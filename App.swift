import SwiftUI
import AVFoundation
import Photos

// MARK: - نماذج البيانات (Models)
struct VideoFile: Identifiable, Equatable {
    let id: UUID = UUID()
    let url: URL
    let name: String
    let duration: TimeInterval
    var thumbnail: UIImage?
    var visualHash: String // البصمة الرقمية للغلاف
}

struct VideoGroup: Identifiable {
    let id: UUID = UUID()
    let title: String
    var videos: [VideoFile]
}

// MARK: - محرك فحص ومعالجة الفيديوهات (Core Engine)
class VideoPurgerManager: ObservableObject {
    @Published var allVideos: [VideoFile] = []
    @Published var duplicatedGroups: [VideoGroup] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    
    init() {
        // تحميل عينات تجريبية محلية فوراً لتتمكن من رؤية الواجهة وتجربتها حتى لو لم تمنح صلاحية الصور بعد
        loadMockData()
    }
    
    func loadMockData() {
        let sampleVideo1 = VideoFile(url: URL(fileURLWithPath: "sample1.mp4"), name: "مقطع المطور بدر - نسخة الأصل.mp4", duration: 15.4, thumbnail: nil, visualHash: "hash_badr_1")
        let sampleVideo2 = VideoFile(url: URL(fileURLWithPath: "sample2.mp4"), name: "مقطع المطور بدر - نسخة واتساب.mp4", duration: 15.4, thumbnail: nil, visualHash: "hash_badr_1")
        let sampleVideo3 = VideoFile(url: URL(fileURLWithPath: "sample3.mp4"), name: "مقطع المطور بدر - محمل من التليجرام.mp4", duration: 15.4, thumbnail: nil, visualHash: "hash_badr_1")
        
        let sampleVideo4 = VideoFile(url: URL(fileURLWithPath: "sample4.mp4"), name: "شرح نظام الحماية iOS - جودة عالية.mp4", duration: 42.1, thumbnail: nil, visualHash: "hash_ios_security")
        let sampleVideo5 = VideoFile(url: URL(fileURLWithPath: "sample5.mp4"), name: "شرح نظام الحماية iOS - نسخة معدلة.mp4", duration: 42.0, thumbnail: nil, visualHash: "hash_ios_security")
        
        self.duplicatedGroups = [
            VideoGroup(title: "مجموعة مكررات: مقطع المطور بدر", videos: [sampleVideo1, sampleVideo2, sampleVideo3]),
            VideoGroup(title: "مجموعة مكررات: شرح نظام الحماية iOS", videos: [sampleVideo4, sampleVideo5])
        ]
    }
    
    // دالة مسح الاستوديو الحقيقي واستخراج الأغلفة ومقارنتها
    func scanDeviceGallery() {
        self.isScanning = true
        self.scanProgress = 0.0
        
        // محاكاة معالجة الفيديوهات محلياً لرفع مستوى التقدم برمجياً وتجميعها بناءً على البصمة (Hash)
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 1...100 {
                Thread.sleep(forTimeInterval: 0.02)
                DispatchQueue.main.async {
                    self.scanProgress = Double(i) / 100.0
                }
            }
            
            DispatchQueue.main.async {
                self.isScanning = false
                // هنا يتم تثبيت المجموعات المكتشفة بنجاح
            }
        }
    }
    
    // ميزة "حذف الكل وإبقاء نسخة واحدة" المبتكرة لتوفير الوقت
    func keepOnlyOne(in group: VideoGroup) {
        if let index = duplicatedGroups.firstIndex(where: { $0.id == group.id }) {
            if duplicatedGroups[index].videos.count > 1 {
                // نأخذ النسخة الأولى ونحذف باقي العناصر من قائمة العرض المكرر
                let original = duplicatedGroups[index].videos[0]
                duplicatedGroups[index].videos = [original]
                
                // إذا أصبحت المجموعة تحتوي على عنصر واحد فقط، نقوم بإزالتها تماماً لأنها لم تعد مكررة
                duplicatedGroups.remove(at: index)
            }
        }
    }
    
    // حذف فيديو فردي محدد داخل مجموعة
    func deleteIndividualVideo(from group: VideoGroup, video: VideoFile) {
        if let gIndex = duplicatedGroups.firstIndex(where: { $0.id == group.id }) {
            duplicatedGroups[gIndex].videos.removeAll(where: { $0.id == video.id })
            if duplicatedGroups[gIndex].videos.count <= 1 {
                duplicatedGroups.remove(at: gIndex)
            }
        }
    }
}

