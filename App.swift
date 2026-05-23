import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers

// MARK: - نماذج البيانات الثابتة
struct VideoFile: Identifiable, Equatable {
    let id: UUID = UUID()
    var asset: PHAsset? = nil
    var fileURL: URL? = nil
    let name: String
    let duration: TimeInterval
    var thumbnail: UIImage?
    let visualHash: String
}

struct VideoGroup: Identifiable {
    let id: UUID = UUID()
    let title: String
    var videos: [VideoFile]
}

// MARK: - محرك الفحص الآمن والمحمي ضد الـ Crash
class VideoPurgerManager: ObservableObject {
    @Published var duplicatedGroups: [VideoGroup] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var statusMessage: String = "اختر مصدر الفحص لبدء سحب ومقارنة الفيديوهات الحقيقية"
    @Published var hasPhotoPermission: Bool = false
    
    init() {
        checkPhotoLibraryPermission()
    }
    
    func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async {
            self.hasPhotoPermission = (status == .authorized || status == .limited)
        }
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.hasPhotoPermission = (newStatus == .authorized || newStatus == .limited)
                }
            }
        }
    }
    
    func scanDeviceGallery() {
        guard hasPhotoPermission else {
            checkPhotoLibraryPermission()
            return
        }
        
        self.isScanning = true
        self.scanProgress = 0.0
        self.duplicatedGroups = []
        self.statusMessage = "جاري استعلام ملفات الاستوديو..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            let total = fetchResult.count
            
            guard total > 0 else {
                self.updateStatus(scanning: false, msg: "لم يتم العثور على فيديوهات في الاستوديو")
                return
            }
            
            var discovered: [VideoFile] = []
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            
            for index in 0..<total {
                let asset = fetchResult.object(at: index)
                let resources = PHAssetResource.assetResources(for: asset)
                let fileName = resources.first?.originalFilename ?? "مقطع_استوديو_\(index).mp4"
                
                let width = asset.pixelWidth
                let height = asset.pixelHeight
                let duration = asset.duration
                let visualHash = "vhash_ph_\(width)x\(height)_\(Int(duration))"
                
                var thumb: UIImage? = nil
                imageManager.requestImage(for: asset, targetSize: CGSize(width: 120, height: 120), contentMode: .aspectFill, options: requestOptions) { img, _ in
                    thumb = img
                }
                
                discovered.append(VideoFile(asset: asset, name: fileName, duration: duration, thumbnail: thumb, visualHash: visualHash))
                self.updateProgress(current: index + 1, total: total, name: fileName)
            }
            
            self.processDuplicatedGroups(videos: discovered)
        }
    }
    
    func scanSelectedFolder(url: URL) {
        self.isScanning = true
        self.scanProgress = 0.0
        self.duplicatedGroups = []
        self.statusMessage = "جاري قراءة المجلد المختار..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard url.startAccessingSecurityScopedResource() else {
                self.updateStatus(scanning: false, msg: "فشل الوصول للمجلد، تحقق من صلاحيات النظام.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                self.updateStatus(scanning: false, msg: "المجلد فارغ أو غير قابل للقراءة")
                return
            }
            
            let videoURLs = files.filter { file in
                if let type = UTType(filenameExtension: file.pathExtension) {
                    return type.conforms(to: .video) || type.conforms(to: .movie)
                }
                return false
            }
            
            let total = videoURLs.count
            guard total > 0 else {
                self.updateStatus(scanning: false, msg: "لا توجد ملفات فيديو مدعومة داخل هذا المجلد")
                return
            }
            
            var discovered: [VideoFile] = []
            
            for (index, fileURL) in videoURLs.enumerated() {
                let fileName = fileURL.lastPathComponent
                let asset = AVAsset(url: fileURL)
                let duration = CMTimeGetSeconds(asset.duration)
                
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1.0, preferredTimescale: 60)
                
                var thumb: UIImage? = nil
                var visualHash = "vhash_file_\(index)"
                
                if let imgRef = try? generator.copyCGImage(at: time, actualTime: nil) {
                    thumb = UIImage(cgImage: imgRef)
                    visualHash = "vhash_fl_\(imgRef.width)x\(imgRef.height)_\(imgRef.bytesPerRow)"
                }
                
                discovered.append(VideoFile(fileURL: fileURL, name: fileName, duration: duration.isNaN ? 0.0 : duration, thumbnail: thumb, visualHash: visualHash))
                self.updateProgress(current: index + 1, total: total, name: fileName)
            }
            
            self.processDuplicatedGroups(videos: discovered)
        }
    }
    
    private func processDuplicatedGroups(videos: [VideoFile]) {
        let grouped = Dictionary(grouping: videos, by: { $0.visualHash })
        var finalGroups: [VideoGroup] = []
        
        for (hash, list) in grouped where list.count > 1 {
            let title = "مجموعة مكررة: \(list.first?.name ?? "ملف مكرر")"
            finalGroups.append(VideoGroup(title: title, videos: list))
        }
        
        DispatchQueue.main.async {
            self.duplicatedGroups = finalGroups
            self.isScanning = false
            self.statusMessage = finalGroups.isEmpty ? "رائع! لا توجد ملفات مكررة بصرياً." : "تم العثور على \(finalGroups.count) مجموعات مكررة."
        }
    }
    
    private func updateProgress(current: Int, total: Int, name: String) {
        DispatchQueue.main.async {
            self.scanProgress = Double(current) / Double(total)
            self.statusMessage = "جاري تحليل \(current) من أصل \(total): \(name)"
        }
    }
    
    private func updateStatus(scanning: Bool, msg: String) {
        DispatchQueue.main.async {
            self.isScanning = scanning
            self.statusMessage = msg
        }
    }
    
    func deleteVideo(from group: VideoGroup, video: VideoFile) {
        if let asset = video.asset {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
            }) { success, _ in
                if success { self.removeVideoFromUI(group: group, video: video) }
            }
        } else if let fileURL = video.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
            self.removeVideoFromUI(group: group, video: video)
        }
    }
    
    func keepOnlyOne(in group: VideoGroup) {
        let targets = group.videos.dropFirst()
        for video in targets {
            deleteVideo(from: group, video: video)
        }
    }
    
    private func removeVideoFromUI(group: VideoGroup, video: VideoFile) {
        DispatchQueue.main.async {
            if let gIndex = self.duplicatedGroups.firstIndex(where: { $0.id == group.id }) {
                self.duplicatedGroups[gIndex].videos.removeAll(where: { $0.id == video.id })
                if self.duplicatedGroups[gIndex].videos.count <= 1 {
                    self.duplicatedGroups.remove(at: gIndex)
                }
            }
        }
    }
}

