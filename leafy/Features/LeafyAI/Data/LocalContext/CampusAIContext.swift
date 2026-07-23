nonisolated struct CampusAIContextPayload: Codable, Hashable {
    let generatedAt: String
    let campusID: String
    let campusName: String
    let currentWeek: Int
    let currentDayOfWeek: Int
    let includedScopes: [String]
    let omittedScopes: [String]
    let dataBoundary: [String]
    let sourceStatus: [CampusAIContextSourceStatus]
    let timetable: CampusAITimetableContext
    let exams: [CampusAIExamContext]
    let grades: CampusAIGradeContext
    let teachingPlan: [CampusAITeachingPlanContext]
    let trainingProgram: CampusAITrainingProgramContext?
    let countdowns: [CampusAICountdownContext]
    let learningWorkspace: CampusAILearningWorkspaceContext
    let postgraduateAndCareer: CampusAIPostgraduateCareerContext
    let honorsFitnessQuality: CampusAIHonorsFitnessQualityContext
    let medicalLedger: CampusAIMedicalLedgerContext
    let communityCache: CampusAICommunityCacheContext

    var hasReadableAcademicData: Bool {
        !timetable.today.isEmpty ||
            !timetable.currentWeek.isEmpty ||
            !timetable.allCourses.isEmpty ||
            !exams.isEmpty ||
            grades.courseCount > 0 ||
            !teachingPlan.isEmpty ||
            trainingProgram != nil ||
            !countdowns.isEmpty ||
            learningWorkspace.hasContent ||
            postgraduateAndCareer.hasContent ||
            honorsFitnessQuality.hasContent ||
            medicalLedger.hasContent
    }
}

nonisolated private extension String {
    func clampedForAIContext(_ limit: Int = 240) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(limit - 1, 0))) + "…"
    }
}

nonisolated enum CampusAIContextSourceState: String, Codable, Hashable {
    case available
    case missing
    case disabled
    case localOnly
}

nonisolated struct CampusAIContextSourceStatus: Codable, Hashable {
    let scope: String
    let itemCount: Int
    let lastSyncAt: String?
    let state: CampusAIContextSourceState
    let note: String
}

nonisolated struct CampusAITimetableContext: Codable, Hashable {
    let today: [CampusAICourseContext]
    let currentWeek: [CampusAICourseContext]
    let allCourses: [CampusAICourseContext]
    let courseNotes: [CampusAICourseNoteContext]
    let occurrenceNotes: [CampusAICourseOccurrenceNoteContext]
    let courseReminders: [CampusAICourseReminderContext]
    let cellReminders: [CampusAITimetableCellReminderContext]
    let favoriteClassrooms: [String]
}

nonisolated struct CampusAICourseContext: Codable, Hashable {
    let name: String
    let teacher: String
    let room: String
    let location: String
    let dayOfWeek: Int
    let periods: [Int]
    let weeks: [Int]
}

nonisolated struct CampusAIExamContext: Codable, Hashable {
    let name: String
    let date: String
    let start: String
    let end: String
    let location: String
}

nonisolated struct CampusAIGradeContext: Codable, Hashable {
    let courseCount: Int
    let termCount: Int
    let latestTerm: String?
    let officialGPA: Double?
    let officialWeightedAverage: Double?
    let totalCredits: Double?
    let requiredCredits: Double?
    let publicElectiveCredits: Double?
    let professionalElectiveCredits: Double?
    let recentCourses: [CampusAIGradeCourseContext]
    let allCourses: [CampusAIGradeCourseContext]
    let rankings: [CampusAIGradeRankingContext]
}

nonisolated struct CampusAIGradeCourseContext: Codable, Hashable {
    let term: String
    let name: String
    let credit: String
    let score: String
    let type: String
}

nonisolated struct CampusAITeachingPlanContext: Codable, Hashable {
    let term: String
    let totalCredits: Double
    let courses: [String]
}

nonisolated struct CampusAITrainingProgramContext: Codable, Hashable {
    let title: String
    let sections: [String]
    let creditRequirements: [String]
}

nonisolated struct CampusAICountdownContext: Codable, Hashable {
    let title: String
    let targetDate: String
}

nonisolated struct CampusAICourseNoteContext: Codable, Hashable {
    let courseName: String
    let text: String
    let updatedAt: String
}

nonisolated struct CampusAICourseOccurrenceNoteContext: Codable, Hashable {
    let courseName: String
    let week: Int
    let dayOfWeek: Int
    let text: String
    let updatedAt: String
}

nonisolated struct CampusAICourseReminderContext: Codable, Hashable {
    let courseName: String
    let minutesBefore: Int
    let anchorPeriod: Int?
    let updatedAt: String
}

nonisolated struct CampusAITimetableCellReminderContext: Codable, Hashable {
    let week: Int
    let dayOfWeek: Int
    let period: Int
    let endPeriod: Int?
    let title: String
    let location: String?
    let note: String?
    let minutesBefore: Int
    let updatedAt: String
}

nonisolated struct CampusAIGradeRankingContext: Codable, Hashable {
    let term: String
    let range: String
    let rank: Int?
    let totalCount: Int?
    let percentile: Double?
    let metric: String
}

nonisolated struct CampusAILearningWorkspaceContext: Codable, Hashable {
    let projects: [CampusAILearningProjectContext]
    let tasks: [CampusAILearningTaskContext]
    let materials: [CampusAIFileMetadataContext]
    let studyRecords: [CampusAIStudyRecordContext]

    static let empty = CampusAILearningWorkspaceContext(projects: [], tasks: [], materials: [], studyRecords: [])

    var hasContent: Bool {
        !projects.isEmpty || !tasks.isEmpty || !materials.isEmpty || !studyRecords.isEmpty
    }
}

nonisolated struct CampusAILearningProjectContext: Codable, Hashable {
    let title: String
    let kind: String
    let goal: String
    let isArchived: Bool
    let updatedAt: String
}

