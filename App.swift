import SwiftUI
import Foundation

// MARK: - إعدادات الربط السحابي الحقيقية
struct SupabaseConfig {
    static let url = "https://bcagoitcioafquzmsgri.supabase.co"
    static let anonKey = "sb_publishable_EK4jspttg3mshfe1ZZ0SMg_NwGLPJ3E"
}

// MARK: - نماذج البيانات المتوافقة مع السيرفر
struct Message: Identifiable, Codable {
    var id: UUID? = UUID()
    let sender_phone: String
    let receiver_phone: String
    let text: String
    
    var idString: String { id?.uuidString ?? UUID().uuidString }
}

struct ChatUser: Identifiable, Codable {
    var id: String { phoneNumber }
    let phoneNumber: String
    let name: String
}

// MARK: - محرك إدارة الاتصال السحابي الحقيقي
class ChatManager: ObservableObject {
    @Published var currentUserPhone: String = "" {
        didSet { UserDefaults.standard.set(currentUserPhone, forKey: "saved_phone") }
    }
    @Published var isLoggedIn: Bool = false
    @Published var activeChats: [ChatUser] = []
    @Published var messages: [Message] = []
    
    private var timer: Timer?
    
    init() {
        if let savedPhone = UserDefaults.standard.string(forKey: "saved_phone"), !savedPhone.isEmpty {
            self.currentUserPhone = savedPhone
            self.isLoggedIn = true
            startFetchingMessages()
        }
        
        activeChats = [
            ChatUser(phoneNumber: "0500000000", name: "الدعم الفني 👋"),
            ChatUser(phoneNumber: "0511111111", name: "الجهاز الثاني 📱")
        ]
    }
    
    func startFetchingMessages() {
        timer?.invalidate()
        fetchMessagesFromCloud()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.fetchMessagesFromCloud()
        }
    }
    
    func stopFetching() {
        timer?.invalidate()
    }
    
    func fetchMessagesFromCloud() {
        guard !currentUserPhone.isEmpty else { return }
        
        let endpoint = "\(SupabaseConfig.url)/rest/v1/messages?select=*"
        guard let url = URL(string: endpoint) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apiKey")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data {
                if let decodedMessages = try? JSONDecoder().decode([Message].self, from: data) {
                    DispatchQueue.main.async {
                        self.messages = decodedMessages
                    }
                }
            }
        }
        .resume()
    }
    
    func sendMessageToCloud(to receiver: String, text: String) {
        let endpoint = "\(SupabaseConfig.url)/rest/v1/messages"
        guard let url = URL(string: endpoint) else { return }
        
        let newMessage = Message(sender_phone: currentUserPhone, receiver_phone: receiver, text: text)
        guard let jsonData = try? JSONEncoder().encode(newMessage) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apiKey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.fetchMessagesFromCloud()
        }
        .resume()
    }
    
    func logout() {
        stopFetching()
        currentUserPhone = ""
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: "saved_phone")
    }
}

// MARK: - التطبيق الأساسي
@main
struct ChatApplication: App {
    @StateObject private var chatManager = ChatManager()
    
    var body: some Scene {
        WindowGroup {
            if chatManager.isLoggedIn {
                MainChatsView()
                    .environmentObject(chatManager)
            } else {
                LoginView()
                    .environmentObject(chatManager)
            }
        }
    }
}

// MARK: - 1. واجهة تسجيل الدخول
struct LoginView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var phoneNumber = ""
    @FocusState private var isKeyfocused: Bool
    
    var isPhoneValid: Bool {
        return phoneNumber.count >= 10 && phoneNumber.allSatisfy { $0.isNumber }
    }
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 30) {
                    Spacer().frame(height: 40)
                    
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.1)).frame(width: 110, height: 110)
                        Text("💬").font(.system(size: 55))
                    }
                    
                    VStack(spacing: 12) {
                        Text("تطبيق المراسلة الحقيقي").font(.system(size: 28, weight: .bold)).foregroundColor(.black)
                        Text("متصل الآن عبر السحابة الآمنة").font(.system(size: 15, weight: .medium)).foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("أدخل رقم الجوال لبدء الاتصال").font(.system(size: 14, weight: .bold)).foregroundColor(.blue)
                        TextField("05xxxxxxxx", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .focused($isKeyfocused)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 16)
                            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                            .cornerRadius(15)
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 25)
                    
                    Button(action: {
                        isKeyfocused = false
                        chatManager.currentUserPhone = phoneNumber
                        chatManager.isLoggedIn = true
                        chatManager.startFetchingMessages()
                    }) {
                        Text("ربط ودخول").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16).background(isPhoneValid ? Color.blue : Color.gray.opacity(0.4)).cornerRadius(15)
                    }
                    .disabled(!isPhoneValid)
                    .padding(.horizontal, 25)
                }
            }
        }
        .onTapGesture { isKeyfocused = false }
    }
}

