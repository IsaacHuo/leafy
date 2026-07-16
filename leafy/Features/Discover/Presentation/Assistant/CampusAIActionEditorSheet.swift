import SwiftUI

extension CampusAIActionRecord {
    var status: CampusAIActionStatus {
        CampusAIActionStatus(rawValue: statusRawValue) ?? .pending
    }

    var kind: CampusAIActionKind? {
        CampusAIActionKind(rawValue: kindRawValue)
    }

    var payload: CampusAIActionPayload? {
        guard let data = payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CampusAIActionPayload.self, from: data)
    }

    var actionDraft: CampusAIActionDraft? {
        guard let kind, let payload else { return nil }
        return CampusAIActionDraft(
            id: id.uuidString,
            kind: kind,
            title: title,
            detail: detail,
            payload: payload
        )
    }
}

struct CampusAIActionEditorPresentation: Identifiable {
    let id: UUID
    let record: CampusAIActionRecord
    let draft: CampusAIActionDraft

    init(record: CampusAIActionRecord, draft: CampusAIActionDraft) {
        self.id = record.id
        self.record = record
        self.draft = draft
    }
}

struct CampusAIActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: CampusAIActionEditorPresentation
    let onSave: @MainActor (CampusAIActionDraft) async -> Bool

    @State private var scheduleTitle: String
    @State private var scheduleDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var hasDate: Bool
    @State private var hasStartTime: Bool
    @State private var hasEndTime: Bool
    @State private var location: String
    @State private var note: String
    @State private var minutesBefore: Int
    @State private var isSaving = false

    init(
        presentation: CampusAIActionEditorPresentation,
        onSave: @escaping @MainActor (CampusAIActionDraft) async -> Bool
    ) {
        self.presentation = presentation
        self.onSave = onSave
        let payload = presentation.draft.payload
        let initialStart = Self.initialStartDate(for: presentation.draft)
        let initialEnd = Self.initialEndDate(for: presentation.draft)
        let fallback = initialStart ?? Date()
        _scheduleTitle = State(initialValue: payload.title ?? payload.countdownTitle ?? "")
        _scheduleDate = State(initialValue: fallback)
        _startTime = State(initialValue: fallback)
        _endTime = State(initialValue: initialEnd ?? fallback.addingTimeInterval(45 * 60))
        _hasDate = State(initialValue: Self.hasInitialDate(for: presentation.draft))
        _hasStartTime = State(initialValue: Self.hasInitialTime(for: presentation.draft))
        _hasEndTime = State(initialValue: initialEnd != nil)
        _location = State(initialValue: payload.location ?? "")
        _note = State(initialValue: payload.note ?? "")
        _minutesBefore = State(initialValue: max(0, payload.minutesBefore ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                scheduleSection
            }
            .navigationTitle("添加日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private var scheduleSection: some View {
        Group {
            Section("日程信息") {
                TextField("标题", text: $scheduleTitle)
                TextField("地点（可选）", text: $location)
                TextField("备注（可选）", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("日程时间") {
                Toggle("设置日期", isOn: $hasDate)
                if hasDate {
                    DatePicker("日期", selection: $scheduleDate, displayedComponents: .date)
                }

                Toggle("设置开始时间", isOn: $hasStartTime)
                if hasStartTime {
                    DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                }

                Toggle("设置结束时间", isOn: $hasEndTime)
                    .disabled(!hasDate || !hasStartTime)
                if hasEndTime {
                    DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                }
            }

            Section("提醒") {
                Stepper(
                    minutesBefore > 0 ? "提前 \(minutesBefore) 分钟提醒" : "不提前提醒",
                    value: $minutesBefore,
                    in: 0...180,
                    step: 5
                )
            }
        }
    }

    private var canSave: Bool {
        guard scheduleTitle.nonEmptyTrimmed != nil, hasDate, hasStartTime else { return false }
        return !hasEndTime || combinedEndDate > combinedStartDate
    }

    private var editedDraft: CampusAIActionDraft {
        CampusAIActionDraft(
            id: presentation.draft.id,
            kind: .createSchedule,
            title: "添加日程",
            detail: presentation.draft.detail,
            payload: CampusAIActionPayload(
                startsAt: Self.isoFormatter.string(from: combinedStartDate),
                endsAt: hasEndTime ? Self.isoFormatter.string(from: combinedEndDate) : nil,
                title: scheduleTitle,
                location: location,
                note: note,
                minutesBefore: minutesBefore
            )
        )
    }

    private var combinedStartDate: Date {
        Self.combinedDate(date: scheduleDate, time: startTime)
    }

    private var combinedEndDate: Date {
        Self.combinedDate(date: scheduleDate, time: endTime)
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        let succeeded = await onSave(editedDraft)
        isSaving = false
        if succeeded { dismiss() }
    }

    private static func initialStartDate(for draft: CampusAIActionDraft) -> Date? {
        switch draft.kind {
        case .createSchedule:
            return CampusAIActionValidation.scheduleStartDate(for: draft)
        case .createCountdown:
            return CampusAIActionValidation.countdownDate(for: draft)
        case .createTimetableReminder:
            guard let week = draft.payload.week,
                  let day = draft.payload.dayOfWeek,
                  let period = draft.payload.period else { return nil }
            return TimetablePeriodSchedule.startDate(week: week, dayOfWeek: day, period: period)
        case .openAcademicRoute:
            return nil
        }
    }

    private static func initialEndDate(for draft: CampusAIActionDraft) -> Date? {
        switch draft.kind {
        case .createSchedule:
            return CampusAIActionValidation.scheduleEndDate(for: draft)
        case .createTimetableReminder:
            guard let week = draft.payload.week,
                  let day = draft.payload.dayOfWeek,
                  let period = draft.payload.endPeriod ?? draft.payload.period else { return nil }
            return TimetablePeriodSchedule.endDate(week: week, dayOfWeek: day, period: period)
        case .createCountdown, .openAcademicRoute:
            return nil
        }
    }

    private static func hasInitialDate(for draft: CampusAIActionDraft) -> Bool {
        initialStartDate(for: draft) != nil
    }

    private static func hasInitialTime(for draft: CampusAIActionDraft) -> Bool {
        switch draft.kind {
        case .createCountdown:
            return false
        default:
            return initialStartDate(for: draft) != nil
        }
    }

    private static func combinedDate(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateParts = calendar.dateComponents([.year, .month, .day], from: date)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: DateComponents(
            year: dateParts.year,
            month: dateParts.month,
            day: dateParts.day,
            hour: timeParts.hour,
            minute: timeParts.minute
        )) ?? date
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