// MARK: - واجهات العرض المستقرة
@main
struct StudioPurgerApp: App {
    @StateObject private var manager = VideoPurgerManager()
    var body: some Scene {
        WindowGroup {
            MainDashboardView().environmentObject(manager)
        }
    }
}

struct MainDashboardView: View {
    @EnvironmentObject var manager: VideoPurgerManager
    @State private var showFolderPicker = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.96, green: 0.96, blue: 0.98).ignoresSafeArea()
                VStack(spacing: 16) {
                    HeaderStatusCard(showFolderPicker: $showFolderPicker)
                    
                    if manager.isScanning {
                        ScanProgressContainer()
                    } else if manager.duplicatedGroups.isEmpty {
                        EmptyStateContainer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(manager.duplicatedGroups) { group in
                                    DuplicatedGroupCard(group: group)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .navigationTitle("منزّه الاستوديو والملفات")
                .sheet(isPresented: $showFolderPicker) {
                    FolderPicker { url in
                        showFolderPicker = false
                        manager.scanSelectedFolder(url: url)
                    }
                }
            }
        }
    }
}

struct HeaderStatusCard: View {
    @EnvironmentObject var manager: VideoPurgerManager
    @Binding var showFolderPicker: Bool
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الفحص الهجين الآمن")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                    Text("فحص فوري دون تجمد للواجهة")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { manager.scanDeviceGallery() }) {
                        Text("الاستوديو").font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.blue).cornerRadius(10)
                    }
                    Button(action: { showFolderPicker = true }) {
                        Text("الملفات 📁").font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.orange).cornerRadius(10)
                    }
                }
                .disabled(manager.isScanning)
            }
            Divider()
            Text(manager.statusMessage).font(.system(size: 11, weight: .medium)).foregroundColor(.blue).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding().background(Color.white).cornerRadius(16).padding(.horizontal).padding(.top, 10)
    }
}

struct DuplicatedGroupCard: View {
    let group: VideoGroup
    @EnvironmentObject var manager: VideoPurgerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.title).font(.system(size: 13, weight: .bold)).foregroundColor(.black).lineLimit(1)
                Spacer()
                Button(action: { manager.keepOnlyOne(in: group) }) {
                    Text("إبقاء نسخة").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Color.red).cornerRadius(8)
                }
            }
            Divider()
            
            ForEach(group.videos) { video in
                HStack(spacing: 12) {
                    if let img = video.thumbnail {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 60, height: 60).cornerRadius(8).clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)).frame(width: 60, height: 60)
                            .overlay(Image(systemName: video.fileURL != nil ? "doc.fill" : "video").foregroundColor(.gray))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.name).font(.system(size: 12, weight: .medium)).foregroundColor(.black).lineLimit(1)
                        Text(video.fileURL != nil ? "المصدر: تطبيق الملفات" : "المصدر: مكتبة الصور").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { manager.deleteVideo(from: group, video: video) }) {
                        Image(systemName: "trash").foregroundColor(.red).padding(8).background(Color.red.opacity(0.05)).clipShape(Circle())
                    }
                }
            }
        }
        .padding().background(Color.white).cornerRadius(16)
    }
}

struct ScanProgressContainer: View {
    @EnvironmentObject var manager: VideoPurgerManager
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView(value: manager.scanProgress).progressViewStyle(LinearProgressViewStyle(tint: Color.blue)).padding(.horizontal, 40)
            Text("\(Int(manager.scanProgress * 100))%").font(.system(size: 22, weight: .bold)).foregroundColor(.blue)
            Text(manager.statusMessage).font(.system(size: 12)).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
    }
}

struct EmptyStateContainer: View {
    @EnvironmentObject var manager: VideoPurgerManager
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 50)).foregroundColor(.gray.opacity(0.4))
            Text(manager.statusMessage).font(.system(size: 13)).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPicker
        init(_ parent: FolderPicker) { self.parent = parent }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedURL = urls.first else { return }
            DispatchQueue.main.async {
                self.parent.onFolderSelected(selectedURL)
            }
        }
    }
}
