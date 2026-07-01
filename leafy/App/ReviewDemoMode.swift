import Foundation
import SwiftData

enum ReviewDemoMode {
    static let storageKey = "reviewDemoMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: storageKey)
    }
}

enum ReviewDemoDataSeeder {
    private static let seededKey = "reviewDemoMode.seeded"
    private static let courseBackupKey = "reviewDemoMode.backup.courses"
    private static let gradeBackupKey = "reviewDemoMode.backup.grades"
    private static let defaultsBackupKey = "reviewDemoMode.backup.defaults"
    private static let demoEduID = "review-demo"

    static var displayName: String {
        "\(AppBrand.displayName) 审核演示"
    }

    @MainActor
    static func enter(using modelContext: ModelContext) {
        ReviewDemoMode.isEnabled = true
        ActiveCampusContext.networkManager.persistDemoIdentity(eduID: demoEduID, displayName: displayName)
        seedIfNeeded(using: modelContext)
    }

    @MainActor
    static func seedIfNeeded(using modelContext: ModelContext) {
        guard ReviewDemoMode.isEnabled else { return }
        if !UserDefaults.standard.bool(forKey: seededKey) {
            seed(using: modelContext)
            UserDefaults.standard.set(true, forKey: seededKey)
        } else {
            ActiveCampusContext.networkManager.persistDemoIdentity(eduID: demoEduID, displayName: displayName)
        }
    }

    @MainActor
    static func seed(using modelContext: ModelContext) {
        preserveCurrentSchoolDataIfNeeded(using: modelContext)
        replace(Course.self, in: modelContext, with: sampleCourses)
        replace(Grade.self, in: modelContext, with: sampleGrades)
        ensureFavoriteClassrooms(in: modelContext)
        seedSchoolCaches()
        try? modelContext.save()
    }

    @MainActor
    static func exit(using modelContext: ModelContext? = nil) {
        ReviewDemoMode.isEnabled = false
        UserDefaults.standard.removeObject(forKey: seededKey)
        if let modelContext {
            restorePreservedSchoolData(using: modelContext)
        }
    }

    static func refreshSchoolCaches() {
        seedSchoolCaches()
    }

    static func emptyClassrooms(for date: Date, start: Int, end: Int) -> [EmptyClassroom] {
        let rooms = [
            EmptyClassroom(building: "二教", room: "205"),
            EmptyClassroom(building: "二教", room: "306"),
            EmptyClassroom(building: "主楼", room: "112"),
            EmptyClassroom(building: "学研中心", room: "B203"),
            EmptyClassroom(building: "图书馆", room: "研讨间 3")
        ]
        SchoolDataCache.saveEmptyClassrooms(rooms, date: date, start: start, end: end)
        return rooms
    }

    static func classroomUsage(for date: Date, building: String, room: String) -> [ClassroomUsageSlot] {
        let usage = (1...12).map { period in
            ClassroomUsageSlot(period: period, status: ![3, 4, 9].contains(period) ? .available : .occupied)
        }
        SchoolDataCache.saveClassroomUsage(usage, date: date, building: building, room: room)
        return usage
    }

    static func teacherSummaries(search: String = "") -> [TeacherRatingSummary] {
        let now = ISO8601DateFormatter().string(from: Date())
        let teacherProfiles = [
            TeacherProfile(id: 1, name: "林青", unit: "信息学院", ratingAverage: 4.8, ratingCount: 26, rating1Count: 0, rating2Count: 1, rating3Count: 2, rating4Count: 5, rating5Count: 18, createdAt: now, updatedAt: now),
            TeacherProfile(id: 2, name: "周木", unit: "理学院", ratingAverage: 4.5, ratingCount: 19, rating1Count: 0, rating2Count: 1, rating3Count: 3, rating4Count: 6, rating5Count: 9, createdAt: now, updatedAt: now),
            TeacherProfile(id: 3, name: "叶岚", unit: "经济管理学院", ratingAverage: 4.2, ratingCount: 11, rating1Count: 1, rating2Count: 0, rating3Count: 2, rating4Count: 4, rating5Count: 4, createdAt: now, updatedAt: now)
        ]
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return teacherProfiles
            .filter { teacher in
                normalizedSearch.isEmpty
                    || teacher.name.localizedCaseInsensitiveContains(normalizedSearch)
                    || teacher.unit.localizedCaseInsensitiveContains(normalizedSearch)
            }
            .map { teacher in
                TeacherRatingSummary(
                    teacher: teacher,
                    myRating: TeacherRating(teacherID: teacher.id, userID: demoCommunityUserID, stars: 5, createdAt: now, updatedAt: now)
                )
            }
    }

