import SwiftUI

// MARK: - نماذج البيانات الأساسية
struct Message: Identifiable, Codable {
    let id: UUID
    let senderPhone: String
    let receiverPhone: String
    let text: String
    let timestamp: Date
}

struct ChatUser: Identifiable, Codable {
    var id: String { phoneNumber }
    let phoneNumber: String
    let name: String
}

// MARK: - محرك إدارة التطبيق
class ChatManager: ObservableObject {
    @Published var currentUserPhone: String = "" {
        didSet {
            UserDefaults.standard.set(currentUserPhone, forKey: "saved_phone")
        }
    }
    @Published var isLoggedIn: Bool = false
    @Published var activeChats: [ChatUser] = []
    @Published var messages: [Message] = []
    
    init() {
        if let savedPhone = UserDefaults.standard.string(forKey: "saved_phone"), !savedPhone.isEmpty {
            self.currentUserPhone = savedPhone
            self.isLoggedIn = true
        }
        
        activeChats = [
            ChatUser(phoneNumber: "0500000000", name: "الدعم الفني 👋"),
            ChatUser(phoneNumber: "0511111111", name: "المطور بدر 🚀")
        ]
        
        messages = [
            Message(id: UUID(), senderPhone: "0500000000", receiverPhone: "all", text: "مرحباً بك في نظام المراسلة الآمن الجديد! 💬", timestamp: Date()),
            Message(id: UUID(), senderPhone: "0511111111", receiverPhone: "all", text: "تم ترقية الواجهة وحل مشكلة الكيبورد جذرياً يا بطل. 👍", timestamp: Date())
        ]
    }
    
    func sendMessage(to receiver: String, text: String) {
        let newMessage = Message(
            id: UUID(),
            senderPhone: currentUserPhone,
            receiverPhone: receiver,
            text: text,
            timestamp: Date()
        )
        self.messages.append(newMessage)
    }
    
    func startNewChat(phoneNumber: String, name: String) {
        if !activeChats.contains(where: { $0.phoneNumber == phoneNumber }) {
            let newUser = ChatUser(phoneNumber: phoneNumber, name: name)
            activeChats.append(newUser)
        }
    }
    
    func logout() {
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

// MARK: - 1. واجهة تسجيل الدخول المضادة للاختفاء (قسرية الألوان والتمرير)
struct LoginView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var phoneNumber = ""
    @FocusState private var isKeyfocused: Bool
    
    var isPhoneValid: Bool {
        return phoneNumber.count >= 10 && phoneNumber.allSatisfy { $0.isNumber }
    }
    
    var body: some View {
        ZStack {
            // إجبار الخلفية على اللون الأبيض الصافي لكسر الوضع الداكن في التطبيق المترجم
            Color.white.ignoresSafeArea()
            
            // حاوية تمرير مرنة تسمح بسحب الشاشة لأسفل عند ظهور الكيبورد
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 30) {
                    
                    Spacer()
                        .frame(height: 40)
                    
                    // شعار التطبيق المحدث والأنيق
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 110, height: 110)
                        Text("💬")
                            .font(.system(size: 55))
                    }
                    
                    VStack(spacing: 12) {
                        Text("تطبيق المراسلة الفورية")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black) // خط أسود صريح
                        
                        Text("المراسلة الآمنة برقم الجوال المباشر")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    // حقل الإدخال الذكي في موقع مرتفع ومحمي
                    VStack(alignment: .leading, spacing: 8) {
                        Text("أدخل رقم الجوال")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                        
                        TextField("05xxxxxxxx", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .focused($isKeyfocused)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 16)
                            .background(Color(red: 0.95, green: 0.95, blue: 0.97)) // خلفية رمادية فاتحة جداً تفتح النفس
                            .cornerRadius(15)
                            .foregroundColor(.black) // تلوين نص الرقم بالأسود الصريح
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(isPhoneValid ? Color.blue : Color.gray.opacity(0.2), lineWidth: 2)
                            )
                    }
                    .padding(.horizontal, 25)
                    .padding(.top, 10)
                    
                    // زر الدخول المحدث
                    Button(action: {
                        isKeyfocused = false
                        chatManager.currentUserPhone = phoneNumber
                        chatManager.isLoggedIn = true
                    }) {
                        HStack {
                            Text("دخول سريع وآمن")
                            Image(systemName: "arrow.left.circle.fill")
                        }
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isPhoneValid ? Color.blue : Color.gray.opacity(0.4))
                        .cornerRadius(15)
                        .shadow(color: isPhoneValid ? Color.blue.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                    }
                    .disabled(!isPhoneValid)
                    .padding(.horizontal, 25)
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .onTapGesture {
            isKeyfocused = false
        }
    }
}

// MARK: - 2. واجهة قائمة المحادثات الكاملة
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
                                ZStack {
                                    Circle().fill(Color.blue.opacity(0.1))
                                    Text(user.name.prefix(1)).bold().foregroundColor(.blue)
                                }
                                .frame(width: 50, height: 50)
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(user.name).font(.headline).foregroundColor(.black)
                                    Text(user.phoneNumber).font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("المحادثات")
            .navigationBarItems(
                leading: Button("خروج") { chatManager.logout() }.foregroundColor(.red),
                trailing: Button(action: { showAddChat = true }) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            )
            .sheet(isPresented: $showAddChat) {
                VStack(spacing: 20) {
                    Text("بدء محادثة جديدة").font(.title2).bold().foregroundColor(.black)
                    
                    TextField("اسم الشخص", text: $newChatName)
                        .padding().background(Color(.systemGray6)).cornerRadius(12).foregroundColor(.black)
                    
                    TextField("رقم الجوال", text: $newChatPhone)
                        .keyboardType(.phonePad)
                        .padding().background(Color(.systemGray6)).cornerRadius(12).foregroundColor(.black)
                    
                    Button("إضافة القائمة") {
                        if !newChatPhone.isEmpty && !newChatName.isEmpty {
                            chatManager.startNewChat(phoneNumber: newChatPhone, name: newChatName)
                            newChatPhone = ""
                            newChatName = ""
                            showAddChat = false
                        }
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(12)
                }
                .padding(30)
                .background(Color.white.ignoresSafeArea())
            }
        }
    }
}

// MARK: - 3. غرفة الدردشة الكاملة
struct ChatRoomView: View {
    let targetUser: ChatUser
    @EnvironmentObject var chatManager: ChatManager
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(chatManager.messages) { msg in
                        let isCurrentUser = msg.senderPhone == chatManager.currentUserPhone
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
                TextField("اكتب رسالتك هنا...", text: $messageText)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(25)
                    .foregroundColor(.black)
                
                Button(action: {
                    chatManager.sendMessage(to: targetUser.phoneNumber, text: messageText)
                    messageText = ""
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(12)
                        .background(messageText.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(25)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
            .background(Color.white)
        }
        .navigationTitle(targetUser.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
