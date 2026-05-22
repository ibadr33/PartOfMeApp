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

// MARK: - محرك إدارة المحادثات (Chat Engine)
class ChatManager: ObservableObject {
    @Published var currentUserPhone: String = ""
    @Published var isLoggedIn: Bool = false
    @Published var activeChats: [ChatUser] = []
    @Published var messages: [Message] = []
    
    init() {
        // بيانات تجريبية للتأكد من استقرار الواجهة فور تشغيل التطبيق
        activeChats = [
            ChatUser(phoneNumber: "0500000000", name: "بدر (تجربة)")
        ]
        messages = [
            Message(id: UUID(), senderPhone: "0500000000", receiverPhone: "", text: "مرحباً بك في تطبيق المراسلة الجديد! 💬", timestamp: Date())
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
}

// MARK: - نقطة الانطلاق الرسمية للتطبيق (App Entry)
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

// MARK: - الواجهات الرسومية (UI Views)

// 1. واجهة تسجيل الدخول
struct LoginView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var phoneNumber = ""
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            Text("💬")
                .font(.system(size: 80))
            
            Text("تطبيق المراسلة الفورية")
                .font(.title)
                .bold()
            
            Text("المراسلة الآمنة برقم الجوال فقط")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            TextField("أدخل رقم جوالك", text: $phoneNumber)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .multilineTextAlignment(.center)
                .keyboardType(.phonePad)
            
            Button(action: login) {
                Text("دخول")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(phoneNumber.count >= 10 ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(phoneNumber.count < 10)
            
            Spacer()
        }
        .padding(30)
    }
    
    func login() {
        chatManager.currentUserPhone = phoneNumber
        chatManager.isLoggedIn = true
    }
}

// 2. قائمة المحادثات
struct MainChatsView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var showAddChat = false
    @State private var newChatPhone = ""
    @State private var newChatName = ""
    
    var body: some View {
        NavigationView {
            List(chatManager.activeChats) { user in
                NavigationLink(destination: ChatRoomView(targetUser: user)) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(user.name).bold()
                            Text(user.phoneNumber)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("المحادثات")
            .navigationBarItems(trailing: Button(action: { showAddChat = true }) {
                Image(systemName: "plus.circle.fill").font(.title2)
            })
            .sheet(isPresented: $showAddChat) {
                VStack(spacing: 20) {
                    Text("بدء محادثة جديدة").font(.headline).bold()
                    TextField("اسم الشخص", text: $newChatName)
                        .padding().background(Color(.systemGray6)).cornerRadius(10)
                    TextField("رقم الجوال", text: $newChatPhone)
                        .keyboardType(.phonePad)
                        .padding().background(Color(.systemGray6)).cornerRadius(10)
                    
                    Button("إضافة") {
                        if !newChatPhone.isEmpty && !newChatName.isEmpty {
                            chatManager.startNewChat(phoneNumber: newChatPhone, name: newChatName)
                            newChatPhone = ""
                            newChatName = ""
                            showAddChat = false
                        }
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(10)
                }
                .padding(30)
            }
        }
    }
}

// 3. شاشة غرفة الدردشة
struct ChatRoomView: View {
    let targetUser: ChatUser
    @EnvironmentObject var chatManager: ChatManager
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(chatManager.messages.filter {
                        ($0.senderPhone == chatManager.currentUserPhone && $0.receiverPhone == targetUser.phoneNumber) ||
                        ($0.senderPhone == targetUser.phoneNumber && $0.receiverPhone == chatManager.currentUserPhone) ||
                        (targetUser.phoneNumber == "0500000000" && $0.senderPhone == "0500000000")
                    }) { msg in
                        let isCurrentUser = msg.senderPhone == chatManager.currentUserPhone
                        HStack {
                            if isCurrentUser { Spacer() }
                            Text(msg.text)
                                .padding()
                                .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                                .foregroundColor(isCurrentUser ? .white : .black)
                                .cornerRadius(16)
                            if !isCurrentUser { Spacer() }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            HStack {
                TextField("اكتب رسالتك...", text: $messageText)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(messageText.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(20)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .navigationTitle(targetUser.name)
    }
    
    func send() {
        chatManager.sendMessage(to: targetUser.phoneNumber, text: messageText)
        messageText = ""
    }
}
