import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers
import Vision

// MARK: - نماذج البيانات الثابتة
struct VideoFile: Identifiable, Equatable {
    let id: UUID = UUID()
    var asset: PHAsset? = nil
    var fileURL: URL? = nil
    let name: String
    let duration: TimeInterval
    var thumbnail: UIImage?
    let visualHash: [Float]
}

struct VideoGroup: Identifiable {
    let id: UUID = UUID()
    let title: String
    var videos: [VideoFile]
}

// MARK: - محرك الفحص الآمن والمجرّب
class VideoPurgerManager: ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var duplicatedGroups: [VideoGroup] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var statusMessage: String = "اختر مصدر الفحص لبدء المقارنة البصرية الحقيقية"
    @Published var hasPhotoPermission: Bool = false
    @Published var showSettingsButton: Bool = false
    
    init() {
        checkPhotoLibraryPermission()
        // تسجيل المراقب لضمان استجابة الاستوديو الفورية فور تفعيل الصلاحية
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    // مراقبة التغييرات الحية في صلاحيات النظام
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        checkPhotoLibraryPermission()
    }
    
    func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async {
            self.hasPhotoPermission = (status == .authorized || status == .limited)
            self.showSettingsButton = (status == .denied || status == .restricted)
        }
    }
    
    func scanDeviceGallery() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.hasPhotoPermission = (newStatus == .authorized || newStatus == .limited)
                    self.showSettingsButton = (newStatus == .denied || newStatus == .restricted)
                    if self.hasPhotoPermission {
                        self.startGalleryScanProcedure()
                    }
                }
            }
        } else if status == .authorized || status == .limited {
            self.startGalleryScanProcedure()
        } else {
            DispatchQueue.main.async {
                self.showSettingsButton = true
                self.statusMessage = "صلاحية الاستوديو مرفوضة، يرجى تفعيلها من إعدادات النظام للبدء."
            }
        }
    }
    
    private func startGalleryScanProcedure() {
        self.updateStatus(scanning: true, progress: 0.0, msg: "جاري استعلام ملفات الاستوديو...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            let total = fetchResult.count
            
            guard total > 0 else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "لم يتم العثور على فيديوهات في الاستوديو")
                return
            }
            
            var discovered: [VideoFile] = []
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            
            for index in 0..<total {
                autoreleasepool {
                    let asset = fetchResult.object(at: index)
                    let resources = PHAssetResource.assetResources(for: asset)
                    let fileName = resources.first?.originalFilename ?? "مقطع_\(index).mp4"
                    
                    var thumb: UIImage? = nil
                    imageManager.requestImage(for: asset, targetSize: CGSize(width: 120, height: 120), contentMode: .aspectFill, options: requestOptions) { img, _ in
                        thumb = img
                    }
                    
                    if let validThumb = thumb, let featurePrint = self.extractFeaturePrint(from: validThumb) {
                        discovered.append(VideoFile(asset: asset, name: fileName, duration: asset.duration, thumbnail: validThumb, visualHash: featurePrint))
                    }
                    
                    if index % 5 == 0 || index == total - 1 {
                        self.updateProgress(current: index + 1, total: total, name: fileName)
                    }
                }
            }
            self.processVisualDuplicates(videos: discovered)
        }
    }
    
    func scanSelectedFolder(url: URL) {
        self.updateStatus(scanning: true, progress: 0.0, msg: "جاري فحص المجلد والمجلدات الفرعية...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard url.startAccessingSecurityScopedResource() else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "فشل أمن النظام في الوصول للمجلد.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "المجلد غير قابل للقراءة")
                return
            }
            
            var videoURLs: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                if let type = UTType(filenameExtension: fileURL.pathExtension),
                   type.conforms(to: .video) || type.conforms(to: .movie) {
                    videoURLs.append(fileURL)
                }
            }
            
            let total = videoURLs.count
            guard total > 0 else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "لا توجد ملفات فيديو مدعومة داخل هذا المجلد")
                return
            }
            
            var discovered: [VideoFile] = []
            
            for (index, fileURL) in videoURLs.enumerated() {
                autoreleasepool {
                    let fileName = fileURL.lastPathComponent
                    let asset = AVAsset(url: fileURL)
                    let duration = CMTimeGetSeconds(asset.duration)
                    
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    let time = CMTime(seconds: 1.0, preferredTimescale: 60)
                    
                    if let imgRef = try? generator.copyCGImage(at: time, actualTime: nil) {
                        let thumb = UIImage(cgImage: imgRef)
                        if let featurePrint = self.extractFeaturePrint(from: thumb) {
                            discovered.append(VideoFile(fileURL: fileURL, name: fileName, duration: duration.isNaN ? 0.0 : duration, thumbnail: thumb, visualHash: featurePrint))
                        }
                    }
                    
                    if index % 5 == 0 || index == total - 1 {
                        self.updateProgress(current: index + 1, total: total, name: fileName)
                    }
                }
            }
            self.processVisualDuplicates(videos: discovered)
        }
    }
    
    private func processVisualDuplicates(videos: [VideoFile]) {
        var unhandled = videos
        var finalGroups: [VideoGroup] = []
        
        while !unhandled.isEmpty {
            let current = unhandled.removeFirst()
            var matches: [VideoFile] = [current]
            
            var index = 0
            while index < unhandled.count {
                if let distance = computeDistance(from: current.visualHash, to: unhandled[index].visualHash), distance < 0.15 {
                    matches.append(unhandled.remove(at: index))
                } else {
                    index += 1
                }
            }
            
            if matches.count > 1 {
                finalGroups.append(VideoGroup(title: "مجموعة متطابقة بصرياً: \(current.name)", videos: matches))
            }
        }
        
        DispatchQueue.main.async {
            self.duplicatedGroups = finalGroups
            self.isScanning = false
            self.statusMessage = finalGroups.isEmpty ? "لم يتم العثور على مكررات بصرياً." : "تم العثور على \(finalGroups.count) مجموعات مكررة."
        }
    }
    
    private func extractFeaturePrint(from image: UIImage) -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        
        try? requestHandler.perform([request])
        if let result = request.results?.first as? VNFeaturePrintObservation {
            return result.data.map { Float($0) }
        }
        return nil
    }
    
    private func computeDistance(from hash1: [Float], to hash2: [Float]) -> Float? {
        guard hash1.count == hash2.count else { return nil }
        return sqrt(zip(hash1, hash2).map { pow($0 - $1, 2) }.reduce(0, +))
    }
    
    private func updateProgress(current: Int, total: Int, name: String) {
        DispatchQueue.main.async {
            self.scanProgress = Double(current) / Double(total)
            self.statusMessage = "جاري تحليل \(current) من أصل \(total): \(name)"
        }
    }
    
    private func updateStatus(scanning: Bool, progress: Double, msg: String) {
        DispatchQueue.main.async {
            self.isScanning = scanning
            self.scanProgress = progress
            self.statusMessage = msg
        }
    }
    
    func openSystemSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
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
        for video in targets { deleteVideo(from: group, video: video) }
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