    static func updatedTeacherSummary(teacherID: Int64, stars: Int) -> TeacherRatingSummary {
        let now = ISO8601DateFormatter().string(from: Date())
        let fallback = teacherSummaries().first(where: { $0.teacher.id == teacherID })?.teacher
            ?? TeacherProfile(id: teacherID, name: "演示教师", unit: "信息学院", ratingAverage: Double(stars), ratingCount: 1, rating1Count: 0, rating2Count: 0, rating3Count: 0, rating4Count: 0, rating5Count: 1, createdAt: now, updatedAt: now)

        return TeacherRatingSummary(
            teacher: TeacherProfile(
                id: fallback.id,
                name: fallback.name,
                unit: fallback.unit,
                ratingAverage: Double(stars),
                ratingCount: max(fallback.ratingCount, 1),
                rating1Count: stars == 1 ? max(fallback.rating1Count, 1) : fallback.rating1Count,
                rating2Count: stars == 2 ? max(fallback.rating2Count, 1) : fallback.rating2Count,
                rating3Count: stars == 3 ? max(fallback.rating3Count, 1) : fallback.rating3Count,
                rating4Count: stars == 4 ? max(fallback.rating4Count, 1) : fallback.rating4Count,
                rating5Count: stars == 5 ? max(fallback.rating5Count, 1) : fallback.rating5Count,
                createdAt: fallback.createdAt,
                updatedAt: now
            ),
            myRating: TeacherRating(teacherID: teacherID, userID: demoCommunityUserID, stars: stars, createdAt: now, updatedAt: now)
        )
    }

    static func courseRatingSummaries(
        search: String = "",
        category: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) -> [CourseRatingSummary] {
        let now = ISO8601DateFormatter().string(from: Date())
        let courseProfiles = [
            CourseProfile(id: 1, name: "森林生态学导论", unit: "林学院", category: "公选课", credit: 2, ratingAverage: 4.7, ratingCount: 31, rating1Count: 0, rating2Count: 1, rating3Count: 2, rating4Count: 6, rating5Count: 22, createdAt: now, updatedAt: now),
            CourseProfile(id: 2, name: "审美艺术导论", unit: "艺术设计学院", category: "公选课", credit: 2, ratingAverage: 4.4, ratingCount: 18, rating1Count: 0, rating2Count: 1, rating3Count: 3, rating4Count: 5, rating5Count: 9, createdAt: now, updatedAt: now),
            CourseProfile(id: 3, name: "写作与沟通", unit: "人文社会科学学院", category: "公选课", credit: 1.5, ratingAverage: 4.1, ratingCount: 12, rating1Count: 1, rating2Count: 0, rating3Count: 2, rating4Count: 5, rating5Count: 4, createdAt: now, updatedAt: now)
        ]
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = courseProfiles
            .filter { course in
                normalizedSearch.isEmpty
                    || course.name.localizedCaseInsensitiveContains(normalizedSearch)
                    || course.unit.localizedCaseInsensitiveContains(normalizedSearch)
                    || course.category.localizedCaseInsensitiveContains(normalizedSearch)
            }
            .filter { course in
                guard let normalizedCategory, !normalizedCategory.isEmpty else { return true }
                return course.category == normalizedCategory
            }

        return Array(filtered.dropFirst(max(offset, 0)).prefix(max(limit, 1))).map { course in
            CourseRatingSummary(
                course: course,
                myRating: CourseRating(courseID: course.id, userID: demoCommunityUserID, stars: 5, createdAt: now, updatedAt: now)
            )
        }
    }

