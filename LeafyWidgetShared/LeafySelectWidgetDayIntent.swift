import AppIntents
import WidgetKit

struct LeafySelectWidgetDayIntent: AppIntent {
    static var title: LocalizedStringResource = "切换课表日期"
    static var description = IntentDescription("切换 MyLeafy 小组件显示今天或明天的课表。")
    static var isDiscoverable = false

    @Parameter(title: "日期偏移")
    var dayOffset: Int

    init() {
        dayOffset = 0
    }

    init(dayOffset: Int) {
        self.dayOffset = LeafyWidgetSnapshotStore.normalizedDayOffset(dayOffset)
    }

    func perform() async throws -> some IntentResult {
        LeafyWidgetSnapshotStore.setSelectedDayOffset(dayOffset)
        WidgetCenter.shared.reloadTimelines(ofKind: LeafyWidgetConstants.widgetKind)
        return .result()
    }
}