// MARK: - الواجهات الرسومية المستقرة
@main
struct StudioPurgerApp: App {
    @StateObject private var manager = VideoPurgerManager()
    var body: some Scene { WindowGroup { MainDashboardView().environmentObject(manager) } }
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
                    Text("الفحص الهجين المصلح").font(.system(size: 16, weight: .bold))
                    Text("مقارنة بصرية واختيار مجلدات فوري").font(.system(size: 11)).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { manager.scanDeviceGallery() }) {
                        Text("الاستوديو").font(.system(size: 12, weight: .bold)).foregroundColor(.white).padding(10).background(Color.blue).cornerRadius(10)
                    }
                    Button(action: { showFolderPicker = true }) {
                        Text("الملفات 📁").font(.system(size: 12, weight: .bold)).foregroundColor(.white).padding(10).background(Color.orange).cornerRadius(10)
                    }
                }.disabled(manager.isScanning)
            }
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(manager.statusMessage).font(.system(size: 11, weight: .medium)).foregroundColor(.blue)
                if manager.showSettingsButton {
                    Button(action: { manager.openSystemSettings() }) {
                        Text("افتح إعدادات الآيفون لمنح الصلاحية ⚙️")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                            .padding(.vertical, 6).padding(.horizontal, 12).background(Color.red).cornerRadius(8)
                    }
                }
            }
        }.padding().background(Color.white).cornerRadius(16).padding(.horizontal)
    }
}

struct DuplicatedGroupCard: View {
    let group: VideoGroup
    @EnvironmentObject var manager: VideoPurgerManager
    @State private var confirmBulkDelete = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Spacer()
                Button(action: { confirmBulkDelete = true }) {
                    Text("تفريغ المكرر").font(.system(size: 10, weight: .bold)).foregroundColor(.white).padding(6).background(Color.red).cornerRadius(8)
                }
                .alert(isPresented: $confirmBulkDelete) {
                    Alert(
                        title: Text("تأكيد مسح الوسائط"),
                        message: Text("هل أنت متأكد من رغبتك في حذف جميع النسخ المكررة وإبقاء نسخة واحدة فقط؟"),
                        primaryButton: .destructive(Text("حذف دائم")) { manager.keepOnlyOne(in: group) },
                        secondaryButton: .cancel(Text("تراجع"))
                    )
                }
            }
            Divider()
            ForEach(group.videos) { video in
                HStack(spacing: 12) {
                    if let img = video.thumbnail {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 55, height: 55).cornerRadius(6).clipped()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(video.fileURL != nil ? "تطبيق الملفات" : "استوديو الصور").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { manager.deleteVideo(from: group, video: video) }) {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.red).padding(6).background(Color.red.opacity(0.05)).clipShape(Circle())
                    }
                }
            }
        }.padding().background(Color.white).cornerRadius(16)
    }
}

struct ScanProgressContainer: View {
    @EnvironmentObject var manager: VideoPurgerManager
    var body: some View {
        VStack {
            Spacer()
            ProgressView(value: manager.scanProgress).progressViewStyle(LinearProgressViewStyle(tint: Color.blue)).padding(.horizontal, 40)
            Text("\(Int(manager.scanProgress * 100))%").font(.system(size: 20, weight: .bold)).foregroundColor(.blue)
            Text(manager.statusMessage).font(.system(size: 11)).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
    }
}

struct EmptyStateContainer: View {
    @EnvironmentObject var manager: VideoPurgerManager
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "shield.checkerboard").font(.system(size: 40)).foregroundColor(.gray.opacity(0.3))
            Text(manager.statusMessage).font(.system(size: 12)).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - مستعرض المجلدات الصارم والمصلح لجعل المجلدات قابلة للاختيار والضغط
struct FolderPicker: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // استخدام UTType.folder الصارم لمنع ظهور المجلدات بشكل رمادي وضمان تفعيل زر الـ Open فوق مجلد بأكمله
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPicker
        init(_ parent: FolderPicker) { self.parent = parent }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // تمرير الرابط فوراً وبشكل آمن
            parent.onFolderSelected(url)
        }
    }
}
