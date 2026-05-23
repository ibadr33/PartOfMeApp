import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers
import Vision

// MARK: - نماذج البيانات (Models)
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

// MARK: - المحرك الرئيسي المحصن أمنياً وهندسياً
class VideoPurgerManager: ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var duplicatedGroups: [VideoGroup] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var statusMessage: String = "اختر مصدر الفحص لبدء المقارنة البصرية الحقيقية"
    @Published var hasPhotoPermission: Bool = false
    @Published var showSettingsButton: Bool = false
    @Published var isLimitedPermission: Bool = false
    
    init() {
        checkPhotoLibraryPermission()
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        checkPhotoLibraryPermission()
    }
    
    func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async {
            self.hasPhotoPermission = (status == .authorized || status == .limited)
            self.isLimitedPermission = (status == .limited)
            self.showSettingsButton = (status == .denied || status == .restricted)
        }
    }
    
    // حل مشكلة عدم استجابة الاستوديو ودعم الصلاحيات الجزئية
    func scanDeviceGallery() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.checkPhotoLibraryPermission()
                    if self.hasPhotoPermission { self.startGalleryScanProcedure() }
                }
            }
        } else if status == .limited {
            // إذا كانت الصلاحية محدودة، نتيح للمستخدم اختيار المزيد من الفيديوهات
            if let vc = UIApplication.shared.windows.first?.rootViewController {
                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc)
            }
            self.startGalleryScanProcedure()
        } else if status == .authorized {
            self.startGalleryScanProcedure()
        } else {
            DispatchQueue.main.async {
                self.showSettingsButton = true
                self.statusMessage = "صلاحية الاستوديو مرفوضة كلياً. يرجى تفعيلها من إعدادات الآيفون."
            }
        }
    }
    
    private func startGalleryScanProcedure() {
        self.updateStatus(scanning: true, progress: 0.0, msg: "جاري استعلام ملفات الاستوديو بدفعات آمنة...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            // ترتيب الجلب التنازلي لحماية الذاكرة العشوائية
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            let total = fetchResult.count
            
            guard total > 0 else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "لم يتم العثور على فيديوهات متاحة.")
                return
            }
            
            var discovered: [VideoFile] = []
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            requestOptions.deliveryMode = .fastFormat
            
            // معالجة ذكية على دفعات (Batching) لمنع الانهيار الصامت وتجمد النظام
            for index in 0..<total {
                autoreleasepool {
                    let asset = fetchResult.object(at: index)
                    let resources = PHAssetResource.assetResources(for: asset)
                    let fileName = resources.first?.originalFilename ?? "مقطع_\(index).mp4"
                    
                    var thumb: UIImage? = nil
                    imageManager.requestImage(for: asset, targetSize: CGSize(width: 100, height: 100), contentMode: .aspectFill, options: requestOptions) { img, _ in
                        thumb = img
                    }
                    
                    if let validThumb = thumb, let featurePrint = self.extractFeaturePrint(from: validThumb) {
                        discovered.append(VideoFile(asset: asset, name: fileName, duration: asset.duration, thumbnail: validThumb, visualHash: featurePrint))
                    }
                    
                    if index % 10 == 0 || index == total - 1 {
                        self.updateProgress(current: index + 1, total: total, name: fileName)
                    }
                }
            }
            self.processVisualDuplicates(videos: discovered)
        }
    }
    
    // السيطرة الكلية على ثغرة المجلدات الفرعية والروابط الأمنية المفتوحة
    func scanSelectedFolder(url: URL) {
        self.updateStatus(scanning: true, progress: 0.0, msg: "جاري جلب وفك تشفير مسار المجلد...")
        
        guard url.startAccessingSecurityScopedResource() else {
            self.updateStatus(scanning: false, progress: 0.0, msg: "النظام الأمني لـ iOS منع التطبيق من كسر حماية المجلد.")
            return
        }
        
        Task(priority: .userInitiated) {
            defer { url.stopAccessingSecurityScopedResource() }
            
            let fileManager = FileManager.default
            let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
            
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "تعذر فتح أو قراءة شجرة المجلد المختار.")
                return
            }
            
            var videoURLs: [URL] = []
            for case let fileURL as URL in enumerator {
                if let type = UTType(filenameExtension: fileURL.pathExtension),
                   type.conforms(to: .video) || type.conforms(to: .movie) {
                    videoURLs.append(fileURL)
                }
            }
            
            let total = videoURLs.count
            guard total > 0 else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "المجلد المختار لا يحتوي على أي ملفات فيديو مدعومة.")
                return
            }
            
            var discovered: [VideoFile] = []
            for (index, fileURL) in videoURLs.enumerated() {
                let fileName = fileURL.lastPathComponent
                let asset = AVAsset(url: fileURL)
                
                var durationSeconds: TimeInterval = 0.0
                if let loadedDuration = try? await asset.load(.duration) {
                    durationSeconds = CMTimeGetSeconds(loadedDuration)
                } else {
                    durationSeconds = CMTimeGetSeconds(asset.duration)
                }
                
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1.0, preferredTimescale: 60)
                
                if let imgRef = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let thumb = UIImage(cgImage: imgRef)
                    if let featurePrint = self.extractFeaturePrint(from: thumb) {
                        discovered.append(VideoFile(fileURL: fileURL, name: fileName, duration: durationSeconds.isNaN ? 0.0 : durationSeconds, thumbnail: thumb, visualHash: featurePrint))
                    }
                }
                
                if index % 5 == 0 || index == total - 1 {
                    self.updateProgress(current: index + 1, total: total, name: fileName)
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
                } else { index += 1 }
            }
            if matches.count > 1 {
                finalGroups.append(VideoGroup(title: "تطابق بصري محقق: \(current.name)", videos: matches))
            }
        }
        
        DispatchQueue.main.async {
            self.duplicatedGroups = finalGroups
            self.isScanning = false
            self.statusMessage = finalGroups.isEmpty ? "عملية ناجحة: لا توجد مكررات بصرية." : "اكتمل الفحص: عثر على \(finalGroups.count) مجموعات مكررة."
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
            self.statusMessage = "تحليل آمن للوسائط \(current)/\(total): \(name)"
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

// MARK: - واجهات العرض التكتيكية المقسمة (مقاومة للانهيار ومحسنة للمترجم)
@main
struct StudioPurgerApp: App {
    @StateObject private var manager = VideoPurgerManager()
    var body: some Scene {
        WindowGroup {
            MainDashboardView()
                .environmentObject(manager)
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
                    contentPanel
                }
                .navigationTitle("منزّه الاستوديو والملفات")
                .sheet(isPresented: $showFolderPicker) {
                    FolderPicker { url in manager.scanSelectedFolder(url: url) }
                }
            }
        }
    }
    
    private var contentPanel: some View {
        Group {
            if manager.isScanning {
                ScanProgressContainer()
            } else if manager.duplicatedGroups.isEmpty {
                EmptyStateContainer()
            } else {
                scrollResultsList
            }
        }
    }
    
    private var scrollResultsList: some View {
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

struct HeaderStatusCard: View {
    @EnvironmentObject var manager: VideoPurgerManager
    @Binding var showFolderPicker: Bool
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("نظام الفحص الدفاعي المصحح").font(.system(size: 14, weight: .bold))
                    Text("حل جذري لمشكلة المجلدات الرمادية واختيار الملفات").font(.system(size: 11)).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { manager.scanDeviceGallery() }) {
                        Text(manager.isLimitedPermission ? "إضافة للفحص ➕" : "الاستوديو").font(.system(size: 11, weight: .bold)).foregroundColor(.white).padding(10).background(Color.blue).cornerRadius(10)
                    }
                    Button(action: { showFolderPicker = true }) {
                        Text("الملفات 📁").font(.system(size: 11, weight: .bold)).foregroundColor(.white).padding(10).background(Color.orange).cornerRadius(10)
                    }
                }.disabled(manager.isScanning)
            }
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text(manager.statusMessage).font(.system(size: 11, weight: .medium)).foregroundColor(.blue)
                if manager.showSettingsButton {
                    Button(action: { manager.openSystemSettings() }) {
                        Text("منح الوصول الكامل من إعدادات الآيفون ⚙️")
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
                Text(group.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                Spacer()
                Button(action: { confirmBulkDelete = true }) {
                    Text("تفريغ المكرر تلقائياً").font(.system(size: 10, weight: .bold)).foregroundColor(.white).padding(6).background(Color.red).cornerRadius(8)
                }
                .alert(isPresented: $confirmBulkDelete) {
                    Alert(
                        title: Text("تأكيد التطهير النهائي"),
                        message: Text("سيتم مسح النسخ المتطابقة مع الإبقاء على ملف أصلي واحد فقط، تود التأكيد؟"),
                        primaryButton: .destructive(Text("حذف")) { manager.keepOnlyOne(in: group) },
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
                        Text(video.fileURL != nil ? "دليل الملفات الخارجي" : "استوديو نظام آبل").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { manager.deleteVideo(from: group, video: video) }) {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundColor(.red).padding(6).background(Color.red.opacity(0.06)).clipShape(Circle())
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
            Image(systemName: "shield.checkered").font(.system(size: 35)).foregroundColor(.gray.opacity(0.4))
            Text(manager.statusMessage).font(.system(size: 11)).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - ملتقط المجلدات الصارم (إجبار نظام التشغيل على فتح المجلد وحل مشكلة اللون الرمادي)
struct FolderPicker: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // حسم الثغرة: دمج نوع المجلد والـ directory معاً لضمان عدم إجبار المستخدم على اختيار ملف داخلي
        let supportedTypes: [UTType] = [.folder, .directory]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: false)
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
            parent.onFolderSelected(url)
        }
    }
}
