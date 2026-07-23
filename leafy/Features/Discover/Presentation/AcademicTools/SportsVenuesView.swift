import Combine
import QuickLook
import Supabase
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SportsVenuesView: View {
    var body: some View {
        AcademicDetailScrollContainer {
            SportsVenueNoticeCard()

            ForEach(SportsVenueData.groups) { group in
                SportsVenueGroupSection(group: group)
            }

            AcademicDetailFooterText(text: "场馆信息根据当前整理版本展示，不包含实时占用状态。")
        }
        .navigationTitle("场馆开放")
        .leafyInlineNavigationTitle()
    }
}

private struct SportsVenueNoticeCard: View {
    var body: some View {
        AcademicDetailCard {
            HStack(alignment: .top, spacing: AppSpacing.compact) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .frame(width: 24, height: 24)

                Text("开放时间可能因教学任务、节假日或场馆安排调整，以现场/预约页面通知为准。")
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SportsVenueGroupSection: View {
    let group: SportsVenueGroup
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var expandedVenueID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: group.title)

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ForEach(group.venues) { venue in
                    let isExpanded = expandedVenueID == venue.id
                    Button {
                        let update = {
                            expandedVenueID = isExpanded ? nil : venue.id
                        }
                        if accessibilityReduceMotion {
                            update()
                        } else {
                            withAnimation(.snappy(duration: 0.32)) {
                                update()
                            }
                        }
                    } label: {
                        SportsVenueTile(venue: venue, isExpanded: isExpanded)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded ? "已展开" : "已收起")
                    .accessibilityHint(isExpanded ? "轻点收起详细信息" : "轻点展开详细信息")
                }
            }
        }
    }
}

private struct SportsVenueTile: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let venue: SportsVenue
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .top, spacing: 8) {
                Text(venue.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                    .frame(width: 16)

                Text(venue.location)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !venue.tags.isEmpty {
                SportsVenueTagRow(tags: isExpanded ? venue.tags : Array(venue.tags.prefix(2)))
            }

            if isExpanded {
                expandedDetails
                    .transition(.opacity)
            }
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppTheme.separator.opacity(0.35), lineWidth: 1)
        }
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailDivider()

            ForEach(Array(venue.details.enumerated()), id: \.offset) { _, detail in
                SportsVenueDetailLine(title: detail.title, value: detail.value)
            }

            if !venue.fees.isEmpty {
                AcademicDetailDivider()

                Text("收费标准")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                ForEach(Array(venue.fees.enumerated()), id: \.offset) { index, fee in
                    if index > 0 {
                        AcademicDetailDivider()
                    }
                    SportsVenueFeeRow(fee: fee)
                }
            }

            if !venue.notes.isEmpty {
                AcademicDetailDivider()

                Text("备注")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                ForEach(venue.notes, id: \.self) { note in
                    SportsVenueNoteLine(text: note)
                }
            }
        }
    }
}

private struct SportsVenueTagRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(AppTheme.softFill, in: Capsule())
            }
        }
    }
}

