import SwiftUI
import SwiftData
import AVFoundation
import UIKit

/// Phát chuông có giai điệu khi app đang mở. Tôn trọng công tắc im lặng (dùng phiên âm thanh ambient) và tuỳ chọn trong hộp thông báo.
@MainActor
final class BellPlayer {
    static let shared = BellPlayer()
    private var player: AVAudioPlayer?

    func play(_ kind: BellMelody.Kind, force: Bool = false) {
        guard force || HopeAlertState.soundEnabled else { return }
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) { BellMelody.wavData(for: kind) }.value
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(data: data)
            player?.prepareToPlay()
            player?.play()
        }
    }
}

/// Nút chuông có huy hiệu số thông báo chưa đọc (hoặc số việc quá hạn). Chạm để mở hộp thông báo.
@MainActor
struct HopeBellButton: View {
    var glass = false
    @Query private var tasks: [TaskItem]
    @Query private var shifts: [ShiftConfig]
    @Query private var visits: [HealingVisit]
    @State private var showing = false
    @State private var readKeys = HopeAlertState.readKeys()
    @State private var ringing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(glass: Bool = false) {
        self.glass = glass
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let back = calendar.date(byAdding: .day, value: -2, to: day) ?? day
        _tasks = Query(filter: #Predicate<TaskItem> { !$0.isCompleted && $0.deletedAt == nil })
        _shifts = Query(filter: #Predicate<ShiftConfig> { $0.targetDate >= back })
        _visits = Query(filter: #Predicate<HealingVisit> { $0.createdAt >= day })
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let alerts = HopeAlertEngine.make(tasks: tasks, shifts: shifts, visits: visits, now: timeline.date)
            let unread = alerts.filter { !readKeys.contains($0.id) }
            let urgent = alerts.contains { $0.kind == .taskLate || $0.kind == .shiftEnd }
            Button { showing = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: unread.isEmpty ? "bell" : "bell.fill")
                        .font(.body.weight(.medium)).foregroundStyle(HopeTheme.ink)
                        .rotationEffect(.degrees(ringing ? 14 : 0), anchor: .top)
                        .frame(width: glass ? 40 : 44, height: glass ? 40 : 44)
                        .background { if glass { Circle().fill(.ultraThinMaterial) } }
                    if !unread.isEmpty {
                        Text(unread.count > 9 ? "9+" : "\(unread.count)")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                            .background(urgent ? HopeTheme.urgent : HopeTheme.accent, in: Capsule())
                            .offset(x: 2, y: glass ? 0 : 4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thông báo")
            .accessibilityValue(unread.isEmpty ? "Không có thông báo mới" : "\(unread.count) chưa đọc")
            .onChange(of: alerts.map(\.id)) { _, keys in announceNew(alerts, keys: keys) }
            .onAppear { announceNew(alerts, keys: alerts.map(\.id)) }
            .sheet(isPresented: $showing, onDismiss: { readKeys = HopeAlertState.readKeys() }) {
                HopeAlertsView(alerts: alerts)
            }
        }
    }

    /// Có thông báo mới: lắc chuông và rung nhẹ. Chuông trong app chỉ phát cho loại không có thông báo hệ thống
    /// (thông báo hệ thống đã tự phát chuông có giai điệu kể cả khi app đang mở).
    private func announceNew(_ alerts: [HopeAlert], keys: [String]) {
        let fresh = Set(HopeAlertState.newlySeen(keys))
        guard !fresh.isEmpty else { return }
        let added = alerts.filter { fresh.contains($0.id) }
        HealingHaptics.soft()
        if let first = added.first(where: { !$0.kind.hasScheduledNotification }) { BellPlayer.shared.play(first.kind.melody) }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.12).repeatCount(8, autoreverses: true)) { ringing = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation { ringing = false }
        }
    }
}

/// Hộp thông báo: việc cần chú ý ngay, xử lý nhanh (xong, hoãn), và tuỳ chọn chuông.
@MainActor
struct HopeAlertsView: View {
    let alerts: [HopeAlert]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(HopeAlertState.soundKey) private var sound = true
    @AppStorage(HopeAlertState.closeDayKey) private var closeDayReminder = false
    @State private var handled: Set<String> = []
    @State private var errorMessage: String?

    private var visible: [HopeAlert] { alerts.filter { !handled.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if visible.isEmpty {
                        Text("Không có gì cần chú ý lúc này. Chuông sẽ báo khi việc đến hạn, quá hạn, sắp đến hoặc hết ca, và vài lời nhắc nhẹ trong ngày.")
                            .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                    }
                    ForEach(visible) { alert in row(alert) }
                } header: { Text("Đang cần chú ý") }
                .listRowBackground(HopeTheme.surface)

                Section {
                    Toggle("Chuông khi có thông báo mới", isOn: $sound)
                    Button { BellPlayer.shared.play(.due, force: true) } label: { Label("Thử chuông", systemImage: "bell.and.waves.left.and.right") }
                    Toggle("Nhắc khép lại hôm nay lúc 21:00", isOn: $closeDayReminder)
                        .onChange(of: closeDayReminder) { _, on in
                            Task {
                                if on { _ = await NotificationScheduler.shared.requestAuthorization() }
                                await NotificationScheduler.shared.setDailyCloseDay(enabled: on)
                            }
                        }
                } header: { Text("Chuông") } footer: {
                    Text("Chuông có giai điệu, dài khoảng 5 đến 7 giây: nhẹ khi sắp đến hạn, vui khi đến hạn, dồn dập khi quá hạn hoặc sắp hết ca. Thông báo hệ thống cần được cho phép trong Cài đặt iPhone.")
                }
                .listRowBackground(HopeTheme.surface)
            }
            .scrollContentBackground(.hidden).background(HopeTheme.background)
            .navigationTitle("Thông báo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đọc hết") { HopeAlertState.markRead(alerts.map(\.id)); dismiss() }
                        .disabled(alerts.isEmpty).fontWeight(.semibold)
                }
            }
            .alert("Hope", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .tint(HopeTheme.accent)
            .onAppear { HopeAlertState.markRead(alerts.map(\.id)) }
        }
        .presentationDragIndicator(.visible)
    }

    private func row(_ alert: HopeAlert) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alert.kind.symbol).font(.title3)
                    .foregroundStyle(alert.kind == .taskLate || alert.kind == .shiftEnd ? HopeTheme.urgent : HopeTheme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title).font(.headline).foregroundStyle(HopeTheme.ink)
                    Text(alert.body).font(.subheadline).foregroundStyle(HopeTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let taskID = alert.taskID {
                HStack(spacing: 8) {
                    Button("Xong") { act(alert, taskID: taskID, minutes: nil) }.buttonStyle(.borderedProminent)
                    Button("Hoãn 10 phút") { act(alert, taskID: taskID, minutes: 10) }.buttonStyle(.bordered)
                    Button("15 phút") { act(alert, taskID: taskID, minutes: 15) }.buttonStyle(.bordered)
                }.controlSize(.small)
            } else {
                Button("Đã hiểu") { handled.insert(alert.id); HopeAlertState.markRead([alert.id]) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    /// Xong hoặc hoãn một việc ngay trong hộp thông báo, rồi đồng bộ thông báo, màn hình khoá và widget.
    private func act(_ alert: HopeAlert, taskID: String, minutes: Int?) {
        do {
            var query = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == taskID && $0.deletedAt == nil })
            query.fetchLimit = 1
            guard let task = try context.fetch(query).first else { return }
            if let minutes {
                let shift: ShiftConfig?
                if let shiftID = task.shiftId {
                    shift = try context.fetch(FetchDescriptor<ShiftConfig>(predicate: #Predicate { $0.id == shiftID })).first
                } else {
                    shift = nil
                }
                try TaskCommands.snooze(task, minutes: minutes, shift: shift, context: context)
            } else {
                try TaskCommands.complete(task, completed: true, context: context)
            }
            handled.insert(alert.id)
            HealingHaptics.settle()
            Task { try? await ShiftTaskSync.refresh(using: context) }
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