    static func updatedCourseSummary(courseID: Int64, stars: Int) -> CourseRatingSummary {
        let now = ISO8601DateFormatter().string(from: Date())
        let fallback = courseRatingSummaries().first(where: { $0.course.id == courseID })?.course
            ?? CourseProfile(id: courseID, name: "演示课程", unit: "开课单位", category: "公选课", credit: 2, ratingAverage: Double(stars), ratingCount: 1, rating1Count: 0, rating2Count: 0, rating3Count: 0, rating4Count: 0, rating5Count: 1, createdAt: now, updatedAt: now)

        return CourseRatingSummary(
            course: CourseProfile(
                id: fallback.id,
                name: fallback.name,
                unit: fallback.unit,
                category: fallback.category,
                credit: fallback.credit,
                ratingAverage: Double(stars),
                ratingCount: max(fallback.ratingCount, 1),
                rating1Count: stars == 1 ? max(fallback.rating1Count, 1) : fallback.rating1Count,
                rating2Count: stars == 2 ? max(fallback.rating2Count, 1) : fallback.rating2Count,
                rating3Count: stars == 3 ? max(fallback.rating3Count, 1) : fallback.rating3Count,
                rating4Count: stars == 4 ? max(fallback.rating4Count, 1) : fallback.rating4Count,
                rating5Count: stars == 5 ? max(fallback.rating5Count, 1) : fallback.rating5Count,
                createdAt: fallback.createdAt,
                updatedAt: now
            ),
            myRating: CourseRating(courseID: courseID, userID: demoCommunityUserID, stars: stars, createdAt: now, updatedAt: now)
        )
    }

    static func dishRatingSummaries(
        search: String = "",
        canteen: String? = nil,
        location: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) -> [DishRatingSummary] {
        let now = ISO8601DateFormatter().string(from: Date())
        let dishProfiles = [
            DishProfile(id: 1, name: "番茄牛腩饭", location: "东区食堂 · 一层 · 学一食堂", ratingAverage: 4.6, ratingCount: 24, rating1Count: 0, rating2Count: 1, rating3Count: 2, rating4Count: 5, rating5Count: 16, createdAt: now, updatedAt: now),
            DishProfile(id: 2, name: "鸡腿盖饭", location: "东区食堂 · 二层 · 学四食堂", ratingAverage: 4.3, ratingCount: 18, rating1Count: 1, rating2Count: 1, rating3Count: 2, rating4Count: 6, rating5Count: 8, createdAt: now, updatedAt: now),
            DishProfile(id: 3, name: "麻辣香锅", location: "西区食堂 · 二层 · 齐芳阁餐厅", ratingAverage: 4.8, ratingCount: 36, rating1Count: 0, rating2Count: 0, rating3Count: 2, rating4Count: 4, rating5Count: 30, createdAt: now, updatedAt: now),
            DishProfile(id: 4, name: "热干面", location: "西区食堂 · B1层 · 小食光餐厅", ratingAverage: 4.2, ratingCount: 13, rating1Count: 1, rating2Count: 0, rating3Count: 2, rating4Count: 4, rating5Count: 6, createdAt: now, updatedAt: now)
        ]
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCanteen = canteen?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = dishProfiles
            .filter { dish in
                normalizedSearch.isEmpty
                    || dish.name.localizedCaseInsensitiveContains(normalizedSearch)
                    || dish.location.localizedCaseInsensitiveContains(normalizedSearch)
            }
            .filter { dish in
                guard let normalizedCanteen, !normalizedCanteen.isEmpty else { return true }
                return dish.location.hasPrefix(normalizedCanteen)
            }
            .filter { dish in
                guard let normalizedLocation, !normalizedLocation.isEmpty else { return true }
                return dish.location == normalizedLocation
            }

        return Array(filtered.dropFirst(max(offset, 0)).prefix(max(limit, 1))).map { dish in
            DishRatingSummary(
                dish: dish,
                myRating: DishRating(dishID: dish.id, userID: demoCommunityUserID, stars: 5, createdAt: now, updatedAt: now)
            )
        }
    }