private struct SportsVenueDetailLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SportsVenueFeeRow: View {
    let fee: SportsVenueFee

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fee.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            ForEach(Array(fee.lines.enumerated()), id: \.offset) { _, line in
                SportsVenueDetailLine(title: line.title, value: line.value)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SportsVenueNoteLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(AppTheme.secondaryText.opacity(0.45))
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum SportsVenueData {
    static let groups: [SportsVenueGroup] = [
        SportsVenueGroup(
            id: "west",
            title: "西区与田家炳",
            venues: [
                SportsVenue(
                    id: "west-fields",
                    title: "西区操场及周边",
                    location: "西区操场及周边",
                    tags: ["全天开放", "上课封闭"],
                    details: [
                        SportsVenueDetail(title: "场地", value: "操场、篮球场、网球场、排球场"),
                        SportsVenueDetail(title: "开放时间", value: "全天开放"),
                        SportsVenueDetail(title: "限制", value: "上课时间段封闭")
                    ]
                ),
                SportsVenue(
                    id: "west-trackside-equipment",
                    title: "场边器械",
                    location: "西区操场周边",
                    tags: ["户外器械", "操场周边", "分散设置"],
                    details: [
                        SportsVenueDetail(title: "器械", value: "单杠、扩胸器等户外健身器械"),
                        SportsVenueDetail(title: "分布", value: "沿操场周边分散设置")
                    ]
                ),
                SportsVenue(
                    id: "stadium-table-tennis",
                    title: "看台乒乓球场",
                    location: "田径场看台地下",
                    tags: ["无需预约", "即到即用"],
                    details: [
                        SportsVenueDetail(title: "周一至周五", value: "17:30-22:00"),
                        SportsVenueDetail(title: "周六、周日", value: "15:30-22:00"),
                        SportsVenueDetail(title: "预约", value: "无需预约，即到即用")
                    ]
                ),
                SportsVenue(
                    id: "tianjiabing-badminton",
                    title: "田家炳体育馆羽毛球场",
                    location: "田家炳体育馆内",
                    tags: ["需预约", "免费时段", "收费时段"],
                    details: [
                        SportsVenueDetail(title: "场地", value: "馆内设有羽毛球场地"),
                        SportsVenueDetail(title: "开放方式", value: "有免费时段和收费时段可供选择"),
                        SportsVenueDetail(title: "预约方式", value: "企业微信 -> 事务e办 -> 办事大厅 -> 羽毛球场地预约")
                    ],
                    notes: ["需提前通过企业微信预约。"]
                )
            ]
        ),
        SportsVenueGroup(
            id: "east",
            title: "东区",
            venues: [
                SportsVenue(
                    id: "haohai-gym",
                    title: "昊海健身房",
                    location: "东区下沉广场",
                    tags: ["收费健身房", "更衣室", "淋浴"],
                    details: [
                        SportsVenueDetail(title: "日常开放", value: "8:30-22:00"),
                        SportsVenueDetail(title: "节假日", value: "营业时间可能调整")
                    ],
                    notes: [
                        "健身设备较齐全，配备更衣室和淋浴间，有免费操课。",
                        "高峰时段人较多；馆内没有游泳池。"
                    ]
                ),
                SportsVenue(
                    id: "east-fourth-floor",
                    title: "东四多功能大厅",
                    location: "东区食堂四层",
                    tags: ["需预约", "羽毛球", "乒乓球"],
                    details: [
                        SportsVenueDetail(title: "场地", value: "6块羽毛球场地、12块乒乓球场地"),
                        SportsVenueDetail(title: "场馆开放", value: "周一至周五 8:00-22:00；周六、周日 9:00-22:00"),
                        SportsVenueDetail(title: "免费时段", value: "周一至周五 8:00-11:00、14:00-17:00；周六、周日 9:00-12:00"),
                        SportsVenueDetail(title: "收费时段", value: "周一至周五 18:00-22:00；周六、周日 12:00-22:00"),
                        SportsVenueDetail(title: "预约方式", value: "企业微信 -> 事务e办 -> 办事大厅 -> 多功能厅运动场地预约")
                    ],
                    fees: [
                        SportsVenueFee(
                            title: "羽毛球",
                            lines: [
                                SportsVenueDetail(title: "校内师生", value: "40元/小时"),
                                SportsVenueDetail(title: "校外人员（学期内）", value: "不开放/未列明"),
                                SportsVenueDetail(title: "校外人员（寒暑假 9:00-22:00）", value: "80元/小时")
                            ]
                        ),
                        SportsVenueFee(
                            title: "乒乓球",
                            lines: [
                                SportsVenueDetail(title: "校内师生", value: "3元/小时"),
                                SportsVenueDetail(title: "校外人员（学期内）", value: "不开放/未列明"),
                                SportsVenueDetail(title: "校外人员（寒暑假 9:00-22:00）", value: "30元/小时")
                            ]
                        )
                    ],
                    notes: [
                        "免费时段优先安排教学任务；无教学任务时对学生免费开放，需预约使用。",
                        "每周一 9:00 开始预约本周场地，并实时缴费。",
                        "无法按时使用时，请至少提前 24 小时取消预约；未按时取消且未到场使用无法退费。",
                        "费用一般在一个工作日内退回，跨月退费除外。",
                        "场内需穿专业运动鞋，禁止穿黑色胶底鞋及高跟鞋等。",
                        "场馆较新，免费时段较难预约；有人反馈羽毛球场地灯光偏晃眼。"
                    ]
                )
            ]
        ),
        SportsVenueGroup(
            id: "practice",
            title: "其他练习点",
            venues: [
                SportsVenue(
                    id: "east-canteen-hall",
                    title: "东区食堂四层大厅",
                    location: "东区食堂四层",
                    tags: ["练舞", "非办公时间"],
                    details: [
                        SportsVenueDetail(title: "可用时间", value: "白天办公时间不建议使用，晚上可去"),
                        SportsVenueDetail(title: "适合", value: "练舞；灯光不熄，玻璃可作镜面参考")
                    ]
                ),
                SportsVenue(
                    id: "international-dorm-badminton",
                    title: "留学生公寓前羽毛球场地",
                    location: "留学生公寓前",
                    tags: ["户外", "羽毛球"],
                    details: [
                        SportsVenueDetail(title: "适合", value: "约不到室内羽毛球场时的户外替代选择")
                    ]
                ),
                SportsVenue(
                    id: "tianjiabing-skateboard",
                    title: "田家炳体育馆门前",
                    location: "田家炳体育馆门前",
                    tags: ["滑板"],
                    details: [
                        SportsVenueDetail(title: "适合", value: "滑板练习")
                    ]
                )
            ]
        )
    ]
}

private struct SportsVenueGroup: Identifiable {
    let id: String
    let title: String
    let venues: [SportsVenue]
}

private struct SportsVenue: Identifiable {
    let id: String
    let title: String
    let location: String
    let tags: [String]
    let details: [SportsVenueDetail]
    var fees: [SportsVenueFee] = []
    var notes: [String] = []
}

private struct SportsVenueDetail {
    let title: String
    let value: String
}

private struct SportsVenueFee {
    let title: String
    let lines: [SportsVenueDetail]
}