nonisolated struct CampusAILearningTaskContext: Codable, Hashable {
    let title: String
    let category: String
    let note: String
    let dueAt: String?
    let isCompleted: Bool
    let updatedAt: String
}

nonisolated struct CampusAIFileMetadataContext: Codable, Hashable {
    let title: String
    let note: String
    let category: String
    let fileType: String
    let updatedAt: String
}

nonisolated struct CampusAIStudyRecordContext: Codable, Hashable {
    let content: String
    let category: String
    let location: String
    let note: String
    let startedAt: String
    let minutes: Int
}

nonisolated struct CampusAIPostgraduateCareerContext: Codable, Hashable {
    let postgraduateTargets: [CampusAIPostgraduateTargetContext]
    let resumes: [CampusAIFileMetadataContext]
    let careerTasks: [CampusAICareerTaskContext]
    let opportunities: [CampusAICareerOpportunityContext]

    static let empty = CampusAIPostgraduateCareerContext(
        postgraduateTargets: [],
        resumes: [],
        careerTasks: [],
        opportunities: []
    )

    var hasContent: Bool {
        !postgraduateTargets.isEmpty || !resumes.isEmpty || !careerTasks.isEmpty || !opportunities.isEmpty
    }
}

nonisolated struct CampusAIPostgraduateTargetContext: Codable, Hashable {
    let school: String
    let unit: String
    let major: String
    let direction: String
    let examYear: Int
    let subjects: String
    let scoreAndPlanNote: String
    let personalNote: String
    let state: String
    let updatedAt: String
}

nonisolated struct CampusAICareerTaskContext: Codable, Hashable {
    let title: String
    let note: String
    let dueAt: String?
    let isCompleted: Bool
    let updatedAt: String
}

nonisolated struct CampusAICareerOpportunityContext: Codable, Hashable {
    let title: String
    let organization: String
    let status: String
    let note: String
    let updatedAt: String
}

nonisolated struct CampusAIHonorsFitnessQualityContext: Codable, Hashable {
    let honors: [CampusAIFileMetadataContext]
    let fitnessTests: [CampusAIFitnessTestContext]
    let comprehensiveQualityRecords: [CampusAIComprehensiveQualityRecordContext]
    let comprehensiveQualityComponents: [CampusAIComprehensiveQualityComponentContext]
    let comprehensiveQualityEvidence: [CampusAIFileMetadataContext]

    static let empty = CampusAIHonorsFitnessQualityContext(
        honors: [],
        fitnessTests: [],
        comprehensiveQualityRecords: [],
        comprehensiveQualityComponents: [],
        comprehensiveQualityEvidence: []
    )

    var hasContent: Bool {
        !honors.isEmpty ||
            !fitnessTests.isEmpty ||
            !comprehensiveQualityRecords.isEmpty ||
            !comprehensiveQualityComponents.isEmpty ||
            !comprehensiveQualityEvidence.isEmpty
    }
}

nonisolated struct CampusAIFitnessTestContext: Codable, Hashable {
    let item: String
    let value: String
    let note: String
    let testedAt: String
}

nonisolated struct CampusAIComprehensiveQualityRecordContext: Codable, Hashable {
    let collegeName: String
    let cohort: String
    let academicStandardScore: Double?
    let officialQualityScore: Double?
    let officialCompositeScore: Double?
    let note: String
    let updatedAt: String
}

nonisolated struct CampusAIComprehensiveQualityComponentContext: Codable, Hashable {
    let collegeName: String
    let cohort: String
    let component: String
    let rawScore: Double?
    let peerMaxScore: Double?
    let officialStandardScore: Double?
    let materialReady: Bool
    let note: String
    let updatedAt: String
}

nonisolated struct CampusAIMedicalLedgerContext: Codable, Hashable {
    let entries: [CampusAIMedicalLedgerEntryContext]
    let photoCount: Int

    static let empty = CampusAIMedicalLedgerContext(entries: [], photoCount: 0)

    var hasContent: Bool {
        !entries.isEmpty || photoCount > 0
    }
}

nonisolated struct CampusAIMedicalLedgerEntryContext: Codable, Hashable {
    let visitDate: String
    let hospitalName: String
    let department: String
    let diagnosisNote: String
    let scenario: String
    let totalExpense: Double
    let estimatedReimbursement: Double?
    let actualReimbursement: Double?
    let status: String
    let reimbursementDeadline: String?
    let materials: [String]
    let note: String
    let photoCount: Int
    let updatedAt: String
}

nonisolated struct CampusAICommunityCacheContext: Codable, Hashable {
    let posts: [CampusAICommunityPostContext]

    static let empty = CampusAICommunityCacheContext(posts: [])

    var hasContent: Bool {
        !posts.isEmpty
    }
}

nonisolated struct CampusAICommunityPostContext: Codable, Hashable {
    let title: String
    let body: String
    let category: String?
    let commentCount: Int
    let likeCount: Int
    let imageCount: Int
    let createdAt: String
    let updatedAt: String
}