// MARK: - 2. واجهة قائمة المحادثات
struct MainChatsView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var showAddChat = false
    @State private var newChatPhone = ""
    @State private var newChatName = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()
                List {
                    ForEach(chatManager.activeChats) { user in
                        NavigationLink(destination: ChatRoomView(targetUser: user)) {
                            HStack(spacing: 15) {
                                Circle().fill(Color.blue.opacity(0.1)).frame(width: 50, height: 50)
                                    .overlay(Text(user.name.prefix(1)).bold().foregroundColor(.blue))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(user.name).font(.headline).foregroundColor(.black)
                                    Text(user.phoneNumber).font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("المحادثات السحابية")
            .navigationBarItems(
                leading: Button("خروج") { chatManager.logout() }.foregroundColor(.red),
                trailing: Button(action: { showAddChat = true }) { Image(systemName: "plus.circle.fill").font(.title2) }
            )
            .sheet(isPresented: $showAddChat) {
                VStack(spacing: 20) {
                    Text("إضافة مستخدم للشبكة").font(.title2).bold().foregroundColor(.black)
                    TextField("الاسم", text: $newChatName).padding().background(Color(.systemGray6)).cornerRadius(12).foregroundColor(.black)
                    TextField("رقم الجوال", text: $newChatPhone).keyboardType(.phonePad).padding().background(Color(.systemGray6)).cornerRadius(12).foregroundColor(.black)
                    Button("تأكيد الإضافة") {
                        if !newChatPhone.isEmpty && !newChatName.isEmpty {
                            chatManager.startNewChat(phoneNumber: newChatPhone, name: newChatName)
                            showAddChat = false
                        }
                    }
                    .font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(12)
                }
                .padding(30).background(Color.white.ignoresSafeArea())
            }
        }
    }
}

// MARK: - 3. شاشة غرفة الدردشة الحقيقية
struct ChatRoomView: View {
    let targetUser: ChatUser
    @EnvironmentObject var chatManager: ChatManager
    @State private var messageText = ""
    
    var filteredMessages: [Message] {
        chatManager.messages.filter { msg in
            (msg.sender_phone == chatManager.currentUserPhone && msg.receiver_phone == targetUser.phoneNumber) ||
            (msg.sender_phone == targetUser.phoneNumber && msg.receiver_phone == chatManager.currentUserPhone)
        }
    }
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredMessages, id: \.idString) { msg in
                        let isCurrentUser = msg.sender_phone == chatManager.currentUserPhone
                        HStack {
                            if isCurrentUser { Spacer() }
                            Text(msg.text)
                                .padding(14)
                                .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                                .foregroundColor(isCurrentUser ? .white : .black)
                                .cornerRadius(16)
                            if !isCurrentUser { Spacer() }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .background(Color.white)
            
            HStack(spacing: 10) {
                TextField("اكتب رسالة حقيقية للطرف الآخر...", text: $messageText)
                    .padding(12).background(Color(.systemGray6)).cornerRadius(25).foregroundColor(.black)
                
                Button(action: {
                    chatManager.sendMessageToCloud(to: targetUser.phoneNumber, text: messageText)
                    messageText = ""
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white).padding(12).background(messageText.isEmpty ? Color.gray : Color.blue).cornerRadius(25)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
            .background(Color.white)
        }
        .navigationTitle(targetUser.name)
    }
}
