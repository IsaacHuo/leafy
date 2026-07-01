import SwiftUI

extension Color {
    /// 基于课程信息稳定选择当前主题色阶，用于统一课表课程卡片颜色。
    static func fromHash(name: String) -> Color {
        AppTheme.courseCardColor(for: name)
    }
}
