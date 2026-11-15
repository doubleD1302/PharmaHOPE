import SwiftUI

/// Ba chấm nhấp nháy: nhân vật đang suy nghĩ.
struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = reduceMotion ? 0.5 : max(0, sin(t * 5 - Double(index) * 0.7))
                    Circle().fill(HopeTheme.secondary).frame(width: 7, height: 7)
                        .offset(y: -5 * wave).opacity(0.4 + 0.6 * wave)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Trang trò chuyện với Hope và các con vật. Khóa Gemini có thì nhân vật trả lời bằng AI (sau khi bạn đồng ý một lần),
/// không có thì trả lời bằng lời viết sẵn. Trả lời có thể chậm: hiện "đang suy nghĩ", rồi "đang nhập" từng chữ.
@MainActor
struct CompanionChatView: View {
    @Binding var companionID: String
    let mood: HopeMood?
    /// Nhúng trong khung chat nổi của trang Vườn: không có hàng chọn nhân vật (nhân vật do con vật được chạm quyết định) và không thêm lề.
    var embedded = false
    @AppStorage("hope.chat.consent") private var consent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var phase: Phase = .idle
    @State private var activeTargetID = ""
    @State private var thinkingSince = Date()
    @State private var typed = ""
    @State private var request: Task<HealingNote?, Never>?
    @State private var work: Task<Void, Never>?
    @FocusState private var focused: Bool

    private enum Phase: Equatable { case idle, thinking, typing }

    private var companion: HopeCompanion { CompanionCatalog.companion(id: companionID) }
    private var needsConsent: Bool { GeminiKeyStore.hasKey && !consent }
    private var busy: Bool { phase != .idle }
    private let quick = ["Hôm nay mình hơi mệt", "Kể mình nghe một điều vui", "Cùng mình hít thở nhé"]

    /// Nhãn khi chờ lâu: càng chờ lâu càng nói rõ là vẫn đang nghĩ.
    static func thinkingLabel(name: String, waited: TimeInterval) -> String {
        if waited < 6 { return "\(name) đang suy nghĩ…" }
        if waited < 20 { return "\(name) vẫn đang nghĩ…" }
        return "\(name) đang nghĩ kỹ một chút, bạn đợi nhé…"
    }

    /// Thời gian chờ giữa hai chữ khi nhập: nhanh dần với câu dài (tối đa khoảng 6 giây), ngắt nhịp ở dấu câu.
    static func typingDelay(for character: Character, total: Int) -> Double {
        let perSecond = max(30.0, Double(total) / 6.0)
        var delay = 1.0 / perSecond
        if ".!?…".contains(character) { delay += 0.24 } else if character == "," { delay += 0.11 }
        return delay
    }