nonisolated enum CampusAIContextBuilder {
    @MainActor
    static func build(
        modelContext: ModelContext,
        settings: CampusAIContextSettings = .defaultValue,
        now: Date = Date()
    ) -> CampusAIContextPayload {
        build(
            courses: fetch(Course.self, in: modelContext),
            courseNotes: fetch(CourseNote.self, in: modelContext),
            occurrenceNotes: fetch(CourseOccurrenceNote.self, in: modelContext),
            courseReminders: fetch(CourseReminderSetting.self, in: modelContext),
            cellReminders: fetch(TimetableCellReminder.self, in: modelContext),
            favoriteClassrooms: fetch(FavoriteClassroom.self, in: modelContext),
            grades: fetch(Grade.self, in: modelContext),
            gradeRankings: SchoolDataCache.loadGradeRankings(),
            exams: SchoolDataCache.loadExamSchedule(),
            teachingPlan: SchoolDataCache.loadTeachingPlan(),
            trainingProgram: SchoolDataCache.loadTrainingProgram(),
            gradeCreditSummary: SchoolDataCache.loadGradeCreditSummary(),
            countdowns: CustomScheduleStore.load(),
            learningMaterials: fetch(LearningMaterialDocument.self, in: modelContext),
            learningProjects: fetch(LearningProject.self, in: modelContext),
            learningTasks: fetch(LearningProjectTask.self, in: modelContext),
            studyRecords: fetch(StudyTimeRecord.self, in: modelContext),
            postgraduateTargets: fetch(PostgraduateTarget.self, in: modelContext),
            careerResumes: fetch(CareerResumeDocument.self, in: modelContext),
            careerTasks: fetch(CareerTask.self, in: modelContext),
            careerOpportunities: fetch(CareerOpportunity.self, in: modelContext),
            honors: fetch(HonorRecord.self, in: modelContext),
            fitnessTests: fetch(FitnessTestRecord.self, in: modelContext),
            qualityRecords: fetch(ComprehensiveQualityRecord.self, in: modelContext),
            qualityComponents: fetch(ComprehensiveQualityComponentEntry.self, in: modelContext),
            qualityEvidence: fetch(ComprehensiveQualityEvidenceDocument.self, in: modelContext),
            medicalEntries: fetch(MedicalLedgerEntry.self, in: modelContext),
            medicalPhotos: fetch(MedicalLedgerPhoto.self, in: modelContext),
            timetableLastSyncAt: TimetableCacheMetadata.lastSyncAt,
            gradeDetailsLastSyncAt: SchoolDataCache.lastSyncDate(for: .gradeDetails),
            gradeSupplementalLastSyncAt: SchoolDataCache.lastSyncDate(for: .gradeRankings),
            examScheduleLastSyncAt: SchoolDataCache.lastSyncDate(for: .examSchedule),
            teachingPlanLastSyncAt: SchoolDataCache.lastSyncDate(for: .teachingPlan),
            trainingProgramLastSyncAt: SchoolDataCache.lastSyncDate(for: .graduationRequirements),
            settings: settings,
            now: now
        )
    }

    static func build(
        courses: [Course],
        courseNotes: [CourseNote] = [],
        occurrenceNotes: [CourseOccurrenceNote] = [],
        courseReminders: [CourseReminderSetting] = [],
        cellReminders: [TimetableCellReminder] = [],
        favoriteClassrooms: [FavoriteClassroom] = [],
        grades: [Grade],
        gradeRankings: [GradeRankingRecord] = [],
        exams: [ExamArrangement],
        teachingPlan: [TeachingPlanSection],
        trainingProgram: TrainingProgramDocument?,
        gradeCreditSummary: GradeCreditSummary? = nil,
        countdowns: [CustomScheduleEvent],
        learningMaterials: [LearningMaterialDocument] = [],
        learningProjects: [LearningProject] = [],
        learningTasks: [LearningProjectTask] = [],
        studyRecords: [StudyTimeRecord] = [],
        postgraduateTargets: [PostgraduateTarget] = [],
        careerResumes: [CareerResumeDocument] = [],
        careerTasks: [CareerTask] = [],
        careerOpportunities: [CareerOpportunity] = [],
        honors: [HonorRecord] = [],
        fitnessTests: [FitnessTestRecord] = [],
        qualityRecords: [ComprehensiveQualityRecord] = [],
        qualityComponents: [ComprehensiveQualityComponentEntry] = [],
        qualityEvidence: [ComprehensiveQualityEvidenceDocument] = [],
        medicalEntries: [MedicalLedgerEntry] = [],
        medicalPhotos: [MedicalLedgerPhoto] = [],
        timetableLastSyncAt: Date? = nil,
        gradeDetailsLastSyncAt: Date? = nil,
        gradeSupplementalLastSyncAt: Date? = nil,
        examScheduleLastSyncAt: Date? = nil,
        teachingPlanLastSyncAt: Date? = nil,
        trainingProgramLastSyncAt: Date? = nil,
        settings: CampusAIContextSettings = .defaultValue,
        now: Date = Date()
    ) -> CampusAIContextPayload {
        let weekAndDay = SemesterConfig.weekAndDay(for: now)
        let todayStart = Calendar.current.startOfDay(for: now)
        let sortedCourses = courses.sorted(by: courseSort)
        let weekCourses = sortedCourses
            .filter { $0.weeks.contains(weekAndDay.week) }
        let todayCourses = weekCourses.filter { $0.dayOfWeek == weekAndDay.day }
        let sortedExams = exams
            .filter { exam in
                guard let startsAt = examStartDate(exam) else { return true }
                return startsAt >= todayStart
            }
            .sorted { lhs, rhs in
                (examStartDate(lhs) ?? .distantFuture) < (examStartDate(rhs) ?? .distantFuture)
            }
        let includedScopes = includedScopeNames(settings)
        let omittedScopes = omittedScopeNames(settings)
        let courseNamesByKey = LeafyFirstValueMap.build(
            courses.map { ($0.stableCourseKey, $0.courseName) }
        )
        let photoCounts = Dictionary(grouping: medicalPhotos, by: \.entryID).mapValues(\.count)

        return CampusAIContextPayload(
            generatedAt: ISO8601DateFormatter().string(from: now),
            campusID: ActiveCampusContext.descriptor.id.rawValue,
            campusName: ActiveCampusContext.descriptor.displayName,
            currentWeek: weekAndDay.week,
            currentDayOfWeek: weekAndDay.day,
            includedScopes: includedScopes,
            omittedScopes: omittedScopes,
            dataBoundary: [
                "仅包含用户在设置中允许的本机缓存或本地保存结构化数据。",
                "课表字段 today 和 currentWeek 是当前日期/本周子集；timetable.allCourses 是当前设备已缓存的全学期课程集合。",
                "用户上传文件本体、图片像素、OCR、PDF/Word/PPT/表格正文和本地文件路径永远不会进入上下文。",
                "社区上下文仅来自当前设备缓存的公开 feed 摘要，不包含私信、图片 URL 或未缓存远端内容。"
            ],
            sourceStatus: sourceStatuses(
                settings: settings,
                timetableCount: sortedCourses.count,
                timetableLastSyncAt: timetableLastSyncAt,
                gradeCount: grades.count,
                gradeDetailsLastSyncAt: gradeDetailsLastSyncAt,
                gradeSupplementalCount: gradeRankings.count + (gradeCreditSummary.map { _ in 1 } ?? 0),
                gradeSupplementalLastSyncAt: gradeSupplementalLastSyncAt,
                examCount: sortedExams.count,
                examScheduleLastSyncAt: examScheduleLastSyncAt,
                teachingPlanCourseCount: teachingPlan.reduce(0) { $0 + $1.courses.count },
                teachingPlanLastSyncAt: teachingPlanLastSyncAt,
                trainingProgramRequirementCount: trainingProgram?.creditRequirements.count ?? 0,
                trainingProgramLastSyncAt: trainingProgramLastSyncAt,
                localSavedDataCount: localSavedDataCount(
                    settings: settings,
                    courseNotes: courseNotes,
                    occurrenceNotes: occurrenceNotes,
                    courseReminders: courseReminders,
                    cellReminders: cellReminders,
                    favoriteClassrooms: favoriteClassrooms,
                    countdowns: countdowns,
                    learningMaterials: learningMaterials,
                    learningProjects: learningProjects,
                    learningTasks: learningTasks,
                    studyRecords: studyRecords,
                    postgraduateTargets: postgraduateTargets,
                    careerResumes: careerResumes,
                    careerTasks: careerTasks,
                    careerOpportunities: careerOpportunities,
                    honors: honors,
                    fitnessTests: fitnessTests,
                    qualityRecords: qualityRecords,
                    qualityComponents: qualityComponents,
                    qualityEvidence: qualityEvidence,
                    medicalEntries: medicalEntries,
                    medicalPhotos: medicalPhotos
                )
            ),
            timetable: CampusAITimetableContext(
                today: settings.includesTimetable ? todayCourses.prefix(10).map { CampusAICourseContext(course: $0) } : [],
                currentWeek: settings.includesTimetable ? weekCourses.prefix(60).map { CampusAICourseContext(course: $0) } : [],
                allCourses: settings.includesTimetable ? sortedCourses.prefix(160).map { CampusAICourseContext(course: $0) } : [],
                courseNotes: settings.includesTimetable ? courseNotes.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                    CampusAICourseNoteContext(note: $0, courseName: courseNamesByKey[$0.courseKey])
                } : [],
                occurrenceNotes: settings.includesTimetable ? occurrenceNotes.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                    CampusAICourseOccurrenceNoteContext(note: $0, courseName: courseNamesByKey[$0.courseKey])
                } : [],
                courseReminders: settings.includesTimetable ? courseReminders.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                    CampusAICourseReminderContext(reminder: $0, courseName: courseNamesByKey[$0.courseKey])
                } : [],
                cellReminders: settings.includesTimetable ? cellReminders.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map { CampusAITimetableCellReminderContext(reminder: $0) } : [],
                favoriteClassrooms: settings.includesTimetable ? favoriteClassrooms.prefix(20).map(\.displayName) : []
            ),
            exams: settings.includesExamsAndPlans ? Array(sortedExams.prefix(40)).map { CampusAIExamContext(exam: $0) } : [],
            grades: settings.includesGrades ? gradeContext(from: grades, rankings: gradeRankings, creditSummary: gradeCreditSummary) : .empty,
            teachingPlan: settings.includesExamsAndPlans ? teachingPlan.prefix(12).map { CampusAITeachingPlanContext(section: $0) } : [],
            trainingProgram: settings.includesExamsAndPlans ? trainingProgram.map { CampusAITrainingProgramContext(document: $0) } : nil,
            countdowns: settings.includesExamsAndPlans ? countdowns
                .filter { $0.startsAt >= todayStart }
                .sorted { $0.startsAt < $1.startsAt }
                .prefix(30)
                .map { CampusAICountdownContext(countdown: $0) } : [],
            learningWorkspace: settings.includesLearningWorkspace
                ? learningContext(materials: learningMaterials, projects: learningProjects, tasks: learningTasks, studyRecords: studyRecords, now: now)
                : .empty,
            postgraduateAndCareer: settings.includesPostgraduateAndCareer
                ? postgraduateCareerContext(targets: postgraduateTargets, resumes: careerResumes, tasks: careerTasks, opportunities: careerOpportunities)
                : .empty,
            honorsFitnessQuality: settings.includesHonorsFitnessQuality
                ? honorsFitnessQualityContext(honors: honors, fitnessTests: fitnessTests, qualityRecords: qualityRecords, qualityComponents: qualityComponents, qualityEvidence: qualityEvidence)
                : .empty,
            medicalLedger: settings.includesMedicalLedger
                ? medicalLedgerContext(entries: medicalEntries, photoCounts: photoCounts)
                : .empty,
            communityCache: .empty
        )
    }

    @MainActor
    private static func fetch<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func courseSort(_ lhs: Course, _ rhs: Course) -> Bool {
        if lhs.dayOfWeek != rhs.dayOfWeek {
            return lhs.dayOfWeek < rhs.dayOfWeek
        }
        return (lhs.duration.min() ?? 0) < (rhs.duration.min() ?? 0)
    }

    private static func examStartDate(_ exam: ExamArrangement) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(exam.date) \(exam.start)")
    }

    private static func gradeContext(
        from grades: [Grade],
        rankings: [GradeRankingRecord],
        creditSummary: GradeCreditSummary?
    ) -> CampusAIGradeContext {
        let sortedGrades = grades.sorted {
            if $0.term != $1.term {
                return $0.term > $1.term
            }
            return $0.courseName < $1.courseName
        }
        let terms = Set(grades.map(\.term))
        return CampusAIGradeContext(
            courseCount: grades.count,
            termCount: terms.count,
            latestTerm: sortedGrades.first?.term,
            officialGPA: creditSummary?.officialGPA,
            officialWeightedAverage: creditSummary?.officialWeightedAverage,
            totalCredits: creditSummary.flatMap { $0.totalCredits > 0 ? $0.totalCredits : nil },
            requiredCredits: creditSummary.flatMap { $0.requiredCredits > 0 ? $0.requiredCredits : nil },
            publicElectiveCredits: creditSummary.flatMap { $0.publicElectiveCredits > 0 ? $0.publicElectiveCredits : nil },
            professionalElectiveCredits: creditSummary.flatMap { $0.professionalElectiveCredits > 0 ? $0.professionalElectiveCredits : nil },
            recentCourses: sortedGrades.prefix(20).map { CampusAIGradeCourseContext(grade: $0) },
            allCourses: sortedGrades.prefix(160).map { CampusAIGradeCourseContext(grade: $0) },
            rankings: rankings.prefix(20).map { CampusAIGradeRankingContext(ranking: $0) }
        )
    }

    private static func learningContext(
        materials: [LearningMaterialDocument],
        projects: [LearningProject],
        tasks: [LearningProjectTask],
        studyRecords: [StudyTimeRecord],
        now: Date
    ) -> CampusAILearningWorkspaceContext {
        CampusAILearningWorkspaceContext(
            projects: projects.sorted { $0.updatedAt > $1.updatedAt }.prefix(30).map { CampusAILearningProjectContext(project: $0) },
            tasks: tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(60).map { CampusAILearningTaskContext(task: $0) },
            materials: materials.sorted { $0.updatedAt > $1.updatedAt }.prefix(60).map(CampusAIFileMetadataContext.init(material:)),
            studyRecords: studyRecords.sorted { $0.startedAt > $1.startedAt }.prefix(60).map { CampusAIStudyRecordContext(record: $0) }
        )
    }

    private static func postgraduateCareerContext(
        targets: [PostgraduateTarget],
        resumes: [CareerResumeDocument],
        tasks: [CareerTask],
        opportunities: [CareerOpportunity]
    ) -> CampusAIPostgraduateCareerContext {
        CampusAIPostgraduateCareerContext(
            postgraduateTargets: targets.sorted { $0.updatedAt > $1.updatedAt }.prefix(30).map { CampusAIPostgraduateTargetContext(target: $0) },
            resumes: resumes.sorted { $0.updatedAt > $1.updatedAt }.prefix(20).map(CampusAIFileMetadataContext.init(resume:)),
            careerTasks: tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map { CampusAICareerTaskContext(task: $0) },
            opportunities: opportunities.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map { CampusAICareerOpportunityContext(opportunity: $0) }
        )
    }

    private static func honorsFitnessQualityContext(
        honors: [HonorRecord],
        fitnessTests: [FitnessTestRecord],
        qualityRecords: [ComprehensiveQualityRecord],
        qualityComponents: [ComprehensiveQualityComponentEntry],
        qualityEvidence: [ComprehensiveQualityEvidenceDocument]
    ) -> CampusAIHonorsFitnessQualityContext {
        CampusAIHonorsFitnessQualityContext(
            honors: honors.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map(CampusAIFileMetadataContext.init(honor:)),
            fitnessTests: fitnessTests.sorted {
                if $0.testedAt != $1.testedAt {
                    return $0.testedAt > $1.testedAt
                }
                return $0.createdAt > $1.createdAt
            }.prefix(40).map { CampusAIFitnessTestContext(record: $0) },
            comprehensiveQualityRecords: qualityRecords.sorted { $0.updatedAt > $1.updatedAt }.prefix(20).map { CampusAIComprehensiveQualityRecordContext(record: $0) },
            comprehensiveQualityComponents: qualityComponents.sorted { $0.updatedAt > $1.updatedAt }.prefix(60).map { CampusAIComprehensiveQualityComponentContext(component: $0) },
            comprehensiveQualityEvidence: qualityEvidence.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map(CampusAIFileMetadataContext.init(qualityEvidence:))
        )
    }

    private static func medicalLedgerContext(
        entries: [MedicalLedgerEntry],
        photoCounts: [String: Int]
    ) -> CampusAIMedicalLedgerContext {
        CampusAIMedicalLedgerContext(
            entries: entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map {
                CampusAIMedicalLedgerEntryContext(entry: $0, photoCount: photoCounts[$0.id.uuidString] ?? 0)
            },
            photoCount: photoCounts.values.reduce(0, +)
        )
    }

    private static func sourceStatuses(
        settings: CampusAIContextSettings,
        timetableCount: Int,
        timetableLastSyncAt: Date?,
        gradeCount: Int,
        gradeDetailsLastSyncAt: Date?,
        gradeSupplementalCount: Int,
        gradeSupplementalLastSyncAt: Date?,
        examCount: Int,
        examScheduleLastSyncAt: Date?,
        teachingPlanCourseCount: Int,
        teachingPlanLastSyncAt: Date?,
        trainingProgramRequirementCount: Int,
        trainingProgramLastSyncAt: Date?,
        localSavedDataCount: Int
    ) -> [CampusAIContextSourceStatus] {
        [
            sourceStatus(
                scope: "全学期课表",
                isEnabled: settings.includesTimetable,
                itemCount: timetableCount,
                lastSyncAt: timetableLastSyncAt,
                missingNote: "当前设备还没有可用课表缓存；需要连接校园网同步或导入。"
            ),
            sourceStatus(
                scope: "成绩明细",
                isEnabled: settings.includesGrades,
                itemCount: gradeCount,
                lastSyncAt: gradeDetailsLastSyncAt,
                missingNote: "当前设备还没有可用成绩明细缓存；需要连接校园网同步或导入。"
            ),
            sourceStatus(
                scope: "成绩排名和学分汇总",
                isEnabled: settings.includesGrades,
                itemCount: gradeSupplementalCount,
                lastSyncAt: gradeSupplementalLastSyncAt,
                missingNote: "当前设备还没有可用排名或学分汇总缓存，教务系统也可能未开放排名。"
            ),
            sourceStatus(
                scope: "考试安排",
                isEnabled: settings.includesExamsAndPlans,
                itemCount: examCount,
                lastSyncAt: examScheduleLastSyncAt,
                missingNote: "当前设备还没有可用考试安排缓存。"
            ),
            sourceStatus(
                scope: "教学计划",
                isEnabled: settings.includesExamsAndPlans,
                itemCount: teachingPlanCourseCount,
                lastSyncAt: teachingPlanLastSyncAt,
                missingNote: "当前设备还没有可用教学计划缓存。"
            ),
            sourceStatus(
                scope: "培养方案",
                isEnabled: settings.includesExamsAndPlans,
                itemCount: trainingProgramRequirementCount,
                lastSyncAt: trainingProgramLastSyncAt,
                missingNote: "当前设备还没有可用培养方案缓存。"
            ),
            CampusAIContextSourceStatus(
                scope: "本地保存数据",
                itemCount: localSavedDataCount,
                lastSyncAt: nil,
                state: .localOnly,
                note: localSavedDataCount > 0 ? "来自当前设备的备注、提醒、资料元数据和个人台账。" : "当前设备暂未保存本地扩展数据。"
            )
        ]
    }

    private static func sourceStatus(
        scope: String,
        isEnabled: Bool,
        itemCount: Int,
        lastSyncAt: Date?,
        missingNote: String
    ) -> CampusAIContextSourceStatus {
        if !isEnabled {
            return CampusAIContextSourceStatus(
                scope: scope,
                itemCount: 0,
                lastSyncAt: nil,
                state: .disabled,
                note: "用户已在 Leafy AI 设置中关闭此上下文。"
            )
        }

        let syncText = lastSyncAt.map { "最近同步：\(ISO8601DateFormatter().string(from: $0))。" } ?? "暂无同步时间记录。"
        return CampusAIContextSourceStatus(
            scope: scope,
            itemCount: itemCount,
            lastSyncAt: lastSyncAt.map { ISO8601DateFormatter().string(from: $0) },
            state: itemCount > 0 ? .available : .missing,
            note: itemCount > 0 ? syncText : missingNote
        )
    }

    private static func localSavedDataCount(
        settings: CampusAIContextSettings,
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        courseReminders: [CourseReminderSetting],
        cellReminders: [TimetableCellReminder],
        favoriteClassrooms: [FavoriteClassroom],
        countdowns: [CustomScheduleEvent],
        learningMaterials: [LearningMaterialDocument],
        learningProjects: [LearningProject],
        learningTasks: [LearningProjectTask],
        studyRecords: [StudyTimeRecord],
        postgraduateTargets: [PostgraduateTarget],
        careerResumes: [CareerResumeDocument],
        careerTasks: [CareerTask],
        careerOpportunities: [CareerOpportunity],
        honors: [HonorRecord],
        fitnessTests: [FitnessTestRecord],
        qualityRecords: [ComprehensiveQualityRecord],
        qualityComponents: [ComprehensiveQualityComponentEntry],
        qualityEvidence: [ComprehensiveQualityEvidenceDocument],
        medicalEntries: [MedicalLedgerEntry],
        medicalPhotos: [MedicalLedgerPhoto]
    ) -> Int {
        let timetableCount = settings.includesTimetable ? (
            courseNotes.count +
            occurrenceNotes.count +
            courseReminders.count +
            cellReminders.count +
            favoriteClassrooms.count
        ) : 0
        let countdownCount = settings.includesExamsAndPlans ? countdowns.count : 0
        let learningCount = settings.includesLearningWorkspace ? (
            learningMaterials.count +
            learningProjects.count +
            learningTasks.count +
            studyRecords.count
        ) : 0
        let careerCount = settings.includesPostgraduateAndCareer ? (
            postgraduateTargets.count +
            careerResumes.count +
            careerTasks.count +
            careerOpportunities.count
        ) : 0
        let honorsCount = settings.includesHonorsFitnessQuality ? (
            honors.count +
            fitnessTests.count +
            qualityRecords.count +
            qualityComponents.count +
            qualityEvidence.count
        ) : 0
        let medicalCount = settings.includesMedicalLedger ? (
            medicalEntries.count +
            medicalPhotos.count
        ) : 0
        return timetableCount + countdownCount + learningCount + careerCount + honorsCount + medicalCount
    }

    private static func includedScopeNames(_ settings: CampusAIContextSettings) -> [String] {
        scopePairs(settings).compactMap { $0.isIncluded ? $0.name : nil }
    }

    private static func omittedScopeNames(_ settings: CampusAIContextSettings) -> [String] {
        scopePairs(settings).compactMap { $0.isIncluded ? nil : $0.name }
    }

    private static func scopePairs(_ settings: CampusAIContextSettings) -> [(name: String, isIncluded: Bool)] {
        [
            ("课表和提醒", settings.includesTimetable),
            ("成绩和排名", settings.includesGrades),
            ("考试和培养计划", settings.includesExamsAndPlans),
            ("学习空间", settings.includesLearningWorkspace),
            ("考研和职业规划", settings.includesPostgraduateAndCareer),
            ("荣誉体测综测", settings.includesHonorsFitnessQuality),
            ("医疗台账", settings.includesMedicalLedger)
        ]
    }
}

