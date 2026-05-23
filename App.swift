import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers

// MARK: - نموذج بيانات الفيديوهات
struct VideoFile: Identifiable, Equatable {
    let id: UUID = UUID()
    var asset: PHAsset? = nil     // إذا كان من الاستوديو
    var fileURL: URL? = nil       // إذا كان من تطبيق الملفات
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

// MARK: - محرك الفحص والربط الذكي
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
        self.hasPhotoPermission = (status == .authorized || status == .limited)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.hasPhotoPermission = (newStatus == .authorized || newStatus == .limited)
                }
            }
        }
    }
    
    // 1. فحص الاستوديو (Photos Library)
    func scanDeviceGallery() {
        if !hasPhotoPermission { checkPhotoLibraryPermission(); return }
        
        self.isScanning = true
        self.scanProgress = 0.0
        self.duplicatedGroups = []
        self.statusMessage = "جاري قراءة الفيديوهات من الاستوديو..."
        
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
                let visualHash = self.generateHashForAsset(asset: asset, index: index)
                
                var thumb: UIImage? = nil
                imageManager.requestImage(for: asset, targetSize: CGSize(width: 150, height: 150), contentMode: .aspectFill, options: requestOptions) { img, _ in
                    thumb = img
                }
                
                discovered.append(VideoFile(asset: asset, name: fileName, duration: asset.duration, thumbnail: thumb, visualHash: visualHash))
                
                self.updateProgress(current: index + 1, total: total, name: fileName)
            }
            
            self.processDuplicatedGroups(videos: discovered)
        }
    }
    
    // 2. فحص المجلدات المحددة من تطبيق الملفات (Files App)
    func scanSelectedFolder(url: URL) {
        // طلب صلاحية أمنية من نظام iOS لقراءة المجلد الخارجي الصادر من تطبيق الملفات
        guard url.startAccessingSecurityScopedResource() else {
            self.statusMessage = "فشل الوصول للمجلد المحدد، تأكد من صلاحيات النظام."
            return
        }
        
        self.isScanning = true
        self.scanProgress = 0.0
        self.duplicatedGroups = []
        self.statusMessage = "جاري قراءة محتويات المجلد المحدد..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            defer { url.stopAccessingSecurityScopedResource() }
            
            let fileManager = FileManager.default
            // جلب ملفات الفيديوهات فقط وتخطي المجلدات الفرعية لتسريع الأداء
            guard let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                self.updateStatus(scanning: false, msg: "المجلد فارغ أو غير قابل للقراءة")
                return
            }
            
            // فلترة الملفات التي تنتمي لعائلة الفيديوهات فقط
            let videoURLs = files.filter { url in
                if let type = UTType(filenameExtension: url.pathExtension) {
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
                
                let visualHash = self.generateHashForURL(url: fileURL, index: index)
                let thumb = self.generateThumbnailForURL(url: fileURL)
                
                discovered.append(VideoFile(fileURL: fileURL, name: fileName, duration: duration.isNaN ? 0.0 : duration, thumbnail: thumb, visualHash: visualHash))
                
                self.updateProgress(current: index + 1, total: total, name: fileName)
            }
            
            self.processDuplicatedGroups(videos: discovered)
        }
    }
    
    // معالجة وفرز المجموعات المتطابقة بصرياً
    private func processDuplicatedGroups(videos: [VideoFile]) {
        let grouped = Dictionary(grouping: videos, by: { $0.visualHash })
        var finalGroups: [VideoGroup] = []
        
        for (hash, list) in grouped where list.count > 1 {
            let title = "مجموعة مكررات: \(list.first?.name ?? "مقطع متطابق")"
            finalGroups.append(VideoGroup(title: title, videos: list))
        }
        
        DispatchQueue.main.async {
            self.duplicatedGroups = finalGroups
            self.isScanning = false
            self.statusMessage = finalGroups.isEmpty ? "رائع! لا توجد ملفات مكررة بصرياً." : "تم العثور على \(finalGroups.count) مجموعات مكررة."
        }
    }
    
    // استخراج الهاش للألبوم
    private func generateHashForAsset(asset: PHAsset, index: Int) -> String {
        var hash = "hash_gallery_\(index)"
        let semaphore = DispatchSemaphore(value: 0)
        PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, _ in
            if let valid = avAsset { hash = self.extractVisualHashFromAVAsset(valid, fallback: hash) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3.0)
        return hash
    }
    
    // استخراج الهاش للملف
    private func generateHashForURL(url: URL, index: Int) -> String {
        let asset = AVAsset(url: url)
        return self.extractVisualHashFromAVAsset(asset, fallback: "hash_file_\(index)")
    }
    
    private func extractVisualHashFromAVAsset(_ asset: AVAsset, fallback: String) -> String {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 2.0, preferredTimescale: 60)
        if let imgRef = try? generator.copyCGImage(at: time, actualTime: nil) {
            return "vhash_\(imgRef.width)x\(imgRef.height)_\(imgRef.bytesPerRow)"
        }
        return fallback
    }
    
    private func generateThumbnailForURL(url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1.0, preferredTimescale: 60)
        if let imgRef = try? generator.copyCGImage(at: time, actualTime: nil) {
            return UIImage(cgImage: imgRef)
        }
        return nil
    }
    
    private func updateProgress(current: Int, total: Int, name: String) {
        DispatchQueue.main.async {
            self.scanProgress = Double(current) / Double(total)
            self.statusMessage = "جاري معالجة \(current) من أصل \(total): \(name)"
        }
    }
    
    private func updateStatus(scanning: Bool, msg: String) {
        DispatchQueue.main.async {
            self.isScanning = scanning
            self.statusMessage = msg
        }
    }
    
    // ميزة الحذف الفعلي والدائم من الجهاز لجميع المصادر
    func deleteVideo(from group: VideoGroup, video: VideoFile) {
        if let asset = video.asset {
            // حذف من الاستوديو
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
            }) { success, _ in
                if success { self.removeVideoFromUI(group: group, video: video) }
            }
        } else if let fileURL = video.fileURL {
            // حذف من تطبيق الملفات
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

// MARK: - واجهات التطبيق الرسومية
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
                    FolderPicker { url in manager.scanSelectedFolder(url: url) }
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
                    Text("الفحص الهجين الذكي")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                    Text("ابحث في الصور أو المجلدات الحرة")
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

// MARK: - الجسر الرابط لاستدعاء مستعرض نظام الملفات (Document Picker Bridge)
struct FolderPicker: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // إنشاء منتقي يركز على المجلدات المفتوحة (Folders/Directories) للسماح بفحص حزمة كاملة
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
            if let selectedURL = urls.first { parent.onFolderSelected(selectedURL) }
        }
    }
}
