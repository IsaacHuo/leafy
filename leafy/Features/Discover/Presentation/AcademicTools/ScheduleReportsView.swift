import SwiftData
import SwiftUI

struct ScheduleReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage

    @State private var settings = ScheduleReportSettingsStore.load()
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isSaving = false

    private var enabledModeCount: Int {
        settings.enabledModes.count
    }

    var body: some View {
        AcademicDetailScrollContainer {
            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Label("推送", systemImage: "bell.badge")
                        .leafyHeadline()
                    Text("按你选择的时间发送本机报告。首版只使用本地通知，不上传课表、考试或本地日程。")
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Toggle("开启报告中心", isOn: $settings.isEnabled)
                        .font(.headline)

                    Text(settings.isEnabled ? "已开启 \(enabledModeCount) 个模式" : "关闭后会取消已排程的报告通知。")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            AcademicDetailSectionHeader(title: "报告模式")
            ForEach(ScheduleReportMode.allCases) { mode in
                ScheduleReportModeCard(
                    mode: mode,
                    setting: binding(for: mode),
                    time: dateBinding(for: mode),
                    isParentEnabled: settings.isEnabled
                )
            }

            AcademicDetailCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Button {
                        Task { await saveSettings() }
                    } label: {
                        Label(isSaving ? "保存中" : "保存推送设置", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || (settings.isEnabled && enabledModeCount == 0))

                    Text("通知正文会根据保存时的课表、考试、重要日期、校历节点和本地日程生成；打开 App、刷新数据或再次保存会重新排程。")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            AcademicDetailFooterText(text: "天气服务将切换到 WeatherKit，但首版报告通知暂不展示天气。")
        }
        .navigationTitle("推送")
        .leafyInlineNavigationTitle()
        .onAppear {
            settings = ScheduleReportSettingsStore.load()
        }
        .leafyOperationAlert($operationAlert)
    }

    private func binding(for mode: ScheduleReportMode) -> Binding<ScheduleReportModeSetting> {
        Binding {
            settings.setting(for: mode)
        } set: { newValue in
            settings.set(newValue, for: mode)
        }
    }

    private func dateBinding(for mode: ScheduleReportMode) -> Binding<Date> {
        Binding {
            let setting = settings.setting(for: mode)
            var components = DateComponents()
            components.hour = setting.hour
            components.minute = setting.minute
            return Calendar.current.date(from: components) ?? Date()
        } set: { newValue in
            var setting = settings.setting(for: mode)
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            setting.hour = components.hour ?? mode.defaultHour
            setting.minute = components.minute ?? mode.defaultMinute
            settings.set(setting, for: mode)
        }
    }

    @MainActor
    private func saveSettings() async {
        isSaving = true
        ScheduleReportSettingsStore.save(settings)

        do {
            let input = ScheduleReportDataSource.input(modelContext: modelContext)
            let updatedSettings = try await ScheduleReportNotificationManager.updateNotifications(
                settings: settings,
                input: input
            )
            settings = updatedSettings
            ScheduleReportSettingsStore.save(updatedSettings)
            operationAlert = .success(
                settings.isEnabled
                    ? L10n.text("推送设置已保存，已排程 %d 条报告通知。", language: leafyLanguage, updatedSettings.scheduledNotificationIDs.count)
                    : L10n.text("报告中心已关闭。", language: leafyLanguage)
            )
        } catch {
            var disabledSettings = settings
            disabledSettings.isEnabled = false
            disabledSettings.scheduledNotificationIDs = []
            settings = disabledSettings
            ScheduleReportSettingsStore.save(disabledSettings)
            operationAlert = .failure(error.localizedDescription)
        }

        isSaving = false
    }
}

private struct ScheduleReportModeCard: View {
    let mode: ScheduleReportMode
    @Binding var setting: ScheduleReportModeSetting
    @Binding var time: Date
    let isParentEnabled: Bool

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Toggle(isOn: $setting.isEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: mode.systemImage)
                            .frame(width: 28, alignment: .leading)
                        Text(mode.title)
                    }
                    .font(.headline)
                }
                .disabled(!isParentEnabled)

                Text(mode.subtitle)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)

                if setting.isEnabled && isParentEnabled {
                    DatePicker("推送时间", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
        }
    }
}
