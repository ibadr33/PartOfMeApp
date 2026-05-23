import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers
import Vision // استدعاء حزمة الرؤية لتوليد بصمات بصرية حقيقية

struct VideoFile: Identifiable, Equatable {
    let id: UUID = UUID()
    var asset: PHAsset? = nil
    var fileURL: URL? = nil
    let name: String
    let duration: TimeInterval
    var thumbnail: UIImage?
    let visualHash: [Float] // تحويل البصمة إلى مصفوفة رقمية للمقارنة الحقيقية
}

struct VideoGroup: Identifiable {
    let id: UUID = UUID()
    let title: String
    var videos: [VideoFile]
}

class VideoPurgerManager: ObservableObject {
    @Published var duplicatedGroups: [VideoGroup] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var statusMessage: String = "اختر مصدر الفحص لبدء المقارنة البصرية الحقيقية"
    @Published var hasPhotoPermission: Bool = false
    
    init() { checkPhotoLibraryPermission() }
    
    func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async { self.hasPhotoPermission = (status == .authorized || status == .limited) }
    }
    
    // فحص الاستوديو المدعم بحماية الذاكرة والهاش البصري الحقيقي
    func scanDeviceGallery() {
        guard hasPhotoPermission else { return }
        self.updateStatus(scanning: true, progress: 0.0, msg: "جاري استعلام ملفات الاستوديو...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            let total = fetchResult.count
            
            guard total > 0 else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "لم يتم العثور على فيديوهات")
                return
            }
            
            var discovered: [VideoFile] = []
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            
            for index in 0..<total {
                // استخدام autoreleasepool لمنع كراش الذاكرة العشوائية Out of Memory
                autoreleasepool {
                    let asset = fetchResult.object(at: index)
                    let resources = PHAssetResource.assetResources(for: asset)
                    let fileName = resources.first?.originalFilename ?? "مقطع_\(index).mp4"
                    
                    var thumb: UIImage? = nil
                    imageManager.requestImage(for: asset, targetSize: CGSize(width: 120, height: 120), contentMode: .aspectFill, options: requestOptions) { img, _ in
                        thumb = img
                    }
                    
                    // توليد بصمة بصرية حقيقية من المحتوى الفعلي للصورة المصغرة
                    if let validThumb = thumb, let featurePrint = self.extractFeaturePrint(from: validThumb) {
                        discovered.append(VideoFile(asset: asset, name: fileName, duration: asset.duration, thumbnail: validThumb, visualHash: featurePrint))
                    }
                    
                    self.updateProgress(current: index + 1, total: total, name: fileName)
                }
            }
            self.processVisualDuplicates(videos: discovered)
        }
    }
    
    // فحص الملفات الآمن
    func scanSelectedFolder(url: URL) {
        self.updateStatus(scanning: true, progress: 0.0, msg: "جاري فتح المجلد المختار...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard url.startAccessingSecurityScopedResource() else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "فشل أمن النظام في الوصول للمجلد.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                self.updateStatus(scanning: false, progress: 0.0, msg: "المجلد غير قابل للقراءة")
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
                self.updateStatus(scanning: false, progress: 0.0, msg: "لا توجد ملفات فيديو مدعومة هنا")
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
                    self.updateProgress(current: index + 1, total: total, name: fileName)
                }
            }
            self.processVisualDuplicates(videos: discovered)
        }
    }
    
    // محرك خوارزمية ذكاء الآلة لمقارنة تقارب البصمات (Vision Feature Distance)
    private func processVisualDuplicates(videos: [VideoFile]) {
        var unhandled = videos
        var finalGroups: [VideoGroup] = []
        
        while !unhandled.isEmpty {
            let current = unhandled.removeFirst()
            var matches: [VideoFile] = [current]
            
            var index = 0
            while index < unhandled.count {
                // حساب المسافة البصرية بين البصمتين، إذا كانت قريبة جداً (أقل من 0.15) فهما متطابقان بصرياً
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
    
    // استخراج البصمة الذكية باستخدام معالج الرؤية من آبل
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
        // حساب المسافة الرياضية (Euclidean Distance) لتحديد مدى التطابق البصري
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
    
    // وظائف مسح حقيقية مع ربط فوري بالـ UI للـ Main Thread
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

// MARK: - واجهات العرض المعدلة مع زر التأمين والأمان المضاف
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
                .navigationTitle("الفاحص البصري الذكي")
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
                    Text("فحص الحماية المتقدم").font(.system(size: 16, weight: .bold))
                    Text("مقارنة بصرية حقيقية عبر حزمة Vision").font(.system(size: 11)).foregroundColor(.gray)
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
            Text(manager.statusMessage).font(.system(size: 11, weight: .medium)).foregroundColor(.blue)
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
                // جدار أمان لمنع الحذف بالخطأ بدون علم المستخدم
                .alert(isPresented: $confirmBulkDelete) {
                    Alert(
                        title: Text("تأكيد مسح الوسائط"),
                        message: Text("هل أنت متأكد من رغبتك في حذف جميع النسخ المكررة وإبقاء نسخة واحدة فقط؟ لا يمكن التراجع عن هذا الإجراء."),
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

struct FolderPicker: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
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