    static func updatedDishSummary(dishID: Int64, stars: Int) -> DishRatingSummary {
        let now = ISO8601DateFormatter().string(from: Date())
        let fallback = dishRatingSummaries().first(where: { $0.dish.id == dishID })?.dish
            ?? DishProfile(id: dishID, name: "演示菜品", location: "东区食堂 · 一层 · 学一食堂", ratingAverage: Double(stars), ratingCount: 1, rating1Count: 0, rating2Count: 0, rating3Count: 0, rating4Count: 0, rating5Count: 1, createdAt: now, updatedAt: now)

        return DishRatingSummary(
            dish: DishProfile(
                id: fallback.id,
                name: fallback.name,
                location: fallback.location,
                ratingAverage: Double(stars),
                ratingCount: max(fallback.ratingCount, 1),
                rating1Count: stars == 1 ? max(fallback.rating1Count, 1) : fallback.rating1Count,
                rating2Count: stars == 2 ? max(fallback.rating2Count, 1) : fallback.rating2Count,
                rating3Count: stars == 3 ? max(fallback.rating3Count, 1) : fallback.rating3Count,
                rating4Count: stars == 4 ? max(fallback.rating4Count, 1) : fallback.rating4Count,
                rating5Count: stars == 5 ? max(fallback.rating5Count, 1) : fallback.rating5Count,
                createdAt: fallback.createdAt,
                updatedAt: now
            ),
            myRating: DishRating(dishID: dishID, userID: demoCommunityUserID, stars: stars, createdAt: now, updatedAt: now)
        )
    }

    private static let demoCommunityUserID = UUID(uuidString: "DEDEDEDE-DEDE-4DED-9DED-DEDEDEDEDEDE") ?? UUID()

    private static var sampleCourses: [Course] {
        [
            Course(courseName: "数据结构", teacher: "林青", classInfo: "演示班", room: "二教 205", location: "二教 205", dayOfWeek: 1, weeks: Array(1...16), duration: [1, 2]),
            Course(courseName: "高等数学 A", teacher: "周木", classInfo: "演示班", room: "主楼 112", location: "主楼 112", dayOfWeek: 2, weeks: Array(1...18), duration: [3, 4]),
            Course(courseName: "大学英语", teacher: "叶岚", classInfo: "演示班", room: "学研中心 B203", location: "学研中心 B203", dayOfWeek: 3, weeks: Array(1...16), duration: [5, 6]),
            Course(courseName: "森林生态学导论", teacher: "陈森", classInfo: "演示班", room: "二教 306", location: "二教 306", dayOfWeek: 4, weeks: Array(3...14), duration: [7, 8]),
            Course(courseName: "体育", teacher: "王青", classInfo: "演示班", room: "操场", location: "操场", dayOfWeek: 5, weeks: Array(1...16), duration: [3, 4])
        ]
    }

    private static var sampleGrades: [Grade] {
        [
            Grade(term: "2025-2026-2", courseName: "数据结构", credit: "3.0", score: "92", type: "必修"),
            Grade(term: "2025-2026-2", courseName: "大学英语", credit: "2.0", score: "88", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "高等数学 A", credit: "5.0", score: "90", type: "必修"),
            Grade(term: "2025-2026-1", courseName: "森林生态学导论", credit: "2.0", score: "优秀", type: "公选")
        ]
    }