nonisolated extension CampusAICourseContext {
    init(course: Course) {
        self.init(
            name: course.courseName,
            teacher: course.teacher,
            room: course.room,
            location: course.location,
            dayOfWeek: course.dayOfWeek,
            periods: course.duration,
            weeks: course.weeks
        )
    }
}

nonisolated extension CampusAIExamContext {
    init(exam: ExamArrangement) {
        self.init(name: exam.name, date: exam.date, start: exam.start, end: exam.end, location: exam.location)
    }
}

nonisolated extension CampusAIGradeCourseContext {
    init(grade: Grade) {
        self.init(term: grade.term, name: grade.courseName, credit: grade.credit, score: grade.score, type: grade.type)
    }
}

nonisolated extension CampusAIGradeContext {
    static let empty = CampusAIGradeContext(
        courseCount: 0,
        termCount: 0,
        latestTerm: nil,
        officialGPA: nil,
        officialWeightedAverage: nil,
        totalCredits: nil,
        requiredCredits: nil,
        publicElectiveCredits: nil,
        professionalElectiveCredits: nil,
        recentCourses: [],
        allCourses: [],
        rankings: []
    )
}

nonisolated extension CampusAIGradeRankingContext {
    init(ranking: GradeRankingRecord) {
        self.init(
            term: ranking.term,
            range: ranking.rankingRange,
            rank: ranking.rank,
            totalCount: ranking.totalCount,
            percentile: ranking.percentile,
            metric: ranking.metricText
        )
    }
}

