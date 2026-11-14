import Foundation
import SwiftData
import SwiftUI
import ActivityKit
import UIKit
import Observation

@MainActor
@Observable
public final class ShiftDashboardViewModel {
    public var isAnalyzingAI = false
    public var alertMessage: String?
    public var showAlert = false
    public var importToReview: PendingTaskImport?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var needsActivity = false

    public init() {}

    public func report(_ error: Error) {
        alertMessage = error.localizedDescription
        showAlert = true
    }

    public func activateShift(_ shift: ShiftConfig, context: ModelContext) {
        guard shift.endTime > Date(), shift.startTime < shift.endTime,
              Calendar.current.isDateInToday(shift.targetDate) || (shift.startTime <= Date() && Date() < shift.endTime),
              !shift.name.lowercased().contains("nghỉ") else {
            alertMessage = "Chỉ bắt đầu ca của hôm nay hoặc ca qua đêm đang diễn ra. Hãy kiểm tra lại ngày và giờ làm."
            showAlert = true
            return
        }
        do {
            try RoutineChecklistService.seedIfNeeded(context: context)
            let shifts = try context.fetch(FetchDescriptor<ShiftConfig>(predicate: #Predicate { $0.isActive }))
            for item in shifts { item.isActive = item.id == shift.id }
            shift.isActive = true
            _ = try RoutineChecklistService.apply(to: shift, context: context)
            // Tasks captured before choosing a shift remain accessible in the first active shift.
            for task in try ShiftTaskSync.tasks(in: context, shiftID: nil) { task.shiftId = shift.id; task.updatedAt = .now }
            try context.save()
            refresh(context: context, startActivity: true)
        } catch {
            context.rollback()
            report(error)
        }
    }

    public func endShift(currentShift: ShiftConfig?, context: ModelContext) {
        do {
            currentShift?.isActive = false
            currentShift?.updatedAt = .now
            try context.save()
            refresh(context: context)
        } catch {
            context.rollback()
            report(error)
        }
    }

    public func addTask(title: String, context: ModelContext) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        do {
            let shift = try ShiftTaskSync.activeShift(in: context)
            context.insert(TaskItem(title: title, priority: .medium, shiftId: shift?.id))
            try context.save()
            refresh(context: context)
            return true
        } catch {
            context.rollback()
            report(error)
            return false
        }
    }

    public func processClipboard(context: ModelContext) {
        guard !isAnalyzingAI else { return }
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Hãy sao chép tin nhắn Zalo trước khi bóc tách."
            showAlert = true
            return
        }
        // Capture the intended shift before the network request can suspend.
        let shiftID: String?
        do { shiftID = try ShiftTaskSync.activeShift(in: context)?.id }
        catch { report(error); return }
        isAnalyzingAI = true
        Task {
            defer { isAnalyzingAI = false }
            do {
                let tasks = try await ZaloTaskExtractorService.shared.extractTasks(from: text)
                importToReview = try TaskImportService.stage(tasks: tasks, source: text, label: "Clipboard Zalo", shiftID: shiftID, context: context)
            } catch {
                context.rollback()
                report(error)
            }
        }
    }

    public func toggleTask(_ task: TaskItem, context: ModelContext) {
        do {
            try TaskCommands.complete(task, completed: !task.isCompleted, context: context)
            refresh(context: context)
        } catch {
            context.rollback()
            report(error)
        }
    }

    public func refresh(context: ModelContext, startActivity: Bool = false) {
        needsRefresh = true
        needsActivity = needsActivity || startActivity
        guard refreshTask == nil else { return }
        refreshTask = Task {
          // Coalesce rapid edits without dropping the final state or starting duplicate activities.
          while needsRefresh {
            needsRefresh = false
            let startActivity = needsActivity
            needsActivity = false
            do {
                try await ShiftTaskSync.refresh(using: context)
                guard startActivity, let shift = try ShiftTaskSync.activeShift(in: context),
                      shift.endTime > Date(), ActivityAuthorizationInfo().areActivitiesEnabled,
                      !Activity<ShiftActivityAttributes>.activities.contains(where: { $0.attributes.shiftId == shift.id }) else { continue }
                let tasks = try ShiftTaskSync.tasks(in: context, shiftID: shift.id)
                _ = try Activity.request(attributes: ShiftActivityAttributes(shiftId: shift.id, shiftEndTime: shift.endTime),
                                         content: ActivityContent(state: ShiftTaskSync.state(shift: shift, tasks: tasks), staleDate: shift.endTime),
                                         pushType: nil)
            } catch {
                // Persistence already succeeded. Do not claim that the task failed to save.
                alertMessage = "Dữ liệu đã lưu, nhưng chưa đồng bộ màn hình khóa: \(error.localizedDescription)"
                showAlert = true
            }
          }
          refreshTask = nil
        }
    }
}