    private static func seedSchoolCaches() {
        let today = Date()
        SchoolDataCache.saveExamSchedule([
            ExamArrangement(id: 1, courseID: "DS-001", name: "数据结构", date: futureDateString(days: 9), start: "09:00", end: "11:00", location: "二教 205"),
            ExamArrangement(id: 2, courseID: "MATH-001", name: "高等数学 A", date: futureDateString(days: 16), start: "14:00", end: "16:00", location: "主楼 112")
        ])
        SchoolDataCache.saveTeachingPlan([
            TeachingPlanSection(term: "2025-2026-1", courses: [
                TeachingPlanCourse(id: 1, period: "2025-2026-1", name: "高等数学 A", unit: "理学院", credit: 5, duration: "80", type: "必修", exam: "考试"),
                TeachingPlanCourse(id: 2, period: "2025-2026-1", name: "程序设计基础", unit: "信息学院", credit: 3, duration: "48", type: "必修", exam: "考试")
            ]),
            TeachingPlanSection(term: "2025-2026-2", courses: [
                TeachingPlanCourse(id: 3, period: "2025-2026-2", name: "数据结构", unit: "信息学院", credit: 3, duration: "48", type: "必修", exam: "考试"),
                TeachingPlanCourse(id: 4, period: "2025-2026-2", name: "森林生态学导论", unit: "林学院", credit: 2, duration: "32", type: "公选", exam: "考查")
            ])
        ])
        SchoolDataCache.saveGradeRankings([
            GradeRankingRecord(term: "全部学期", rankingRange: "专业", rank: 12, totalCount: 186, percentile: 0.064, metricText: "综合排名", rawFields: ["范围": "全部学期"]),
            GradeRankingRecord(term: "2025-2026-1", rankingRange: "专业", rank: 15, totalCount: 186, percentile: 0.081, metricText: "学期排名", rawFields: [:])
        ])
        SchoolDataCache.saveGradeCreditSummary(
            GradeCreditSummary(
                totalCredits: 12,
                requiredCredits: 170,
                professionalElectiveCredits: 0,
                professionalMajorElectiveCredits: 0,
                professionalCrossMajorElectiveCredits: 0,
                publicElectiveCredits: 2,
                officialGPA: 3.86,
                officialWeightedAverage: 91.08,
                officialCreditPoint: 44.6,
                publicElectiveBuckets: [
                    GradeCreditBucket(name: "自然科学", credits: 2),
                    GradeCreditBucket(name: "人文社科", credits: 0)
                ],
                rawFields: [:]
            )
        )
        SchoolDataCache.saveTrainingProgram(
            TrainingProgramDocument(
                title: "计算机科学与技术专业培养方案（演示）",
                sections: [
                    TrainingProgramSection(id: "goal", title: "培养目标", body: "培养具备计算思维、工程实践和校园信息化服务能力的复合型人才。"),
                    TrainingProgramSection(id: "courses", title: "课程体系", body: "课程包含数学基础、程序设计、数据结构、数据库、软件工程和实践训练。")
                ],
                creditRequirements: [
                    GraduationCreditRequirement(id: "total", category: "总学分", courseName: "毕业要求", requiredCredits: 170, plannedCredits: 170, isAggregate: true),
                    GraduationCreditRequirement(id: "public", category: "公共选修", courseName: "通识课程", requiredCredits: 8, plannedCredits: 8, isAggregate: true),
                    GraduationCreditRequirement(id: "major", category: "专业选修", courseName: "专业方向课程", requiredCredits: 24, plannedCredits: 24, isAggregate: true)
                ]
            )
        )
        _ = emptyClassrooms(for: today, start: 1, end: 2)
        _ = classroomUsage(for: today, building: "二教", room: "205")
        TimetableCacheMetadata.lastSyncAt = Date()
        TimetableCacheMetadata.lastFailureMessage = nil
    }

