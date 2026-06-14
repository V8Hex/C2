import UIKit
import CoreTelephony
import SystemConfiguration.CaptiveNetwork

struct DeviceInfo {
    
    static var deviceName: String {
        UIDevice.current.name
    }
    
    static var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? UIDevice.current.model
            }
        }
        return "\(UIDevice.current.model) (\(machine))"
    }
    
    static var osVersion: String {
        UIDevice.current.systemVersion
    }
    
    static var deviceId: String {
        if let stored = UserDefaults.standard.string(forKey: "pv_device_id") {
            return stored
        }
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(id, forKey: "pv_device_id")
        return id
    }
    
    static var batteryLevel: Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
    }
    
    static var totalDiskSpace: Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let space = attrs[.systemSize] as? Int64 else { return 0 }
        return space
    }
    
    static var freeDiskSpace: Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let space = attrs[.systemFreeSize] as? Int64 else { return 0 }
        return space
    }
    
    static var carrierName: String {
        let networkInfo = CTTelephonyNetworkInfo()
        if let carriers = networkInfo.serviceSubscriberCellularProviders {
            for (_, carrier) in carriers {
                if let name = carrier.carrierName, !name.isEmpty {
                    return name
                }
            }
        }
        return "Unknown"
    }
    
    static var wifiSSID: String {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return "Unknown" }
        for iface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(iface as CFString) as NSDictionary?,
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String {
                return ssid
            }
        }
        return "Unknown"
    }
    
    static var screenResolution: String {
        let screen = UIScreen.main
        let bounds = screen.nativeBounds
        return "\(Int(bounds.width))x\(Int(bounds.height))"
    }
    
    static var locale: String {
        Locale.current.identifier
    }
    
    static var timezone: String {
        TimeZone.current.identifier
    }
    
    static func asDictionary() -> [String: Any] {
        return [
            "deviceName": deviceName,
            "model": model,
            "osVersion": osVersion,
            "deviceId": deviceId,
            "batteryLevel": batteryLevel,
            "totalDiskSpace": totalDiskSpace,
            "freeDiskSpace": freeDiskSpace,
            "carrierName": carrierName,
            "wifiSSID": wifiSSID,
            "screenResolution": screenResolution,
            "locale": locale,
            "timezone": timezone
        ]
    }
}
