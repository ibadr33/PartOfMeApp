import SwiftUI

// MARK: - نماذج البيانات (Models)
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

// MARK: - محرك إدارة المحادثات المحصن
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

// MARK: - 1. واجهة تسجيل الدخول المطورة
struct LoginView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var phoneNumber = ""
    @FocusState private var isKeyfocused: Bool
    
    // تم تغيير التحقق هنا ليكون داخلي ومباشر متوافق مع المترجم السحابي
    var isPhoneValid: Bool {
        return phoneNumber.count >= 10 && phoneNumber.allSatisfy { $0.isNumber }
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 120, height: 120)
                    Text("💬")
                        .font(.system(size: 60))
                }
                
                VStack(spacing: 8) {
                    Text("مرحباً بك")
                        .font(.system(size: 34, weight: .bold))
                    Text("سجل دخولك برقم الجوال المباشر")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 10) {
                    TextField("05xxxxxxxx", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .focused($isKeyfocused)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(isPhoneValid ? Color.blue : Color.clear, lineWidth: 1.5)
                        )
                }
                .padding(.horizontal, 30)
                
                Button(action: {
                    isKeyfocused = false
                    chatManager.currentUserPhone = phoneNumber
                    chatManager.isLoggedIn = true
                }) {
                    Text("دخول سريع")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isPhoneValid ? Color.blue : Color.gray.opacity(0.5))
                        .cornerRadius(15)
                }
                .disabled(!isPhoneValid)
                .padding(.horizontal, 30)
                .padding(.top, 15)
                
                Spacer()
            }
            .padding()
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
                                Text(user.name).font(.headline)
                                Text(user.phoneNumber).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
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
                    Text("بدء محادثة جديدة").font(.title2).bold()
                    
                    TextField("اسم الشخص", text: $newChatName)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                    
                    TextField("رقم الجوال", text: $newChatPhone)
                        .keyboardType(.phonePad)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                    
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
            }
        }
    }
}

// MARK: - 3. غرفة الدردشة الكاملة والذكية
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
                                .foregroundColor(isCurrentUser ? .white : .primary)
                                .cornerRadius(16)
                            if !isCurrentUser { Spacer() }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            
            HStack(spacing: 10) {
                TextField("اكتب رسالتك هنا...", text: $messageText)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(25)
                
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
        }
        .navigationTitle(targetUser.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