nonisolated extension CampusAITeachingPlanContext {
    init(section: TeachingPlanSection) {
        self.init(
            term: section.term,
            totalCredits: section.courses.reduce(0) { $0 + $1.credit },
            courses: section.courses.prefix(24).map { "\($0.name)（\($0.credit) 学分）" }
        )
    }
}

nonisolated extension CampusAITrainingProgramContext {
    init(document: TrainingProgramDocument) {
        self.init(
            title: document.title,
            sections: document.sections.prefix(8).map { "\($0.title)：\($0.body)" },
            creditRequirements: document.creditRequirements.prefix(16).map {
                "\(Self.displayCategory(for: $0)) \($0.courseName) 需 \($0.requiredCredits) 学分"
            }
        )
    }

    private static func displayCategory(for requirement: GraduationCreditRequirement) -> String {
        switch requirement.kind {
        case .total:
            return "总学分"
        case .publicElective:
            return "公选课"
        case .professionalElective:
            return "专选课"
        case .other:
            return requirement.category
        }
    }
}

nonisolated extension CampusAICourseNoteContext {
    init(note: CourseNote, courseName: String?) {
        self.init(
            courseName: courseName ?? "未知课程",
            text: note.text.clampedForAIContext(),
            updatedAt: Self.dateString(note.updatedAt)
        )
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

nonisolated extension CampusAICourseOccurrenceNoteContext {
    init(note: CourseOccurrenceNote, courseName: String?) {
        self.init(
            courseName: courseName ?? "未知课程",
            week: note.week,
            dayOfWeek: note.dayOfWeek,
            text: note.text.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: note.updatedAt)
        )
    }
}

nonisolated extension CampusAICourseReminderContext {
    init(reminder: CourseReminderSetting, courseName: String?) {
        self.init(
            courseName: courseName ?? "未知课程",
            minutesBefore: reminder.minutesBefore,
            anchorPeriod: reminder.anchorPeriod,
            updatedAt: ISO8601DateFormatter().string(from: reminder.updatedAt)
        )
    }
}

nonisolated extension CampusAITimetableCellReminderContext {
    init(reminder: TimetableCellReminder) {
        self.init(
            week: reminder.week,
            dayOfWeek: reminder.dayOfWeek,
            period: reminder.period,
            endPeriod: reminder.endPeriod,
            title: reminder.title.clampedForAIContext(80),
            location: reminder.location?.clampedForAIContext(80),
            note: reminder.note?.clampedForAIContext(),
            minutesBefore: reminder.minutesBefore,
            updatedAt: ISO8601DateFormatter().string(from: reminder.updatedAt)
        )
    }
}

nonisolated extension CampusAICountdownContext {
    init(countdown: CustomScheduleEvent) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        self.init(title: countdown.title, targetDate: formatter.string(from: countdown.startsAt))
    }
}

