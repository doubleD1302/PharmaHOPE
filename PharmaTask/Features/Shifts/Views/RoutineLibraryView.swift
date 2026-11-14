import SwiftUI
import SwiftData

@MainActor
struct RoutineLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\RoutineTemplate.position), SortDescriptor(\RoutineTemplate.title)]) private var templates: [RoutineTemplate]
    @State private var type: RoutineType = .morning
    @State private var editor = false
    @State private var editing: RoutineTemplate?
    @State private var title = ""
    @State private var notes = ""
    @State private var priority = TaskPriority.medium
    @State private var clock = ""
    @State private var enabled = true
    @State private var error: String?
    @State private var editorError: String?
    private var filtered: [RoutineTemplate] { templates.filter { $0.typeRaw == type.rawValue } }
    var body: some View {
        List {
            Section {
                Picker("Loại ca", selection: $type) { ForEach(RoutineType.allCases) { Text($0.title).tag($0) } }
            } footer: { Text("Mẫu áp dụng khi bắt đầu một ca mới. Sửa mẫu không đổi công việc của những ca đã tạo.") }
            ForEach(filtered) { item in
                Button { open(item) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).foregroundStyle(HopeTheme.ink)
                            Text(item.isEnabled ? (item.dueTime ?? "Không có giờ cố định") : "Đã tắt")
                                .font(.caption).foregroundStyle(HopeTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(HopeTheme.accent)
                    }
                }
            }
            .onDelete { indices in
                let deleting = indices.map { filtered[$0] }
                for item in deleting { context.delete(item) }
                do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
            }
            .onMove { source, destination in
                var items = filtered
                items.move(fromOffsets: source, toOffset: destination)
                for (index, item) in items.enumerated() { item.position = index; item.updatedAt = .now }
                do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
            }
            if filtered.isEmpty { Text("Chưa có mẫu cho loại ca này.").foregroundStyle(HopeTheme.secondary) }
        }
        .scrollContentBackground(.hidden).background(HopeTheme.background)
        .navigationTitle("Checklist theo ca")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { open(nil) } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm mẫu công việc") }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(isPresented: $editor) { templateEditor }
        .alert("Hope", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Đóng", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .task {
            do { try RoutineChecklistService.seedIfNeeded(context: context) }
            catch { self.error = error.localizedDescription }
        }
    }
    private var templateEditor: some View {
        NavigationStack {
            Form {
                Section("Mẫu công việc · \(type.title)") {
                    TextField("Tên việc", text: $title, axis: .vertical).lineLimit(1...4)
                    TextField("Ghi chú", text: $notes, axis: .vertical).lineLimit(2...6)
                    Picker("Ưu tiên", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Giờ HH:mm (không bắt buộc)", text: $clock).keyboardType(.numbersAndPunctuation)
                    Toggle("Dùng cho ca mới", isOn: $enabled)
                }
                if let error = editorError { Section { Text(error).foregroundStyle(HopeTheme.urgent) } }
            }
            .navigationTitle(editing == nil ? "Thêm mẫu" : "Sửa mẫu").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { editor = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.tint(HopeTheme.accent)
        }
    }
    private func open(_ item: RoutineTemplate?) {
        editing = item; title = item?.title ?? ""; notes = item?.notes ?? ""
        priority = TaskPriority(rawValue: item?.priorityRaw ?? "") ?? .medium
        clock = item?.dueTime ?? ""; enabled = item?.isEnabled ?? true; editorError = nil; editor = true
    }
    private func save() {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clock = clock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500, notes.count <= 20_000, clock.isEmpty || TaskText.validTime(clock) else {
            editorError = "Kiểm tra tên việc, ghi chú và giờ theo định dạng HH:mm."
            return
        }
        let item = editing ?? RoutineTemplate(title: title, type: type, position: filtered.count)
        if editing == nil { context.insert(item) }
        item.title = title; item.notes = notes; item.priorityRaw = priority.rawValue
        item.dueTime = clock.isEmpty ? nil : clock; item.isEnabled = enabled; item.updatedAt = .now
        do { try context.save(); editor = false }
        catch { context.rollback(); editorError = error.localizedDescription }
    }
}