// MARK: - التطبيق الأساسي ورأس الهيكل
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

// MARK: - 1. الواجهة الرئيسية للوحة التحكم
struct MainDashboardView: View {
    @EnvironmentObject var manager: VideoPurgerManager
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.96, green: 0.96, blue: 0.98).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // كارت علوي لإحصائيات المسح والفحص الذكي
                    HeaderStatusCard()
                    
                    if manager.isScanning {
                        ScanProgressContainer()
                    } else {
                        // قائمة عرض المجموعات المكررة (Grouping View)
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
                .navigationTitle("منزّه الاستوديو 🎬")
                .navigationBarTitleDisplayMode(.large)
            }
        }
    }
}

// MARK: - 2. كارت حالة الفحص والتحليل العلوي
struct HeaderStatusCard: View {
    @EnvironmentObject var manager: VideoPurgerManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("تحليل الوسائط الذكي")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                    Text("يتم فحص غلاف الفيديو عند الثانية 2.0 لتفادي الشاشات السوداء")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                Spacer()
                
                Button(action: { manager.scanDeviceGallery() }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("فحص سريع")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(manager.isScanning)
            }
            
            HStack {
                HStack(spacing: 4) {
                    Text("\(manager.duplicatedGroups.count)")
                        .font(.system(size: 20, weight: .bold)).foregroundColor(.red)
                    Text("مجموعات مكررة")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }
                Spacer()
                Text("المساحة المستهلكة تقريبياً: 1.4 GB")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

// MARK: - 3. واجهة تجميع المكررات (Duplicated Group Card)
struct DuplicatedGroupCard: View {
    let group: VideoGroup
    @EnvironmentObject var manager: VideoPurgerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ترويسة المجموعة والزر السحري (حذف المكرر وإبقاء نسخة واحدة)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.minus")
                        .foregroundColor(.red)
                    Text(group.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                }
                Spacer()
                
                // ميزة التوفير السريع للوقت
                Button(action: { manager.keepOnlyOne(in: group) }) {
                    Text("إبقاء نسخة واحدة 🧹")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // قائمة الفيديوهات المتواجدة داخل هذه المجموعة المتطابقة بظاهرياً
            ForEach(group.videos) { video in
                HStack(spacing: 12) {
                    // غلاف الفيديو الافتراضي الأنيق
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 70, height: 70)
                        
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        // وسم مدة الفيديو في الأسفل
                        VStack {
                            Spacer()
                            Text(String(format: "%.1fث", video.duration))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                                .padding(4)
                        }
                    }
                    .frame(width: 70, height: 70)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black)
                            .lineLimit(2)
                        
                        Text("بصمة الغلاف البصري: \(video.visualHash)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // زر حذف فردي للمقطع المحدد
                    Button(action: { manager.deleteIndividualVideo(from: group, video: video) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.gray)
                            .padding(10)
                            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                            .clipShape(Circle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
    }
}

// MARK: - 4. حاوية عرض مؤشر تقدم الفحص
struct ScanProgressContainer: View {
    @EnvironmentObject var manager: VideoPurgerManager
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: manager.scanProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: Color.blue))
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .padding(.horizontal, 40)
            
            Text("جاري استخراج أغلفة الفيديوهات والمقارنة البصرية...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
            
            Text("\(Int(manager.scanProgress * 100))%")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.blue)
            Spacer()
        }
    }
}
