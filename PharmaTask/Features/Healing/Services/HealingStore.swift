import Foundation
import SwiftData

/// Ghi dữ liệu Vườn. Mọi hàm kiểm tra trước, lưu một lần và rollback khi lỗi.
@MainActor
public enum HealingStore {
    public static let maximumJournalLength = 10_000

    public static func recordVisit(_ kind: HealingVisitKind, minutes: Int = 0, context: ModelContext, at date: Date = .now) throws {
        context.insert(HealingVisit(kind: kind, minutes: max(0, minutes), createdAt: date))
        do { try context.save() } catch { context.rollback(); throw error }
    }

    @discardableResult
    public static func recordMood(_ mood: HopeMood, context: ModelContext, at date: Date = .now) throws -> MoodCheckIn {
        let checkIn = MoodCheckIn(mood: mood, createdAt: date)
        context.insert(checkIn)
        context.insert(HealingVisit(kind: .checkIn, createdAt: date))
        do { try context.save() } catch { context.rollback(); throw error }
        return checkIn
    }

    @discardableResult
    public static func saveJournal(kind: JournalKind, prompt: String, text: String, context: ModelContext, at date: Date = .now) throws -> JournalEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HopeDataError.invalid("Hãy viết ít nhất một dòng.") }
        guard trimmed.count <= maximumJournalLength else { throw HopeDataError.invalid("Bài viết dài quá giới hạn 10.000 ký tự.") }
        let entry = JournalEntry(kind: kind, prompt: prompt, text: trimmed, createdAt: date)
        context.insert(entry)
        context.insert(HealingVisit(kind: kind == .closeDay ? .closeDay : .journal, createdAt: date))
        do { try context.save() } catch { context.rollback(); throw error }
        return entry
    }

    public static func update(_ entry: JournalEntry, text: String, context: ModelContext) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HopeDataError.invalid("Bài viết không được để trống.") }
        guard trimmed.count <= maximumJournalLength else { throw HopeDataError.invalid("Bài viết dài quá giới hạn 10.000 ký tự.") }
        entry.text = trimmed; entry.updatedAt = .now
        do { try context.save() } catch { context.rollback(); throw error }
    }

    public static func delete(_ entry: JournalEntry, context: ModelContext) throws {
        context.delete(entry)
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Việc đã hoàn thành trong ngày, mới nhất trước. Không gồm việc đã xóa.
    public static func completedToday(_ tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> [TaskItem] {
        tasks.filter { task in
            guard task.isCompleted, task.deletedAt == nil, let done = task.completedAt else { return false }
            return calendar.isDate(done, inSameDayAs: now)
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}