nonisolated extension CampusAILearningProjectContext {
    init(project: LearningProject) {
        self.init(
            title: project.title.clampedForAIContext(80),
            kind: Self.kindTitle(project.kindRawValue),
            goal: project.goal.clampedForAIContext(),
            isArchived: project.isArchived,
            updatedAt: ISO8601DateFormatter().string(from: project.updatedAt)
        )
    }

    private static func kindTitle(_ rawValue: String) -> String {
        switch rawValue {
        case LearningProjectKind.course.rawValue:
            return "课程"
        case LearningProjectKind.exam.rawValue:
            return "考试"
        case LearningProjectKind.certificate.rawValue:
            return "证书"
        default:
            return "通用"
        }
    }
}

nonisolated extension CampusAILearningTaskContext {
    init(task: LearningProjectTask) {
        self.init(
            title: task.title.clampedForAIContext(80),
            category: task.category.rawValue,
            note: task.note.clampedForAIContext(),
            dueAt: task.dueAt.map { ISO8601DateFormatter().string(from: $0) },
            isCompleted: task.isCompleted,
            updatedAt: ISO8601DateFormatter().string(from: task.updatedAt)
        )
    }
}

nonisolated extension CampusAIFileMetadataContext {
    init(material: LearningMaterialDocument) {
        self.init(
            title: material.title.clampedForAIContext(80),
            note: material.note.clampedForAIContext(),
            category: material.category.rawValue,
            fileType: material.displayType,
            updatedAt: ISO8601DateFormatter().string(from: material.updatedAt)
        )
    }

    init(resume: CareerResumeDocument) {
        self.init(
            title: resume.title.clampedForAIContext(80),
            note: resume.note.clampedForAIContext(),
            category: "简历",
            fileType: LearningMaterialDocument.displayType(
                contentTypeIdentifier: resume.contentTypeIdentifier,
                originalFilename: resume.originalFilename
            ),
            updatedAt: ISO8601DateFormatter().string(from: resume.updatedAt)
        )
    }

    init(honor: HonorRecord) {
        self.init(
            title: honor.title.clampedForAIContext(80),
            note: honor.note.clampedForAIContext(),
            category: "荣誉",
            fileType: LearningMaterialDocument.displayType(
                contentTypeIdentifier: honor.contentTypeIdentifier,
                originalFilename: honor.originalFilename
            ),
            updatedAt: ISO8601DateFormatter().string(from: honor.updatedAt)
        )
    }

    init(qualityEvidence: ComprehensiveQualityEvidenceDocument) {
        self.init(
            title: qualityEvidence.title.clampedForAIContext(80),
            note: qualityEvidence.note.clampedForAIContext(),
            category: qualityEvidence.componentRawValue,
            fileType: LearningMaterialDocument.displayType(
                contentTypeIdentifier: qualityEvidence.contentTypeIdentifier,
                originalFilename: qualityEvidence.originalFilename
            ),
            updatedAt: ISO8601DateFormatter().string(from: qualityEvidence.updatedAt)
        )
    }
}