    var body: some View {
        VStack(spacing: 10) {
            if !embedded { picker }
            transcript
            if needsConsent { consentCard } else {
                quickReplies
                composer
            }
        }
        .padding(.horizontal, embedded ? 0 : HopeTheme.pageInset)
        .task(id: companionID) { messages = CompanionChatStore.load(companionID) }
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CompanionCatalog.all) { item in
                    let selected = item.id == companionID
                    Button { companionID = item.id; HealingHaptics.soft() } label: {
                        Text(item.name).font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(selected ? HopeTheme.onAccent : HopeTheme.ink)
                            .background(selected ? AnyShapeStyle(HopeTheme.accent) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }
                    .buttonStyle(SoftPressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(.vertical, 2)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty && phase == .idle {
                        bubble(ChatMessage(fromUser: false, text: companion.opener, isAI: false, date: .now))
                    }
                    ForEach(messages) { bubble($0).id($0.id) }
                    if phase == .thinking && activeTargetID == companionID { thinkingRow.id("typing") }
                    if phase == .typing && activeTargetID == companionID { typingRow.id("typing") }
                }.padding(12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onChange(of: messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: phase) { _, _ in scrollToEnd(proxy) }
            .onChange(of: typed) { _, _ in proxy.scrollTo("typing", anchor: .bottom) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if phase != .idle { proxy.scrollTo("typing", anchor: .bottom) }
            else if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.fromUser ? .trailing : .leading, spacing: 2) {
            if !message.fromUser { Text(companion.name).font(.caption).foregroundStyle(HopeTheme.secondary) }
            Text(message.text).font(.body)
                .foregroundStyle(message.fromUser ? HopeTheme.onAccent : HopeTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(message.fromUser ? HopeTheme.accent : HopeTheme.surface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    /// Đang chờ câu trả lời: ba chấm nhấp nháy, nhãn đổi theo thời gian chờ, và nút bỏ qua nếu chờ lâu.
    private var thinkingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(companion.name).font(.caption).foregroundStyle(HopeTheme.secondary)
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let waited = timeline.date.timeIntervalSince(thinkingSince)
                HStack(spacing: 10) {
                    ThinkingDots()
                    Text(Self.thinkingLabel(name: companion.name, waited: waited)).font(.subheadline).foregroundStyle(HopeTheme.secondary)
                    if waited > 12 {
                        Button("Không đợi nữa") { request?.cancel() }.font(.subheadline.weight(.semibold)).tint(HopeTheme.accent)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(companion.name) đang suy nghĩ")
    }

    /// Câu trả lời hiện dần từng chữ, có con trỏ nhấp nháy.
    private var typingRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(companion.name) đang nhập…").font(.caption).foregroundStyle(HopeTheme.secondary)
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let on = Int(timeline.date.timeIntervalSince1970 * 2) % 2 == 0
                (Text(typed) + Text(on ? "▍" : " ").foregroundColor(HopeTheme.accent)).font(.body).foregroundStyle(HopeTheme.ink)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(companion.name) đang nhập câu trả lời")
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tin nhắn bạn gõ ở đây được gửi tới dịch vụ AI của Google (Gemini) để \(companion.name) trả lời. Hope không gửi tên việc hay nhật ký của bạn.")
                .font(.subheadline).foregroundStyle(HopeTheme.ink)
            Button("Đã hiểu, bắt đầu trò chuyện") { consent = true }.buttonStyle(HopePrimaryButtonStyle())
        }
        .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var quickReplies: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quick, id: \.self) { text in
                    Button { send(text) } label: {
                        Text(text).font(.subheadline).padding(.horizontal, 14).frame(minHeight: 40)
                            .foregroundStyle(HopeTheme.ink).background(.ultraThinMaterial, in: Capsule())
                    }.buttonStyle(SoftPressStyle()).disabled(busy)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Nhắn cho \(companion.name)…", text: $draft, axis: .vertical).lineLimit(1...3)
                .textFieldStyle(.plain).focused($focused).submitLabel(.send).onSubmit { send(draft) }
                .padding(.horizontal, 16).frame(minHeight: 46)
                .background(HopeTheme.surface, in: Capsule())
                .accessibilityLabel("Tin nhắn cho \(companion.name)")
            Button { send(draft) } label: {
                Image(systemName: "arrow.up").font(.headline).frame(width: 46, height: 46)
                    .foregroundStyle(HopeTheme.onAccent).background(HopeTheme.accent, in: Circle())
            }
            .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Gửi")
        }
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, !needsConsent else { return }
        let target = companion
        let history = messages
        draft = ""
        messages.append(ChatMessage(fromUser: true, text: String(text.prefix(800)), isAI: false, date: .now))
        CompanionChatStore.save(messages, for: target.id)
        activeTargetID = target.id
        thinkingSince = Date()
        typed = ""
        phase = .thinking
        // Lời gọi mạng nằm trong một Task riêng để nút "Không đợi nữa" huỷ được nó mà không làm dừng hiệu ứng nhập chữ.
        let call = Task { @MainActor () -> HealingNote? in
            guard GeminiKeyStore.hasKey else { return nil }
            return await HealingAI.chat(companion: target, history: history, text: text)
        }
        request = call
        work = Task { @MainActor in
            let started = Date()
            var reply = await call.value
            if reply == nil {
                // Không có Gemini, hết thời gian hoặc bị bỏ qua: nhân vật vẫn "nghĩ" một nhịp cho tự nhiên rồi trả lời bằng lời viết sẵn.
                let wait = max(0, Double.random(in: 0.9...1.7) - Date().timeIntervalSince(started))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                reply = HealingNote(text: CompanionReply.offline(target, to: text), isAI: false)
            }
            guard let reply else { phase = .idle; return }
            try? await Task.sleep(nanoseconds: 320_000_000)
            phase = .typing
            if reduceMotion { typed = reply.text } else {
                let characters = Array(reply.text)
                for character in characters {
                    typed.append(character)
                    try? await Task.sleep(nanoseconds: UInt64(Self.typingDelay(for: character, total: characters.count) * 1_000_000_000))
                }
            }
            finish(reply, for: target)
        }
    }

    private func finish(_ reply: HealingNote, for target: HopeCompanion) {
        if target.id == companionID {
            messages.append(ChatMessage(fromUser: false, text: reply.text, isAI: reply.isAI, date: .now))
            CompanionChatStore.save(messages, for: target.id)
        } else {
            var other = CompanionChatStore.load(target.id)
            other.append(ChatMessage(fromUser: false, text: reply.text, isAI: reply.isAI, date: .now))
            CompanionChatStore.save(other, for: target.id)
        }
        HealingHaptics.soft()
        typed = ""
        phase = .idle
        request = nil
        work = nil
    }
}
