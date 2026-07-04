import SafariServices
import SwiftUI

struct TeachingCultivationSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("教学培养", subtitle: sectionSubtitle)

            ToolEntryCard(title: "成绩查询", subtitle: isCustomCampus ? "按模板导入成绩表，查看本地成绩记录" : "查看课程成绩、绩点在各学期记录", icon: "chart.bar.doc.horizontal") {
                openRoute(.grades)
            }

            ToolEntryCard(title: "荣誉记录", subtitle: "保存奖状证书等相关文档和图片", icon: "rosette") {
                openRoute(.honorRecords)
            }

            if !isCustomCampus {
                ToolEntryCard(title: "综素测算", subtitle: "本地估算综素贡献分，整理相关材料", icon: "function") {
                    openRoute(.comprehensiveQuality)
                }

                ToolEntryCard(title: "教学计划", subtitle: "按学期查看课程清单、学分和考核方式", icon: "list.clipboard") {
                    openRoute(.teachingPlan)
                }

                ToolEntryCard(title: "培养方案", subtitle: "查看培养目标、课程体系等", icon: "graduationcap.fill") {
                    openRoute(.trainingProgram)
                }
            }
        }
    }

    private var sectionSubtitle: String {
        if isCustomCampus {
            return "通用学校以本地维护为主：成绩可按模板导入，荣誉记录可手动维护。"
        }
        return "成绩、荣誉、教学计划和培养方案统一收口；个人教务数据仅保存在本机。"
    }
}

struct ScheduleSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("时间日程", subtitle: isCustomCampus ? "考试安排、自定日程和推送设置分开管理。" : "考试、自定日程、校历与作息分开管理。")

            if isCustomCampus {
                ToolEntryCard(title: "课表处理", subtitle: "集中处理手动添加、CSV 导入和示例清理", icon: "slider.horizontal.3") {
                    openRoute(.timetableProcessing)
                }
            }

            ToolEntryCard(title: "考试安排", subtitle: isCustomCampus ? "手动添加或导入考试时间和地点" : "查看教务拉取的考试时间和地点", icon: "calendar.badge.clock") {
                openRoute(.examSchedule)
            }

            ToolEntryCard(title: "自定日程", subtitle: "管理课表日程和任意日期的重要事项", icon: "calendar.badge.plus") {
                openRoute(.customCountdowns)
            }

            ToolEntryCard(title: "日程推送", subtitle: "按时发送课程、考试、重要日期和校历报告", icon: "bell.badge") {
                openRoute(.scheduleReports)
            }

            if !isCustomCampus {
                ToolEntryCard(title: "校历与作息", subtitle: "查看学期校历和作息资源", icon: "calendar.badge.clock") {
                    openRoute(.schoolCalendar)
                }
            }
        }
    }
}

struct ClassroomsSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    @State private var browserItem: LibrarySeatReservationBrowserItem?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("空闲教室", subtitle: "快速搜索空闲教室，随心安静自习。")

            ToolEntryCard(title: "空闲教室", subtitle: "按楼宇、日期和节次快速筛教室", icon: "building.2.crop.circle") {
                openRoute(.emptyClassroom)
            }

            ToolEntryCard(title: "图书馆座位预约", subtitle: "跳转链接", icon: "chair.lounge") {
                browserItem = LibrarySeatReservationBrowserItem(url: LeafyExternalLinks.librarySeat)
            }

            ToolEntryCard(title: "校园热力图", subtitle: "查看当前或自定义时段的教学楼拥挤度", icon: "map.fill") {
                openRoute(.campusHeatmap)
            }

            ToolEntryCard(title: "专注记录", subtitle: "记录每段学习时间、地点和备注", icon: "clock.badge.checkmark") {
                openRoute(.studyTimeRecords)
            }
        }
        .sheet(item: $browserItem) { item in
            LeafySafariView(url: item.url)
        }
    }
}

struct SportsSectionView: View {
    let openRoute: (AcademicDetailRoute) -> Void

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("体育", subtitle: isCustomCampus ? "本地记录阳光长跑和体测，可按学校要求自定义长跑规则。" : "阳光长跑、体测和场馆开放集中管理。")

            ToolEntryCard(title: "阳光长跑", subtitle: isCustomCampus ? "自定义目标次数、周期和假期周规则" : "每两周四次，满分 34 次", icon: "figure.run") {
                openRoute(.sunshineRun)
            }

            ToolEntryCard(title: "体测记录", subtitle: "记录体测项目、成绩和最近趋势", icon: "figure.strengthtraining.traditional") {
                openRoute(.fitnessTestRecords)
            }

            if !isCustomCampus {
                ToolEntryCard(title: "场馆开放", subtitle: "操场、球场、体育馆开放时间与预约方式", icon: "sportscourt") {
                    openRoute(.sportsVenues)
                }
            }
        }
    }
}

struct ToolEntryCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LeafyIconBadge(systemName: icon)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(title, language: leafyLanguage))
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.text(subtitle, language: leafyLanguage))
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(18)
            .leafyCardStyle()
        }
        .buttonStyle(.plain)
    }
}

#if canImport(UIKit)
private struct LeafySafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
private typealias LeafySafariView = LeafyExternalBrowserView
#endif

private struct LibrarySeatReservationBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}