nonisolated extension CampusAIStudyRecordContext {
    init(record: StudyTimeRecord) {
        self.init(
            content: record.content.clampedForAIContext(100),
            category: record.category.rawValue,
            location: record.location.clampedForAIContext(80),
            note: record.note.clampedForAIContext(),
            startedAt: ISO8601DateFormatter().string(from: record.startedAt),
            minutes: max(Int(record.endedAt.timeIntervalSince(record.startedAt) / 60), 0)
        )
    }
}

nonisolated extension CampusAIPostgraduateTargetContext {
    init(target: PostgraduateTarget) {
        self.init(
            school: target.school.clampedForAIContext(80),
            unit: target.unit.clampedForAIContext(80),
            major: target.major.clampedForAIContext(80),
            direction: target.direction.clampedForAIContext(80),
            examYear: target.examYear,
            subjects: target.subjects.clampedForAIContext(),
            scoreAndPlanNote: target.scoreAndPlanNote.clampedForAIContext(),
            personalNote: target.personalNote.clampedForAIContext(),
            state: target.state.rawValue,
            updatedAt: ISO8601DateFormatter().string(from: target.updatedAt)
        )
    }
}

nonisolated extension CampusAICareerTaskContext {
    init(task: CareerTask) {
        self.init(
            title: task.title.clampedForAIContext(80),
            note: task.note.clampedForAIContext(),
            dueAt: task.dueAt.map { ISO8601DateFormatter().string(from: $0) },
            isCompleted: task.isCompleted,
            updatedAt: ISO8601DateFormatter().string(from: task.updatedAt)
        )
    }
}

