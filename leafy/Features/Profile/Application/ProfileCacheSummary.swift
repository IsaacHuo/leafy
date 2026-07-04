import Foundation

struct ProfileCacheSummary: Equatable {
    static let empty = ProfileCacheSummary(rows: [])

    let rows: [ProfileCacheSummaryRow]

    static func makeLive(
        language: AppLanguagePreference,
        courseCount: Int,
        gradeCount: Int,
        noteCount: Int,
        reminderCount: Int,
        cellReminderCount: Int,
        favoriteClassroomCount: Int,
        postgraduateTargetCount: Int,
        learningMaterialCount: Int,
        learningProjectCount: Int,
        learningTaskCount: Int,
        studyTimeRecordCount: Int,
        fitnessTestRecordCount: Int
    ) -> ProfileCacheSummary {
        make(
            language: language,
            courseCount: courseCount,
            gradeCount: gradeCount,
            timetableLastSyncAt: TimetableCacheMetadata.lastSyncAt,
            gradeRankingCount: SchoolDataCache.loadGradeRankings().count,
            gradeRankingLastSyncAt: SchoolDataCache.lastSyncDate(for: .gradeRankings),
            gradeCreditTotal: SchoolDataCache.loadGradeCreditSummary()?.totalCredits,
            examCount: SchoolDataCache.loadExamSchedule().count,
            examLastSyncAt: SchoolDataCache.lastSyncDate(for: .examSchedule),
            graduationRequirementCount: SchoolDataCache.loadGraduationRequirements().count,
            graduationRequirementLastSyncAt: SchoolDataCache.lastSyncDate(for: .graduationRequirements),
            classroomsLastSyncAt: SchoolDataCache.lastSyncDate(for: .classrooms),
            noteCount: noteCount,
            reminderCount: reminderCount,
            cellReminderCount: cellReminderCount,
            favoriteClassroomCount: favoriteClassroomCount,
            postgraduateTargetCount: postgraduateTargetCount,
            learningMaterialCount: learningMaterialCount,
            learningProjectCount: learningProjectCount,
            learningTaskCount: learningTaskCount,
            studyTimeRecordCount: studyTimeRecordCount,
            fitnessTestRecordCount: fitnessTestRecordCount
        )
    }

    static func make(
        language: AppLanguagePreference,
        courseCount: Int,
        gradeCount: Int,
        timetableLastSyncAt: Date?,
        gradeRankingCount: Int,
        gradeRankingLastSyncAt: Date?,
        gradeCreditTotal: Double?,
        examCount: Int,
        examLastSyncAt: Date?,
        graduationRequirementCount: Int,
        graduationRequirementLastSyncAt: Date?,
        classroomsLastSyncAt: Date?,
        noteCount: Int,
        reminderCount: Int,
        cellReminderCount: Int,
        favoriteClassroomCount: Int,
        postgraduateTargetCount: Int,
        learningMaterialCount: Int,
        learningProjectCount: Int,
        learningTaskCount: Int,
        studyTimeRecordCount: Int,
        fitnessTestRecordCount: Int
    ) -> ProfileCacheSummary {
        ProfileCacheSummary(rows: [
            ProfileCacheSummaryRow(
                title: "课表",
                value: L10n.text("%d 门课程", language: language, courseCount),
                detail: syncText(timetableLastSyncAt, language: language)
            ),
            ProfileCacheSummaryRow(
                title: "成绩",
                value: L10n.text("%d 条成绩", language: language, gradeCount),
                detail: L10n.text("保存在本机", language: language)
            ),
            ProfileCacheSummaryRow(
                title: "成绩排名",
                value: L10n.text("%d 条记录", language: language, gradeRankingCount),
                detail: syncText(gradeRankingLastSyncAt, language: language)
            ),
            ProfileCacheSummaryRow(
                title: "所得学分",
                value: creditSummaryText(totalCredits: gradeCreditTotal, language: language),
                detail: L10n.text("来自成绩页", language: language)
            ),
            ProfileCacheSummaryRow(
                title: "考试安排",
                value: L10n.text("%d 条考试", language: language, examCount),
                detail: syncText(examLastSyncAt, language: language)
            ),
            ProfileCacheSummaryRow(
                title: "培养方案明细",
                value: L10n.text("%d 条要求", language: language, graduationRequirementCount),
                detail: syncText(graduationRequirementLastSyncAt, language: language)
            ),
            ProfileCacheSummaryRow(
                title: "空教室",
                value: L10n.text("查询缓存", language: language),
                detail: syncText(classroomsLastSyncAt, language: language)
            ),
            ProfileCacheSummaryRow(
                title: "本地数据",
                value: L10n.text("%d 条备注 / %d 个收藏", language: language, noteCount, favoriteClassroomCount),
                detail: L10n.text("%d 个提醒", language: language, reminderCount + cellReminderCount)
            ),
            ProfileCacheSummaryRow(
                title: "学习空间",
                value: L10n.text("%d 个空间 / %d 份资料", language: language, learningProjectCount, learningMaterialCount),
                detail: L10n.text("%d 个任务 / %d 条记录", language: language, learningTaskCount, studyTimeRecordCount)
            ),
            ProfileCacheSummaryRow(
                title: "体测记录",
                value: L10n.text("%d 条记录", language: language, fitnessTestRecordCount),
                detail: L10n.text("保存在本机", language: language)
            )
        ])
    }

    private static func creditSummaryText(totalCredits: Double?, language: AppLanguagePreference) -> String {
        guard let totalCredits else {
            return L10n.text("未缓存", language: language)
        }
        return L10n.text("%.1f 学分", language: language, totalCredits)
    }

    private static func syncText(_ date: Date?, language: AppLanguagePreference) -> String {
        date.map {
            L10n.text("最近同步：%@", language: language, DateFormatters.headerWithTime.string(from: $0))
        } ?? L10n.text("暂无同步记录", language: language)
    }
}

struct ProfileCacheSummaryRow: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let value: String
    let detail: String
}