    @MainActor
    private static func ensureFavoriteClassrooms(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<FavoriteClassroom>()
        let favorites = (try? modelContext.fetch(descriptor)) ?? []
        if !favorites.contains(where: { $0.building == "二教" && $0.room == "205" }) {
            modelContext.insert(FavoriteClassroom(building: "二教", room: "205"))
        }
    }

    @MainActor
    private static func preserveCurrentSchoolDataIfNeeded(using modelContext: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: courseBackupKey) == nil,
              defaults.data(forKey: gradeBackupKey) == nil,
              defaults.dictionary(forKey: defaultsBackupKey) == nil else {
            return
        }

        let courses = ((try? modelContext.fetch(FetchDescriptor<Course>())) ?? []).map(CourseBackup.init)
        let grades = ((try? modelContext.fetch(FetchDescriptor<Grade>())) ?? []).map(GradeBackup.init)
        if let data = try? JSONEncoder().encode(courses) {
            defaults.set(data, forKey: courseBackupKey)
        }
        if let data = try? JSONEncoder().encode(grades) {
            defaults.set(data, forKey: gradeBackupKey)
        }

        let snapshot = defaults.dictionaryRepresentation().filter { key, _ in
            key.hasPrefix("schoolCache.") || key.hasPrefix("timetable.")
        }
        defaults.set(snapshot, forKey: defaultsBackupKey)
    }

    @MainActor
    private static func restorePreservedSchoolData(using modelContext: ModelContext) {
        deleteAll(Course.self, in: modelContext)
        deleteAll(Grade.self, in: modelContext)
        SchoolDataCache.clearDiscoverCaches()
        TimetableCacheMetadata.clear()

        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: courseBackupKey),
           let courses = try? JSONDecoder().decode([CourseBackup].self, from: data) {
            courses.map(\.course).forEach { modelContext.insert($0) }
        }
        if let data = defaults.data(forKey: gradeBackupKey),
           let grades = try? JSONDecoder().decode([GradeBackup].self, from: data) {
            grades.map(\.grade).forEach { modelContext.insert($0) }
        }
        if let snapshot = defaults.dictionary(forKey: defaultsBackupKey) {
            for (key, value) in snapshot {
                defaults.set(value, forKey: key)
            }
        }

        defaults.removeObject(forKey: courseBackupKey)
        defaults.removeObject(forKey: gradeBackupKey)
        defaults.removeObject(forKey: defaultsBackupKey)
        try? modelContext.save()
    }

    @MainActor
    private static func replace<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext, with values: [T]) {
        deleteAll(type, in: modelContext)
        values.forEach { modelContext.insert($0) }
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<T>()
        for item in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(item)
        }
    }

    private static func futureDateString(days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return DateFormatters.queryDate.string(from: date)
    }

    private struct CourseBackup: Codable {
        let courseName: String
        let teacher: String
        let classInfo: String
        let room: String
        let location: String
        let dayOfWeek: Int
        let weeks: [Int]
        let duration: [Int]

        init(_ course: Course) {
            courseName = course.courseName
            teacher = course.teacher
            classInfo = course.classInfo
            room = course.room
            location = course.location
            dayOfWeek = course.dayOfWeek
            weeks = course.weeks
            duration = course.duration
        }

        var course: Course {
            Course(
                courseName: courseName,
                teacher: teacher,
                classInfo: classInfo,
                room: room,
                location: location,
                dayOfWeek: dayOfWeek,
                weeks: weeks,
                duration: duration
            )
        }
    }

    private struct GradeBackup: Codable {
        let term: String
        let courseName: String
        let credit: String
        let score: String
        let type: String

        init(_ grade: Grade) {
            term = grade.term
            courseName = grade.courseName
            credit = grade.credit
            score = grade.score
            type = grade.type
        }

        var grade: Grade {
            Grade(term: term, courseName: courseName, credit: credit, score: score, type: type)
        }
    }
}