nonisolated extension CampusAICareerOpportunityContext {
    init(opportunity: CareerOpportunity) {
        self.init(
            title: opportunity.title.clampedForAIContext(80),
            organization: opportunity.organization.clampedForAIContext(80),
            status: opportunity.statusRawValue,
            note: opportunity.note.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: opportunity.updatedAt)
        )
    }
}

nonisolated extension CampusAIFitnessTestContext {
    init(record: FitnessTestRecord) {
        self.init(
            item: record.item.rawValue,
            value: record.displayValue,
            note: record.note.clampedForAIContext(),
            testedAt: ISO8601DateFormatter().string(from: record.testedAt)
        )
    }
}

nonisolated extension CampusAIComprehensiveQualityRecordContext {
    init(record: ComprehensiveQualityRecord) {
        self.init(
            collegeName: record.collegeName.clampedForAIContext(80),
            cohort: record.cohort,
            academicStandardScore: record.academicStandardScore,
            officialQualityScore: record.officialQualityScore,
            officialCompositeScore: record.officialCompositeScore,
            note: record.note.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: record.updatedAt)
        )
    }
}

nonisolated extension CampusAIComprehensiveQualityComponentContext {
    init(component: ComprehensiveQualityComponentEntry) {
        self.init(
            collegeName: component.collegeName.clampedForAIContext(80),
            cohort: component.cohort,
            component: component.componentRawValue,
            rawScore: component.rawScore,
            peerMaxScore: component.peerMaxScore,
            officialStandardScore: component.officialStandardScore,
            materialReady: component.materialReady,
            note: component.note.clampedForAIContext(),
            updatedAt: ISO8601DateFormatter().string(from: component.updatedAt)
        )
    }
}

nonisolated extension CampusAIMedicalLedgerEntryContext {
    init(entry: MedicalLedgerEntry, photoCount: Int) {
        self.init(
            visitDate: ISO8601DateFormatter().string(from: entry.visitDate),
            hospitalName: entry.hospitalName.clampedForAIContext(80),
            department: entry.department.clampedForAIContext(80),
            diagnosisNote: entry.diagnosisNote.clampedForAIContext(),
            scenario: entry.scenario.rawValue,
            totalExpense: entry.totalExpense,
            estimatedReimbursement: entry.estimatedOrCalculatedReimbursement,
            actualReimbursement: entry.actualReimbursement,
            status: entry.status.rawValue,
            reimbursementDeadline: entry.reimbursementDeadline.map { ISO8601DateFormatter().string(from: $0) },
            materials: entry.materials.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue),
            note: entry.note.clampedForAIContext(),
            photoCount: photoCount,
            updatedAt: ISO8601DateFormatter().string(from: entry.updatedAt)
        )
    }
}

nonisolated extension CampusAICommunityPostContext {
    init(post: CommunityPost) {
        self.init(
            title: post.title.clampedForAIContext(80),
            body: post.body.clampedForAIContext(180),
            category: post.category,
            commentCount: post.commentCount,
            likeCount: post.likeCount,
            imageCount: post.images.count,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt
        )
    }
}
import Foundation
import SwiftData
