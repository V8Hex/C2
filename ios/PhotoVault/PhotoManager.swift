import UIKit
import Photos

class PhotoManager {
    
    static let shared = PhotoManager()
    private init() {}
    
    // MARK: - Authorization
    func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            completion(false)
        }
    }
    
    // MARK: - Photo Count
    func getTotalPhotoCount() -> Int {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeiTunesSynced, .typeCloudShared]
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        return result.count
    }
    
    // MARK: - Fetch Photos
    func fetchPhotos(count: Int, offset: Int, completion: @escaping ([(Data, String)]) -> Void) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeiTunesSynced, .typeCloudShared]
        
        let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard offset < allAssets.count else {
            completion([])
            return
        }
        
        let endIndex = min(offset + count, allAssets.count)
        var results: [(Data, String)] = []
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.resizeMode = .none
        
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.photovault.photofetch", attributes: .concurrent)
        let lock = NSLock()
        
        for i in offset..<endIndex {
            let asset = allAssets.object(at: i)
            group.enter()
            queue.async {
                imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
                    if let imageData = data {
                        let jpegData: Data
                        if let image = UIImage(data: imageData),
                           let jpeg = image.jpegData(compressionQuality: 0.85) {
                            jpegData = jpeg
                        } else {
                            jpegData = imageData
                        }
                        lock.lock()
                        results.append((jpegData, asset.localIdentifier))
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(results)
        }
    }
    
    // MARK: - Metadata
    func fetchAllPhotoMetadata() -> [[String: Any]] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var metadata: [[String: Any]] = []
        let formatter = ISO8601DateFormatter()
        
        allAssets.enumerateObjects { asset, _, _ in
            var info: [String: Any] = [
                "localIdentifier": asset.localIdentifier,
                "pixelWidth": asset.pixelWidth,
                "pixelHeight": asset.pixelHeight,
                "isFavorite": asset.isFavorite,
                "mediaType": asset.mediaType.rawValue,
                "sourceType": asset.sourceType.rawValue
            ]
            
            if let creationDate = asset.creationDate {
                info["creationDate"] = formatter.string(from: creationDate)
            }
            if let modificationDate = asset.modificationDate {
                info["modificationDate"] = formatter.string(from: modificationDate)
            }
            if let location = asset.location {
                info["latitude"] = location.coordinate.latitude
                info["longitude"] = location.coordinate.longitude
            }
            
            let resources = PHAssetResource.assetResources(for: asset)
            if let primary = resources.first {
                info["filename"] = primary.originalFilename
                info["uniformTypeIdentifier"] = primary.uniformTypeIdentifier
                if let fileSize = primary.value(forKey: "fileSize") as? Int64 {
                    info["fileSize"] = fileSize
                }
            }
            
            metadata.append(info)
        }
        
        return metadata
    }
}
