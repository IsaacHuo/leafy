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
    let onSave: (CampusAIActionDraft) -> Void

    @State private var countdownTitle: String
    @State private var targetDate: Date
    @State private var week: Int
    @State private var dayOfWeek: Int
    @State private var period: Int
    @State private var endPeriod: Int
    @State private var reminderTitle: String
    @State private var location: String
    @State private var note: String
    @State private var minutesBefore: Int

    init(
        presentation: CampusAIActionEditorPresentation,
        onSave: @escaping (CampusAIActionDraft) -> Void
    ) {
        self.presentation = presentation
        self.onSave = onSave
        let payload = presentation.draft.payload
        _countdownTitle = State(initialValue: payload.countdownTitle ?? payload.title ?? "")
        _targetDate = State(initialValue: CampusAIActionValidation.countdownDate(for: presentation.draft) ?? Date())
        _week = State(initialValue: max(1, min(payload.week ?? SemesterConfig.currentWeek(), SemesterConfig.supportedWeeks)))
        _dayOfWeek = State(initialValue: max(1, min(payload.dayOfWeek ?? 1, 7)))
        let initialPeriod = payload.period ?? TimetablePeriodSchedule.slots.first?.period ?? 1
        _period = State(initialValue: max(1, min(initialPeriod, TimetablePeriodSchedule.slots.last?.period ?? 12)))
        _endPeriod = State(initialValue: max(initialPeriod, min(payload.endPeriod ?? initialPeriod, TimetablePeriodSchedule.slots.last?.period ?? 12)))
        _reminderTitle = State(initialValue: payload.title ?? payload.countdownTitle ?? "")
        _location = State(initialValue: payload.location ?? "")
        _note = State(initialValue: payload.note ?? "")
        _minutesBefore = State(initialValue: max(0, payload.minutesBefore ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch presentation.draft.kind {
                case .createCountdown:
                    countdownSection
                case .createTimetableReminder:
                    timetableReminderSection
                default:
                    Text("这个动作不需要编辑。")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(editedDraft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: period) { _, newValue in
                if endPeriod < newValue {
                    endPeriod = newValue
                }
            }
        }
    }

    private var countdownSection: some View {
        Section("重要日期") {
            TextField("标题", text: $countdownTitle)
            DatePicker("目标日期", selection: $targetDate, displayedComponents: .date)
        }
    }

    private var timetableReminderSection: some View {
        Section("课表提醒") {
            TextField("标题", text: $reminderTitle)
            Stepper("第 \(week) 周", value: $week, in: 1...SemesterConfig.supportedWeeks)
            Picker("星期", selection: $dayOfWeek) {
                ForEach(1...7, id: \.self) { day in
                    Text(Self.weekdayText(day)).tag(day)
                }
            }
            Stepper("开始节次：\(period)", value: $period, in: periodRange)
            Stepper("结束节次：\(endPeriod)", value: $endPeriod, in: period...periodRange.upperBound)
            TextField("地点", text: $location)
            TextField("备注", text: $note, axis: .vertical)
                .lineLimit(2...4)
            Stepper(minutesBefore > 0 ? "提前 \(minutesBefore) 分钟提醒" : "不提前提醒", value: $minutesBefore, in: 0...180, step: 5)
        }
    }

    private var navigationTitle: String {
        switch presentation.draft.kind {
        case .createCountdown:
            return "编辑重要日期"
        case .createTimetableReminder:
            return "编辑课表提醒"
        default:
            return "编辑动作"
        }
    }

    private var canSave: Bool {
        switch presentation.draft.kind {
        case .createCountdown:
            return countdownTitle.nonEmptyTrimmed != nil
        case .createTimetableReminder:
            return reminderTitle.nonEmptyTrimmed != nil
        default:
            return false
        }
    }

    private var editedDraft: CampusAIActionDraft {
        switch presentation.draft.kind {
        case .createCountdown:
            let target = DateFormatters.queryDate.string(from: targetDate)
            return CampusAIActionDraft(
                id: presentation.draft.id,
                kind: .createCountdown,
                title: presentation.draft.title,
                detail: presentation.draft.detail,
                payload: CampusAIActionPayload(
                    countdownTitle: countdownTitle,
                    targetDate: target
                )
            )
        case .createTimetableReminder:
            return CampusAIActionDraft(
                id: presentation.draft.id,
                kind: .createTimetableReminder,
                title: presentation.draft.title,
                detail: presentation.draft.detail,
                payload: CampusAIActionPayload(
                    week: week,
                    dayOfWeek: dayOfWeek,
                    period: period,
                    endPeriod: endPeriod,
                    title: reminderTitle,
                    location: location,
                    note: note,
                    minutesBefore: minutesBefore
                )
            )
        default:
            return presentation.draft
        }
    }

    private var periodRange: ClosedRange<Int> {
        let periods = TimetablePeriodSchedule.slots.map(\.period)
        return (periods.min() ?? 1)...(periods.max() ?? 12)
    }

    private static func weekdayText(_ day: Int) -> String {
        ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][max(1, min(day, 7)) - 1]
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
