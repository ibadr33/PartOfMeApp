import SwiftUI
import CoreHaptics

struct TemporaryMessage: Identifiable, Sendable {
    let id: UUID
    let content: String
    let timestamp: Date
}

@main
struct PartOfMeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var isPaired = false
    @State private var messageText = ""
    @State private var activeMessage: TemporaryMessage? = nil
    @State private var countdown = 7
    @State private var timer: Timer? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !isPaired {
                VStack(spacing: 30) {
                    Text("🌌").font(.system(size: 60))
                    Text("جزء مني").font(.title).fontWeight(.bold).foregroundColor(.white)
                    Text("اضغط بالأسفل للاقتران الفوري المباشر.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
                    
                    Button(action: { withAnimation { isPaired = true } }) {
                        HStack {
                            Image(systemName: "link")
                            Text("ربط شخصك المفضل")
                        }
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple.opacity(0.3))
                        .foregroundColor(.purple)
                        .cornerRadius(15)
                    }
                    .padding(.horizontal, 40)
                }
            } else {
                VStack {
                    if let msg = activeMessage {
                        VStack(spacing: 20) {
                            Text(msg.content)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding()
                                .opacity(countdown > 0 ? 1 : 0)
                                .scaleEffect(countdown > 0 ? 1 : 0.8)
                            
                            Text("\(countdown)")
                                .foregroundColor(.purple)
                                .font(.title)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        VStack(spacing: 40) {
                            Spacer()
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 120, height: 120)
                                .overlay(Circle().stroke(Color.purple, lineWidth: 2))
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { _ in
                                            // محاكاة الاهتزاز للنظام
                                            #if os(iOS)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            #endif
                                        }
                                )
                            Spacer()
                            HStack {
                                TextField("اكتب شيئاً يذوب بعد 7 ثوانٍ...", text: $messageText)
                                    .padding()
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                
                                Button(action: sendMessage) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.purple)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
    }
    
    func sendMessage() {
        guard !messageText.isEmpty else { return }
        activeMessage = TemporaryMessage(id: UUID(), content: messageText, timestamp: Date())
        messageText = ""
        countdown = 7
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 1 {
                countdown -= 1
            } else {
                timer?.invalidate()
                activeMessage = nil
            }
        }
    }
}
