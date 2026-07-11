import SwiftData
import WebKit
import XCTest
@testable import Leafy

final class CampusAIAssistantTests: XCTestCase {
    func testSettingsStoreDefaultsToAllContextScopesAndCustomPrompt() throws {
        let suiteName = "CampusAIAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = CampusAISettingsStore.load(userDefaults: defaults)
        XCTAssertEqual(initial.selectedProviderID, .deepSeek)
        XCTAssertEqual(initial.selectedProvider, CampusAIProviderCatalog.deepSeek)
        XCTAssertEqual(initial.serviceMode, .ownAPIKey)
        XCTAssertEqual(initial.systemPrompt, CampusAISettingsStore.defaultSystemPrompt)
        XCTAssertTrue(initial.contextSettings.includesTimetable)
        XCTAssertTrue(initial.contextSettings.includesMedicalLedger)
        XCTAssertTrue(initial.contextSettings.includesCommunityCache)
        XCTAssertFalse(initial.webSearchEnabled)

        var changed = initial
        changed.systemPrompt = "请优先用列表回答"
        changed.contextSettings.includesMedicalLedger = false
        changed.webSearchEnabled = true
        CampusAISettingsStore.save(changed, userDefaults: defaults)

        let reloaded = CampusAISettingsStore.load(userDefaults: defaults)
        XCTAssertEqual(reloaded.systemPrompt, "请优先用列表回答")
        XCTAssertFalse(reloaded.contextSettings.includesMedicalLedger)
        XCTAssertFalse(reloaded.webSearchEnabled)
        XCTAssertEqual(reloaded.serviceMode, .ownAPIKey)

        let reset = CampusAISettingsStore.reset(userDefaults: defaults)
        XCTAssertEqual(reset, .defaultValue)
    }

    func testProviderCatalogDefaultsToDeepSeekV4Flash() {
        XCTAssertEqual(CampusAIProviderCatalog.all, [.init(
            id: .deepSeek,
            displayName: "DeepSeek",
            modelIdentifier: "deepseek-v4-flash",
            modelDisplayName: "DeepSeek V4 Flash",
            baseURLString: "https://api.deepseek.com"
        )])
        XCTAssertEqual(CampusAIProviderCatalog.defaultProvider, CampusAIProviderCatalog.deepSeek)
    }

    func testSettingsStoreMigratesLegacyPromptAndContextOnly() throws {
        let suiteName = "CampusAIAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyJSON = """
        {
          "systemPrompt": "旧版 Prompt",
          "baseURLString": "https://legacy.example.com/v1",
          "contextSettings": {
            "includesTimetable": true,
            "includesGrades": true,
            "includesExamsAndPlans": true,
            "includesLearningWorkspace": true,
            "includesPostgraduateAndCareer": true,
            "includesHonorsFitnessQuality": true,
            "includesMedicalLedger": false,
            "includesCommunityCache": true
          }
        }
        """
        defaults.set(Data(legacyJSON.utf8), forKey: "campusAI.userSettings.v1")

        let settings = CampusAISettingsStore.load(userDefaults: defaults)
        XCTAssertEqual(settings.selectedProviderID, .deepSeek)
        XCTAssertEqual(settings.serviceMode, .ownAPIKey)
        XCTAssertEqual(settings.systemPrompt, "旧版 Prompt")
        XCTAssertFalse(settings.contextSettings.includesMedicalLedger)
        XCTAssertFalse(settings.webSearchEnabled)
        XCTAssertNil(defaults.data(forKey: "campusAI.userSettings.v1"))
        XCTAssertNotNil(defaults.data(forKey: "campusAI.userSettings.v2"))
    }

    func testLegacyKeychainAccountsAreRemovedOnce() throws {
        let suiteName = "CampusAIAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var deletedAccounts: [String] = []

        try CampusAIKeychainStore.removeLegacyKeysIfNeeded(userDefaults: defaults) { account in
            deletedAccounts.append(account)
            return 0
        }

        XCTAssertEqual(Set(deletedAccounts), Set(CampusAIKeychainStore.legacyAccounts))

        deletedAccounts.removeAll()
        try CampusAIKeychainStore.removeLegacyKeysIfNeeded(userDefaults: defaults) { account in
            deletedAccounts.append(account)
            return 0
        }
        XCTAssertTrue(deletedAccounts.isEmpty)
    }

    func testExperimentalNoticeAcknowledgementUsesIndependentStorageKey() throws {
        let suiteName = "CampusAIAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "campusAI.experimentalNoticeAcknowledged.v1"
        XCTAssertNil(defaults.object(forKey: key))

        defaults.set(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key))

        let settings = CampusAISettingsStore.load(userDefaults: defaults)
        XCTAssertEqual(settings, .defaultValue)
        XCTAssertTrue(defaults.bool(forKey: key))
    }

    func testContextBuilderIncludesBroadLocalContextAndKeepsUploadedFileBodiesOut() throws {
        let now = SemesterConfig.startOfSemesterDate.addingTimeInterval(10 * 60 * 60)
        let schedule = SemesterConfig.weekAndDay(for: now)
        let course = Course(
            courseName: "数据结构",
            teacher: "王老师",
            room: "二教 205",
            location: "教学楼",
            dayOfWeek: schedule.day,
            weeks: [schedule.week],
            duration: [1, 2]
        )
        let nextWeekCourse = Course(
            courseName: "大学物理",
            teacher: "李老师",
            room: "三教 101",
            location: "教学楼",
            dayOfWeek: 5,
            weeks: [schedule.week + 1],
            duration: [3, 4]
        )
        let grade = Grade(term: "2025-2026-1", courseName: "高等数学", credit: "4", score: "92", type: "必修")
        let examDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 3, to: now))
        let exam = ExamArrangement(
            id: 1,
            courseID: "math",
            name: "高等数学期末",
            date: DateFormatters.queryDate.string(from: examDate),
            start: "09:00",
            end: "11:00",
            location: "主楼 112"
        )
        let teachingPlan = TeachingPlanSection(
            term: "第1学期",
            courses: [
                TeachingPlanCourse(
                    id: 1,
                    period: "1",
                    name: "大学英语",
                    unit: "外语学院",
                    credit: 2,
                    duration: "32",
                    type: "必修",
                    exam: "考试"
                )
            ]
        )
        let trainingProgram = TrainingProgramDocument(
            title: "本科培养方案",
            sections: [TrainingProgramSection(id: "intro", title: "培养目标", body: "掌握专业基础。")],
            creditRequirements: [
                GraduationCreditRequirement(
                    id: "public",
                    category: "公共选修",
                    courseName: "公共选修课",
                    requiredCredits: 8,
                    plannedCredits: 8,
                    isAggregate: true
                )
            ]
        )
        let countdown = CustomCountdownEvent(
            title: "四六级报名",
            targetDate: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: now))
        )
        let material = LearningMaterialDocument(
            title: "数据结构复习资料",
            note: "只发送这条用户备注",
            categoryRawValue: LearningMaterialCategory.exam.rawValue,
            courseName: "数据结构",
            originalFilename: "do-not-send-file-name.pdf",
            localFilename: "private-local-path.pdf",
            contentTypeIdentifier: "com.adobe.pdf"
        )
        let medicalEntry = MedicalLedgerEntry(
            hospitalName: "北医三院",
            department: "皮肤科",
            diagnosisNote: "敏感诊断",
            totalExpense: 120,
            statusRawValue: MedicalLedgerStatus.organizing.rawValue
        )

        let context = CampusAIContextBuilder.build(
            courses: [course, nextWeekCourse],
            courseNotes: [CourseNote(courseKey: course.stableCourseKey, text: "实验报告要提前写。")],
            grades: [grade],
            gradeRankings: [
                GradeRankingRecord(
                    term: "全部学期",
                    rankingRange: "专业",
                    rank: 12,
                    totalCount: 120,
                    percentile: 0.1,
                    metricText: "GPA",
                    rawFields: [:]
                )
            ],
            exams: [exam],
            teachingPlan: [teachingPlan],
            trainingProgram: trainingProgram,
            gradeCreditSummary: GradeCreditSummary(
                totalCredits: 32,
                requiredCredits: 160,
                professionalElectiveCredits: 4,
                professionalMajorElectiveCredits: 4,
                professionalCrossMajorElectiveCredits: 0,
                publicElectiveCredits: 2,
                officialGPA: 3.8,
                officialWeightedAverage: 91,
                officialCreditPoint: nil,
                publicElectiveBuckets: [],
                rawFields: [:]
            ),
            countdowns: [countdown],
            learningMaterials: [material],
            learningProjects: [LearningProject(title: "期末复习", goal: "两周内完成知识点梳理")],
            learningTasks: [LearningProjectTask(title: "刷树题", note: "每天 3 道")],
            studyRecords: [
                StudyTimeRecord(
                    startedAt: now,
                    endedAt: now.addingTimeInterval(45 * 60),
                    content: "复习链表",
                    location: "图书馆"
                )
            ],
            postgraduateTargets: [PostgraduateTarget(school: "北京林业大学", major: "计算机技术")],
            careerResumes: [
                CareerResumeDocument(
                    title: "产品实习简历",
                    note: "需要突出校园项目",
                    originalFilename: "resume-private.pdf",
                    localFilename: "resume-local.pdf",
                    contentTypeIdentifier: "com.adobe.pdf"
                )
            ],
            careerTasks: [CareerTask(title: "投递暑期实习", note: "先改作品集")],
            careerOpportunities: [CareerOpportunity(title: "AI 产品实习", organization: "Example")],
            honors: [
                HonorRecord(
                    title: "三好学生",
                    originalFilename: "honor-private.pdf",
                    localFilename: "honor-local.pdf",
                    contentTypeIdentifier: "com.adobe.pdf"
                )
            ],
            fitnessTests: [FitnessTestRecord(itemRawValue: FitnessTestItem.sprint50m.rawValue, value: 7.2, unitRawValue: FitnessTestUnit.second.rawValue)],
            qualityRecords: [ComprehensiveQualityRecord(collegeName: "信息学院", academicStandardScore: 90)],
            qualityComponents: [ComprehensiveQualityComponentEntry(collegeName: "信息学院", componentRawValue: "德育", rawScore: 10)],
            qualityEvidence: [
                ComprehensiveQualityEvidenceDocument(
                    collegeName: "信息学院",
                    componentRawValue: "德育",
                    title: "志愿证明",
                    originalFilename: "quality-private.pdf",
                    localFilename: "quality-local.pdf",
                    contentTypeIdentifier: "com.adobe.pdf"
                )
            ],
            medicalEntries: [medicalEntry],
            medicalPhotos: [MedicalLedgerPhoto(entryID: medicalEntry.id.uuidString, originalFilename: "invoice.jpg", localFilename: "invoice-local.jpg")],
            communityPosts: [
                CommunityPost(
                    id: UUID(),
                    authorID: UUID(),
                    title: "校园 App 比赛规划",
                    body: "公开帖子摘要",
                    category: "校园",
                    isAnonymous: true,
                    commentCount: 2,
                    likeCount: 3,
                    status: "published",
                    createdAt: "2026-06-25T00:00:00Z",
                    updatedAt: "2026-06-25T00:00:00Z",
                    viewerHasLiked: false,
                    author: nil,
                    images: []
                )
            ],
            now: now
        )

        XCTAssertTrue(context.hasReadableAcademicData)
        XCTAssertEqual(context.timetable.today.map { $0.name }, ["数据结构"])
        XCTAssertTrue(context.timetable.allCourses.map { $0.name }.contains("大学物理"))
        XCTAssertTrue(context.dataBoundary.contains { $0.contains("timetable.allCourses 是当前设备已缓存的全学期课程集合") })
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "全学期课表" }?.itemCount, 2)
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "本地保存数据" }?.state, .localOnly)
        XCTAssertEqual(context.timetable.courseNotes.first?.text, "实验报告要提前写。")
        XCTAssertEqual(context.exams.map { $0.name }, ["高等数学期末"])
        XCTAssertEqual(context.grades.courseCount, 1)
        XCTAssertEqual(context.grades.rankings.first?.rank, 12)
        XCTAssertEqual(context.teachingPlan.first?.courses, ["大学英语（2.0 学分）"])
        XCTAssertEqual(context.trainingProgram?.title, "本科培养方案")
        XCTAssertEqual(context.countdowns.map { $0.title }, ["四六级报名"])
        XCTAssertEqual(context.learningWorkspace.materials.first?.title, "数据结构复习资料")
        XCTAssertEqual(context.medicalLedger.photoCount, 1)
        XCTAssertEqual(context.communityCache.posts.first?.title, "校园 App 比赛规划")

        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(context), encoding: .utf8))
        XCTAssertTrue(encoded.contains("只发送这条用户备注"))
        XCTAssertTrue(encoded.contains("PDF"))
        XCTAssertFalse(encoded.contains("private-local-path.pdf"))
        XCTAssertFalse(encoded.contains("do-not-send-file-name.pdf"))
        XCTAssertFalse(encoded.contains("invoice-local.jpg"))
        XCTAssertFalse(encoded.contains("resume-local.pdf"))
    }

    func testContextBuilderReportsSourceStatusFreshnessAndMissingData() throws {
        let now = SemesterConfig.startOfSemesterDate.addingTimeInterval(10 * 60 * 60)
        let syncDate = Date(timeIntervalSince1970: 1_234_567)
        let syncString = ISO8601DateFormatter().string(from: syncDate)
        let course = Course(
            courseName: "大学英语",
            teacher: "张老师",
            room: "一教 101",
            location: "教学楼",
            dayOfWeek: 1,
            weeks: [1, 2, 3],
            duration: [1, 2]
        )
        let grade = Grade(term: "2025-2026-1", courseName: "大学英语", credit: "2", score: "88", type: "必修")
        let exam = ExamArrangement(
            id: 1,
            courseID: "eng",
            name: "大学英语期末",
            date: DateFormatters.queryDate.string(from: now.addingTimeInterval(86_400)),
            start: "09:00",
            end: "11:00",
            location: "一教 101"
        )
        let teachingPlan = TeachingPlanSection(
            term: "第1学期",
            courses: [
                TeachingPlanCourse(id: 1, period: "1", name: "大学英语", unit: "外语学院", credit: 2, duration: "32", type: "必修", exam: "考试")
            ]
        )
        let trainingProgram = TrainingProgramDocument(
            title: "培养方案",
            sections: [TrainingProgramSection(id: "goal", title: "培养目标", body: "测试")],
            creditRequirements: [
                GraduationCreditRequirement(id: "total", category: "总学分", courseName: "毕业要求", requiredCredits: 160, plannedCredits: 160, isAggregate: true)
            ]
        )

        let context = CampusAIContextBuilder.build(
            courses: [course],
            grades: [grade],
            gradeRankings: [
                GradeRankingRecord(term: "全部学期", rankingRange: "专业", rank: 1, totalCount: 30, percentile: 0.03, metricText: "GPA", rawFields: [:])
            ],
            exams: [exam],
            teachingPlan: [teachingPlan],
            trainingProgram: trainingProgram,
            gradeCreditSummary: GradeCreditSummary(
                totalCredits: 20,
                requiredCredits: 160,
                professionalElectiveCredits: 0,
                professionalMajorElectiveCredits: 0,
                professionalCrossMajorElectiveCredits: 0,
                publicElectiveCredits: 2,
                officialGPA: 3.6,
                officialWeightedAverage: 88,
                officialCreditPoint: nil,
                publicElectiveBuckets: [],
                rawFields: [:]
            ),
            countdowns: [],
            timetableLastSyncAt: syncDate,
            gradeDetailsLastSyncAt: syncDate,
            gradeSupplementalLastSyncAt: syncDate,
            examScheduleLastSyncAt: syncDate,
            teachingPlanLastSyncAt: syncDate,
            trainingProgramLastSyncAt: syncDate,
            now: now
        )

        XCTAssertEqual(context.sourceStatus.first { $0.scope == "全学期课表" }?.state, .available)
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "全学期课表" }?.lastSyncAt, syncString)
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "成绩明细" }?.itemCount, 1)
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "成绩排名和学分汇总" }?.itemCount, 2)
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "考试安排" }?.state, .available)
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "教学计划" }?.itemCount, 1)
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "培养方案" }?.itemCount, 1)

        let missingContext = CampusAIContextBuilder.build(
            courses: [],
            grades: [],
            exams: [],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            now: now
        )
        XCTAssertEqual(missingContext.sourceStatus.first { $0.scope == "全学期课表" }?.state, .missing)
        XCTAssertEqual(missingContext.sourceStatus.first { $0.scope == "成绩明细" }?.state, .missing)
        XCTAssertEqual(missingContext.sourceStatus.first { $0.scope == "本地保存数据" }?.state, .localOnly)
    }

    func testContextBuilderToleratesDuplicateStableCourseKeys() {
        let firstCourse = Course(
            courseName: "数据结构",
            teacher: "王老师",
            room: "二教 205",
            location: "教学楼",
            dayOfWeek: 2,
            weeks: [1],
            duration: [1, 2]
        )
        let duplicateCourse = Course(
            courseName: "数据结构",
            teacher: "王老师",
            room: "二教 205",
            location: "教学楼",
            dayOfWeek: 2,
            weeks: [2],
            duration: [1, 2]
        )
        XCTAssertEqual(firstCourse.stableCourseKey, duplicateCourse.stableCourseKey)

        let context = CampusAIContextBuilder.build(
            courses: [firstCourse, duplicateCourse],
            courseNotes: [
                CourseNote(courseKey: firstCourse.stableCourseKey, text: "记得复习链表")
            ],
            grades: [],
            exams: [],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            now: SemesterConfig.startOfSemesterDate
        )

        XCTAssertEqual(context.timetable.allCourses.count, 2)
        XCTAssertEqual(context.timetable.courseNotes.first?.courseName, "数据结构")
    }

    func testContextSettingsCanDisableSensitiveScopes() throws {
        var settings = CampusAIContextSettings.defaultValue
        settings.includesMedicalLedger = false
        settings.includesLearningWorkspace = false

        let context = CampusAIContextBuilder.build(
            courses: [],
            grades: [],
            exams: [],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            learningMaterials: [
                LearningMaterialDocument(
                    title: "关闭后不应出现",
                    originalFilename: "source.pdf",
                    localFilename: "local.pdf",
                    contentTypeIdentifier: "com.adobe.pdf"
                )
            ],
            medicalEntries: [MedicalLedgerEntry(hospitalName: "关闭后不应出现")],
            settings: settings
        )

        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(context), encoding: .utf8))
        XCTAssertTrue(context.omittedScopes.contains("学习空间"))
        XCTAssertTrue(context.omittedScopes.contains("医疗台账"))
        XCTAssertEqual(context.sourceStatus.first { $0.scope == "本地保存数据" }?.itemCount, 0)
        XCTAssertFalse(encoded.contains("关闭后不应出现"))
    }

    func testChatCompletionsRequestBuilderUsesOpenAICompatiblePayload() throws {
        let request = CampusAIRequest(
            message: "明天上什么课？",
            context: minimalAIContext(),
            recentMessages: [CampusAIChatMessage(role: .assistant, text: "你好")],
            userSystemPrompt: "请用列表回答"
        )

        let urlRequest = try CampusAIService.makeChatCompletionsRequest(
            for: request,
            baseURLString: CampusAIProviderCatalog.deepSeek.baseURLString,
            apiKey: "test-api-key"
        )
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let bodyData = try XCTUnwrap(urlRequest.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, CampusAIProviderCatalog.deepSeek.modelIdentifier)
        XCTAssertEqual(body["stream"] as? Bool, true)
        let streamOptions = try XCTUnwrap(body["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        XCTAssertNil(body["max_tokens"])
        let temperature = (body["temperature"] as? NSNumber)?.doubleValue ?? -1
        XCTAssertEqual(temperature, 0.2, accuracy: 0.001)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertTrue(String(describing: messages.first?["content"] ?? "").contains("中文 Markdown"))
        XCTAssertTrue(String(describing: messages.first?["content"] ?? "").contains("请用列表回答"))

        let userContentText = try XCTUnwrap(messages.last?["content"] as? String)
        let userContentData = Data(userContentText.utf8)
        let userContent = try XCTUnwrap(JSONSerialization.jsonObject(with: userContentData) as? [String: Any])
        XCTAssertEqual(userContent["message"] as? String, "明天上什么课？")
        XCTAssertNotNil(userContent["context"])
        XCTAssertNotNil(userContent["context_settings"])
        XCTAssertNotNil(userContent["capabilities"])
        XCTAssertNotNil(userContent["local_retrieval"])
        let recentMessages = try XCTUnwrap(userContent["recent_messages"] as? [[String: Any]])
        XCTAssertEqual(recentMessages.first?["role"] as? String, "assistant")
        XCTAssertEqual(recentMessages.first?["text"] as? String, "你好")
    }

    func testChatCompletionsPayloadIncludesLocalRetrievalAndCapabilities() throws {
        let context = CampusAIContextBuilder.build(
            courses: [],
            grades: [],
            exams: [],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            learningTasks: [
                LearningProjectTask(title: "整理论文提纲", note: "周五前完成")
            ]
        )
        let retrieval = CampusAILocalKnowledgeIndex.search(query: "导出学习任务资料包", context: context)
        let request = CampusAIRequest(
            message: "导出学习任务资料包",
            context: context,
            recentMessages: [],
            capabilities: CampusAICapabilitySet(serviceMode: .ownAPIKey, webSearchEnabled: true),
            localRetrieval: retrieval
        )

        let payload = try CampusAIService.chatCompletionsPayload(for: request)
        let userContentText = try XCTUnwrap(payload.messages.last?.content)
        let userContent = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(userContentText.utf8)) as? [String: Any])
        let capabilities = try XCTUnwrap(userContent["capabilities"] as? [String: Any])
        let localRetrieval = try XCTUnwrap(userContent["local_retrieval"] as? [String: Any])
        let results = try XCTUnwrap(localRetrieval["results"] as? [[String: Any]])

        XCTAssertEqual(capabilities["localSearchEnabled"] as? Bool, true)
        XCTAssertEqual(capabilities["artifactGenerationEnabled"] as? Bool, true)
        XCTAssertEqual(capabilities["webSearchEnabled"] as? Bool, false)
        XCTAssertTrue(results.contains { String(describing: $0["title"] ?? "").contains("整理论文提纲") })
        XCTAssertFalse(userContentText.contains("localFilename"))
        XCTAssertFalse(userContentText.contains("private-local-path"))
    }

    func testChatCompletionsPayloadUsesRequestModelIdentifier() throws {
        let request = CampusAIRequest(
            message: "总结一下最近安排",
            context: minimalAIContext(),
            recentMessages: [],
            model: "custom-model-id"
        )

        let payload = try CampusAIService.chatCompletionsPayload(for: request)

        XCTAssertEqual(payload.model, "custom-model-id")
    }

    func testCampusAIRequestDefaultsWebSearchOff() {
        let request = CampusAIRequest(
            message: "查一下论文格式",
            context: minimalAIContext(),
            recentMessages: []
        )

        XCTAssertFalse(request.webSearchEnabled)
        XCTAssertEqual(request.agentMode, .auto)
    }

    func testArtifactFormatResolverDefaultsToHTMLAndHonorsExplicitFormats() {
        XCTAssertEqual(CampusAIArtifactFormatResolver.formats(for: "整理成资料包"), [.html])
        XCTAssertEqual(CampusAIArtifactFormatResolver.formats(for: "生成 Markdown 文档"), [.markdown])
        XCTAssertEqual(CampusAIArtifactFormatResolver.formats(for: "导出 TXT 文本"), [.txt])
        XCTAssertEqual(CampusAIArtifactFormatResolver.formats(for: "生成 HTML Markdown TXT"), [.html, .markdown, .txt])
    }

    func testDeliverableDecodesArtifactContentAndLegacyPayload() throws {
        let legacy = try JSONDecoder().decode(
            CampusAIDeliverable.self,
            from: Data(
                """
                {
                  "id":"legacy-pack",
                  "title":"旧资料包",
                  "query":"论文格式",
                  "summary":"已整理。",
                  "generated_at":"2026-07-02T00:00:00Z",
                  "sources":[],
                  "formats":["html"]
                }
                """.utf8
            )
        )
        XCTAssertNil(legacy.content)
        XCTAssertEqual(legacy.formats, [.html])

        let artifact = try JSONDecoder().decode(
            CampusAIDeliverable.self,
            from: Data(
                """
                {
                  "id":"artifact-pack",
                  "title":"可预览 Artifact",
                  "query":"生成网页",
                  "summary":"已生成。",
                  "generated_at":"2026-07-02T00:00:00Z",
                  "sources":[],
                  "content":{
                    "html":"<main><h1>Leafy</h1></main>",
                    "markdown":"# Leafy",
                    "text":"Leafy"
                  }
                }
                """.utf8
            )
        )
        XCTAssertEqual(artifact.content?.html, "<main><h1>Leafy</h1></main>")
        XCTAssertEqual(artifact.content?.markdown, "# Leafy")
        XCTAssertEqual(artifact.content?.text, "Leafy")
        XCTAssertEqual(artifact.formats, [.html, .markdown, .txt])
    }

    func testCampusAICapabilitySetSeparatesWebFromAgent() {
        let ownKey = CampusAICapabilitySet(serviceMode: .ownAPIKey, webSearchEnabled: true)
        XCTAssertTrue(ownKey.nonWebAgentEnabled)
        XCTAssertTrue(ownKey.localSearchEnabled)
        XCTAssertTrue(ownKey.actionPlanningEnabled)
        XCTAssertTrue(ownKey.artifactGenerationEnabled)
        XCTAssertFalse(ownKey.webSearchEnabled)
        XCTAssertFalse(ownKey.officialDocumentSearchEnabled)

        let managedOff = CampusAICapabilitySet(serviceMode: .leafyManaged, webSearchEnabled: false)
        XCTAssertTrue(managedOff.nonWebAgentEnabled)
        XCTAssertTrue(managedOff.localSearchEnabled)
        XCTAssertFalse(managedOff.webSearchEnabled)
        XCTAssertFalse(managedOff.officialDocumentSearchEnabled)

        let managedOn = CampusAICapabilitySet(serviceMode: .leafyManaged, webSearchEnabled: true)
        XCTAssertTrue(managedOn.webSearchEnabled)
        XCTAssertTrue(managedOn.officialDocumentSearchEnabled)
    }

    func testToolRegistryExposesBuiltInToolsAndSupportedActions() {
        let ids = Set(CampusAIToolRegistry.all.map(\.id))

        XCTAssertTrue(ids.contains("web.search"))
        XCTAssertTrue(ids.contains("local.retrieval"))
        XCTAssertTrue(ids.contains("action.plan"))
        XCTAssertEqual(CampusAIToolRegistry.descriptor(for: .createCountdown)?.title, "创建重要日期")
        XCTAssertEqual(CampusAIToolRegistry.descriptor(forToolName: "web.search")?.systemImageName, "network")

        let supportedActions = CampusAIToolRegistry.supportedActions()
        XCTAssertEqual(supportedActions.count, 3)
        XCTAssertTrue(supportedActions.contains { action in
            action.kind == CampusAIActionKind.openAcademicRoute.rawValue &&
                (action.allowedValues["route"] ?? []).contains("examSchedule")
        })
        XCTAssertTrue(supportedActions.contains { action in
            action.kind == CampusAIActionKind.createTimetableReminder.rawValue &&
                (action.allowedValues["period"] ?? []).contains("1")
        })
    }

    func testLocalKnowledgeIndexFindsLearningAndExamResultsWithinBudget() throws {
        let now = SemesterConfig.startOfSemesterDate.addingTimeInterval(86_400)
        let exam = ExamArrangement(
            id: 1,
            courseID: "math",
            name: "高等数学期末",
            date: DateFormatters.queryDate.string(from: now.addingTimeInterval(86_400 * 3)),
            start: "09:00",
            end: "11:00",
            location: "主楼 112"
        )
        let context = CampusAIContextBuilder.build(
            courses: [],
            grades: [],
            exams: [exam],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            learningTasks: [
                LearningProjectTask(title: "刷树题", note: "每天 3 道，优先二叉树")
            ],
            now: now
        )

        let retrieval = CampusAILocalKnowledgeIndex.search(
            query: "我最近有哪些学习任务和考试要安排",
            context: context,
            maxResults: 12,
            characterBudget: 320
        )

        XCTAssertFalse(retrieval.results.isEmpty)
        XCTAssertTrue(retrieval.results.contains { $0.domain == .learning && $0.title.contains("刷树题") })
        XCTAssertTrue(retrieval.results.contains { $0.domain == .schedule && $0.title.contains("高等数学期末") })
        XCTAssertLessThanOrEqual(retrieval.results.reduce(0) { $0 + $1.title.count + $1.summary.count }, 320)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(retrieval), encoding: .utf8))
        XCTAssertTrue(encoded.contains("sourceID"))
        XCTAssertTrue(encoded.contains("routeHint"))
        XCTAssertFalse(encoded.contains("localFilename"))
        XCTAssertFalse(encoded.contains("private-local-path"))
    }

    func testCampusAIServiceKeepsAgentAutoWhenWebSearchIsDisabled() async throws {
        let service = CampusAIService { request, _ in
            AsyncThrowingStream { continuation in
                XCTAssertFalse(request.webSearchEnabled)
                XCTAssertEqual(request.agentMode, .auto)
                XCTAssertTrue(request.capabilities.nonWebAgentEnabled)
                XCTAssertTrue(request.capabilities.localSearchEnabled)
                XCTAssertFalse(request.capabilities.webSearchEnabled)
                continuation.yield(.done(CampusAIResponse(answer: "已安排。")))
                continuation.finish()
            }
        }
        var settings = CampusAIUserSettings.defaultValue
        settings.webSearchEnabled = false

        _ = try await service.send(
            message: "帮我安排今天的日常",
            context: minimalAIContext(),
            recentMessages: [],
            settings: settings
        )
    }

    func testDirectAgentRunsForOwnKeyPlanningIntentsWithoutWebSearch() {
        let planningRequest = CampusAIRequest(
            message: "帮我安排今天的日常计划",
            context: minimalAIContext(),
            recentMessages: [],
            webSearchEnabled: false
        )
        let searchRequest = CampusAIRequest(
            message: "查一下北京林业大学论文格式官方网页",
            context: minimalAIContext(),
            recentMessages: [],
            webSearchEnabled: false
        )
        let disabledRequest = CampusAIRequest(
            message: "帮我安排今天的日常计划",
            context: minimalAIContext(),
            recentMessages: [],
            agentMode: .off,
            webSearchEnabled: false
        )

        XCTAssertTrue(CampusAIService.shouldRunDirectAgent(planningRequest))
        XCTAssertFalse(CampusAIService.shouldRunDirectAgent(searchRequest))
        XCTAssertFalse(CampusAIService.shouldRunDirectAgent(disabledRequest))
    }

    func testActionPlannerFallbackCreatesScheduleRouteCard() {
        let request = CampusAIRequest(
            message: "我要新建一个日程",
            context: minimalAIContext(),
            recentMessages: [],
            webSearchEnabled: false
        )

        let actions = CampusAIService.fallbackActionDrafts(
            for: request,
            answer: "可以去日程页面添加。"
        )

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, .openAcademicRoute)
        XCTAssertEqual(actions.first?.payload.route, "customCountdowns")
        XCTAssertEqual(actions.first?.title, "打开自定日程")
        XCTAssertEqual(actions.first?.detail, "前往自定日程继续创建或管理日程。")
    }

    func testActionPlannerFallbackRoutesExamRequestsToExamSchedule() {
        let request = CampusAIRequest(
            message: "帮我查看考试时间",
            context: minimalAIContext(),
            recentMessages: [],
            webSearchEnabled: false
        )

        let actions = CampusAIService.fallbackActionDrafts(
            for: request,
            answer: "可以去考试安排页面查看。"
        )

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, .openAcademicRoute)
        XCTAssertEqual(actions.first?.payload.route, "examSchedule")
        XCTAssertEqual(actions.first?.title, "打开考试安排")
        XCTAssertEqual(actions.first?.detail, "前往考试安排继续查看或管理考试。")
        XCTAssertEqual(CampusAIAcademicRouteID.examSchedule.title, "考试安排")
    }

    func testAPIKeyResolverUsesSelectedProviderKey() throws {
        let resolver = CampusAIAPIKeyResolver(
            userAPIKey: { providerID in providerID == .deepSeek ? "user-key" : nil }
        )
        let resolved = try resolver.resolve(for: .defaultValue)

        XCTAssertEqual(resolved, "user-key")
    }

    func testAPIKeyResolverRequiresLocalProviderKey() {
        let resolver = CampusAIAPIKeyResolver(userAPIKey: { _ in nil })

        XCTAssertThrowsError(try resolver.resolve(for: .defaultValue)) { error in
            XCTAssertEqual(error as? CampusAIServiceError, .missingAPIKey)
        }
    }

    func testSystemPromptIsBroaderButKeepsBoundaries() {
        let prompt = CampusAIService.systemPrompt(userPrompt: "请顺便给生活建议")

        XCTAssertTrue(prompt.contains("校园学习与生活助手"))
        XCTAssertTrue(prompt.contains("一般建议"))
        XCTAssertTrue(prompt.contains("不要反复解释内部数据来源"))
        XCTAssertTrue(prompt.contains("PDF"))
        XCTAssertTrue(prompt.contains("本地文件路径"))
        XCTAssertTrue(prompt.contains("不提供诊断"))
        XCTAssertTrue(prompt.contains("中文 Markdown"))
        XCTAssertTrue(CampusAIService.actionPlannerSystemPrompt().contains("普通日程、事项、待办、提醒、重要日期或自定日程管理用 customCountdowns"))
        XCTAssertTrue(CampusAIService.actionPlannerSystemPrompt().contains("考试、考场、考试时间、考试安排"))
        XCTAssertTrue(prompt.contains("请顺便给生活建议"))
    }

    func testRequestBuilderRejectsInvalidBaseURL() {
        XCTAssertThrowsError(
            try CampusAIService.chatCompletionsURL(baseURLString: "http://api.deepseek.com")
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Base URL 设置不正确，请使用 HTTPS 地址。")
        }
    }

    func testSSEParserHandlesOpenAICompatibleSplitDeltaCommentsAndDone() throws {
        var parser = CampusAISSEParser()
        var events = try parser.append(Data(": KEEPALIVE\n\n".utf8))
        XCTAssertTrue(events.isEmpty)

        events = try parser.append(Data("data: {\"choices\":[{\"delta\":{\"content\":\"# 标题\"}}]}\n\n".utf8))
        XCTAssertEqual(events, [.delta("# 标题")])

        events = try parser.append(Data("data: {\"choices\":[{\"delta\":{\"content\":\"\\n- 第一".utf8))
        XCTAssertTrue(events.isEmpty)

        events = try parser.append(Data("点\"}}]}\n\ndata: [DONE]\n\n".utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .delta("\n- 第一点"))
        if case .done(let response) = events.last {
            XCTAssertEqual(response.answer, "# 标题\n- 第一点")
            XCTAssertNil(response.suggestedTitle)
            XCTAssertNil(response.summary)
        } else {
            XCTFail("expected done event")
        }

        XCTAssertTrue(try parser.finish().isEmpty)
    }

    func testSSEParserHandlesDeepSeekReasoningUsageOnlyCRLFAndFinishReason() throws {
        var parser = CampusAISSEParser()

        var events = try parser.append(Data("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"先看课表\"},\"finish_reason\":null}]}\r\n\r\n".utf8))
        XCTAssertEqual(events, [.reasoningDelta("先看课表")])

        events = try parser.append(Data("data: {\"choices\":[{\"delta\":{\"content\":\"明天有两节课。\"},\"finish_reason\":\"stop\"}]}\r\n\r\n".utf8))
        XCTAssertEqual(events, [.delta("明天有两节课。")])

        events = try parser.append(Data("data: {\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":3}}\r\n\r\n".utf8))
        XCTAssertTrue(events.isEmpty)

        events = try parser.append(Data("data: [DONE]\r\n\r\n".utf8))
        XCTAssertEqual(events.count, 1)
        if case .done(let response) = events.first {
            XCTAssertEqual(response.answer, "明天有两节课。")
            XCTAssertEqual(response.reasoning, "先看课表")
            XCTAssertEqual(response.finishReason, "stop")
        } else {
            XCTFail("expected done event")
        }
    }

    func testSSEParserHandlesMultilineDataEvent() throws {
        var parser = CampusAISSEParser()
        let block = """
        data: {
        data:   "choices": [
        data:     {"delta": {"content": "多行 JSON"}}
        data:   ]
        data: }

        """

        let events = try parser.append(Data((block + "\n").utf8))

        XCTAssertEqual(events, [.delta("多行 JSON")])
    }

    func testSSEParserHandlesManagedAgentEvents() throws {
        var parser = CampusAISSEParser()
        let raw = """
        data: {"type":"agent_status","text":"正在联网搜索"}

        data: {"type":"agent_step","step":{"id":"step-1","kind":"tool","title":"联网搜索","detail":"找到结果","status":"completed","tool":"web.search","timestamp":"2026-07-02T00:00:00Z"}}

        data: {"type":"agent_tool","tool":{"name":"web.search","status":"completed","detail":"北林通知","resultCount":2}}

        data: {"type":"agent_citation","citation":{"id":"web-1","title":"北京林业大学通知","url":"https://www.bjfu.edu.cn/notice","siteName":"北京林业大学","summary":"通知摘要","publishedAt":"2026-07-02T00:00:00+08:00"}}

        """

        var events = try parser.append(Data(raw.utf8))
        events.append(contentsOf: try parser.finish())
        events.removeAll {
            if case .done = $0 {
                return true
            }
            return false
        }

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0], .agentStatus("正在联网搜索"))
        if case .agentStep(let step) = events[1] {
            XCTAssertEqual(step.id, "step-1")
            XCTAssertEqual(step.tool, "web.search")
            XCTAssertEqual(step.status, "completed")
        } else {
            XCTFail("expected agent step")
        }
        if case .agentTool(let tool) = events[2] {
            XCTAssertEqual(tool.name, "web.search")
            XCTAssertEqual(tool.resultCount, 2)
        } else {
            XCTFail("expected agent tool")
        }
        if case .agentCitation(let citation) = events[3] {
            XCTAssertEqual(citation.title, "北京林业大学通知")
            XCTAssertEqual(citation.siteName, "北京林业大学")
            XCTAssertEqual(citation.publishedAt, "2026-07-02T00:00:00+08:00")
        } else {
            XCTFail("expected agent citation")
        }
    }

    func testSSEParserPreservesSplitUnicodeBytes() throws {
        var parser = CampusAISSEParser()
        let data = Data("data: {\"choices\":[{\"delta\":{\"content\":\"明天\"}}]}\n\n".utf8)
        let splitIndex = try XCTUnwrap(data.firstIndex(of: 0xE6)).advanced(by: 1)

        var events = try parser.append(Data(data[..<splitIndex]))
        XCTAssertTrue(events.isEmpty)

        events = try parser.append(Data(data[splitIndex...]))
        XCTAssertEqual(events, [.delta("明天")])
    }

    func testRealDeepSeekSSEFixtureDecodesAcrossRawByteChunks() throws {
        let bundle = Bundle(for: type(of: self))
        let fixtureURL = bundle.url(
            forResource: "deepseek-v4-flash-stream",
            withExtension: "sse",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: "deepseek-v4-flash-stream", withExtension: "sse")
        let data = try Data(contentsOf: XCTUnwrap(fixtureURL))
        var parser = CampusAISSEParser()
        var events: [CampusAIStreamEvent] = []

        for start in stride(from: data.startIndex, to: data.endIndex, by: 4_096) {
            let end = min(start + 4_096, data.endIndex)
            events.append(contentsOf: try parser.append(Data(data[start..<end])))
        }
        events.append(contentsOf: try parser.finish())

        let response = try XCTUnwrap(events.compactMap { event -> CampusAIResponse? in
            if case .done(let response) = event {
                return response
            }
            return nil
        }.last)
        XCTAssertEqual(response.answer, "测试成功")
        XCTAssertFalse(response.reasoning.isEmpty)
        XCTAssertEqual(response.finishReason, "stop")
    }

    func testProviderEventsDecodeCompleteJSONResponse() throws {
        let body = """
        {
          "choices": [
            {
              "message": {
                "reasoning_content": "先判断上下文",
                "content": "这是完整 JSON 响应。"
              },
              "finish_reason": "stop"
            }
          ]
        }
        """

        let events = try CampusAIService.providerEvents(from: body)

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .reasoningDelta("先判断上下文"))
        XCTAssertEqual(events[1], .delta("这是完整 JSON 响应。"))
        if case .done(let response) = events[2] {
            XCTAssertEqual(response.answer, "这是完整 JSON 响应。")
            XCTAssertEqual(response.reasoning, "先判断上下文")
            XCTAssertEqual(response.finishReason, "stop")
        } else {
            XCTFail("expected done event")
        }
    }

    func testProviderEventsRejectBrokenResponse() {
        XCTAssertThrowsError(try CampusAIService.providerEvents(from: "not-json"))
    }

    func testCampusAIMessageDefaultsReasoningText() {
        let message = CampusAIMessage(
            conversationID: UUID().uuidString,
            roleRawValue: CampusAIMessageRole.assistant.rawValue,
            text: "回答"
        )

        XCTAssertEqual(message.reasoningText, "")
        XCTAssertEqual(message.agentMetadataJSON, "")
        XCTAssertEqual(message.agentMetadata.citations, [])
        XCTAssertEqual(message.agentMetadata.deliverables, [])
    }

    func testCampusAIMetadataDecodesLegacyJSONWithoutDeliverables() {
        let message = CampusAIMessage(
            conversationID: UUID().uuidString,
            roleRawValue: CampusAIMessageRole.assistant.rawValue,
            text: "回答"
        )
        message.agentMetadataJSON = """
        {"citations":[{"id":"web-1","title":"通知","url":"https://www.bjfu.edu.cn/notice"}],"agentTrace":[]}
        """

        XCTAssertEqual(message.agentMetadata.citations.first?.url, "https://www.bjfu.edu.cn/notice")
        XCTAssertEqual(message.agentMetadata.deliverables, [])
    }

    func testMarkdownRendererUsesLocalResourcesAndSecurityPolicy() {
        let html = CampusAIMarkdownHTML.baseDocument

        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("script-src 'self'"))
        XCTAssertTrue(html.contains("img-src https:"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertTrue(CampusAIMarkdownHTML.requiredResourceNames.contains("renderer.js"))
        XCTAssertTrue(CampusAIMarkdownHTML.requiredResourceNames.contains("purify.min.js"))
        XCTAssertTrue(CampusAIMarkdownHTML.requiredResourceNames.contains("katex.min.js"))
        XCTAssertTrue(CampusAIMarkdownHTML.requiredResourceNames.contains("mermaid.min.js"))
    }

    @MainActor
    func testMarkdownWebRendererRendersAndSanitizesFixture() async throws {
        XCTAssertTrue(CampusAIMarkdownHTML.hasRequiredResources())

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        let loaded = expectation(description: "markdown renderer loaded")
        let navigationDelegate = CampusAIMarkdownTestNavigationDelegate(expectation: loaded)
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(
            CampusAIMarkdownHTML.baseDocument,
            baseURL: CampusAIMarkdownHTML.rendererDirectory()
        )
        await fulfillment(of: [loaded], timeout: 8)
        if let error = navigationDelegate.error {
            throw error
        }

        let markdown = """
        # 标题
        **加粗**、~~删除线~~与 [安全链接](https://example.com)

        - [x] 已完成
        - [ ] 未完成

        | 列 A | 列 B |
        | --- | --- |
        | 1 | 2 |

        ```swift
        let value = 42
        ```

        ```mermaid
        flowchart TD
          A[开始] --> B[结束]
        ```

        公式：$E = mc^2$

        脚注引用[^note]

        [^note]: 脚注内容

        <b>允许的 HTML</b>
        <script>window.unsafe = true</script>
        <iframe src="https://example.com"></iframe>
        <img src="javascript:alert(1)" onerror="alert(1)">
        <img src="https://example.invalid/image.png" alt="remote image">
        <a href="javascript:alert(1)">危险链接</a>
        """
        let literal = CampusAIMarkdownHTML.javascriptStringLiteral(markdown)
        _ = try await webView.evaluateJavaScript("window.LeafyMarkdown.render(\(literal));")
        try await Task.sleep(nanoseconds: 600_000_000)

        let result = try await webView.evaluateJavaScript(
            """
            JSON.stringify({
              h1: document.querySelectorAll('h1').length,
              bold: document.querySelectorAll('strong').length,
              deleted: document.querySelectorAll('del, s').length,
              tasks: document.querySelectorAll('.task-marker').length,
              table: document.querySelectorAll('table').length,
              code: document.querySelectorAll('.code-block').length,
              mermaid: document.querySelectorAll('.mermaid-diagram svg').length,
              math: document.querySelectorAll('.katex').length,
              footnotes: document.querySelectorAll('.footnotes').length,
              safeHTML: document.querySelectorAll('b').length,
              httpsImages: document.querySelectorAll('img[src^="https://"]').length,
              scripts: document.querySelectorAll('#content script').length,
              iframes: document.querySelectorAll('iframe').length,
              eventHandlers: document.querySelectorAll('[onerror]').length,
              javascriptURLs: document.querySelectorAll('[href^="javascript:"], [src^="javascript:"]').length
            })
            """
        )
        let json = try XCTUnwrap(result as? String)
        let data = Data(json.utf8)
        let counts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])

        XCTAssertEqual(counts["h1"], 1)
        XCTAssertEqual(counts["bold"], 1)
        XCTAssertEqual(counts["deleted"], 1)
        XCTAssertEqual(counts["tasks"], 2)
        XCTAssertEqual(counts["table"], 1)
        XCTAssertEqual(counts["code"], 1)
        XCTAssertEqual(counts["mermaid"], 1)
        XCTAssertEqual(counts["math"], 1)
        XCTAssertEqual(counts["footnotes"], 1)
        XCTAssertEqual(counts["safeHTML"], 1)
        XCTAssertEqual(counts["httpsImages"], 1)
        XCTAssertEqual(counts["scripts"], 0)
        XCTAssertEqual(counts["iframes"], 0)
        XCTAssertEqual(counts["eventHandlers"], 0)
        XCTAssertEqual(counts["javascriptURLs"], 0)
    }

    func testSSEParserSurfacesRedactedProviderErrors() {
        var parser = CampusAISSEParser()
        let rawKey = "246114398185460a8f995bf98286645f.FNCxO5AoHHZgaUbO"

        XCTAssertThrowsError(
            try parser.append(Data("data: {\"error\":{\"message\":\"provider failed with \(rawKey)\"}}\n\n".utf8))
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("[redacted]"))
            XCTAssertFalse(error.localizedDescription.contains(rawKey))
        }
    }

    func testProviderErrorRedactionRemovesSecrets() {
        let rawKey = "246114398185460a8f995bf98286645f.FNCxO5AoHHZgaUbO"
        let message = CampusAIService.redactProviderError("failed with \(rawKey) and sk-test_secret_123")

        XCTAssertTrue(message.contains("[redacted]"))
        XCTAssertTrue(message.contains("sk-redacted"))
        XCTAssertFalse(message.contains(rawKey))
        XCTAssertFalse(message.contains("sk-test_secret_123"))
    }

    func testActionValidationAcceptsSupportedDraftsAndRejectsUnknownRoutes() {
        let openRoute = CampusAIActionDraft(
            kind: .openAcademicRoute,
            title: "",
            payload: CampusAIActionPayload(route: "grades")
        )
        let invalidRoute = CampusAIActionDraft(
            kind: .openAcademicRoute,
            title: "打开未知页面",
            payload: CampusAIActionPayload(route: "communityPost")
        )

        XCTAssertEqual(CampusAIActionValidation.validate(openRoute)?.payload.route, "grades")
        XCTAssertEqual(CampusAIActionValidation.validate(
            CampusAIActionDraft(kind: .openAcademicRoute, title: "", payload: CampusAIActionPayload(route: "medicalLedger"))
        )?.payload.route, "medicalLedger")
        XCTAssertNil(CampusAIActionValidation.validate(invalidRoute))
    }

    func testActionValidationAcceptsCountdownsAndRejectsInvalidDates() {
        let countdown = CampusAIActionDraft(
            kind: .createCountdown,
            title: "",
            payload: CampusAIActionPayload(countdownTitle: "期末考试", targetDate: "2026-07-01")
        )
        let invalidCountdown = CampusAIActionDraft(
            kind: .createCountdown,
            title: "创建重要日期",
            payload: CampusAIActionPayload(countdownTitle: "期末考试", targetDate: "not-a-date")
        )

        XCTAssertEqual(CampusAIActionValidation.validate(countdown)?.payload.countdownTitle, "期末考试")
        XCTAssertNil(CampusAIActionValidation.validate(invalidCountdown))
    }

    func testActionValidationAcceptsTimetableRemindersAndRejectsInvalidCells() {
        let reminder = CampusAIActionDraft(
            kind: .createTimetableReminder,
            title: "",
            payload: CampusAIActionPayload(
                week: 2,
                dayOfWeek: 3,
                period: 5,
                endPeriod: 6,
                title: "提交实验报告",
                minutesBefore: -5
            )
        )
        let invalidReminder = CampusAIActionDraft(
            kind: .createTimetableReminder,
            title: "创建课表提醒",
            payload: CampusAIActionPayload(week: 0, dayOfWeek: 8, period: 99, title: "坏数据")
        )

        let validated = CampusAIActionValidation.validate(reminder)
        XCTAssertEqual(validated?.payload.title, "提交实验报告")
        XCTAssertEqual(validated?.payload.minutesBefore, 0)
        XCTAssertNil(CampusAIActionValidation.validate(invalidReminder))
    }

    func testActionPayloadDecodesSnakeCaseFields() throws {
        let data = Data(
            """
            {
              "countdown_title": "期末考试",
              "target_date": "2026-07-01",
              "day_of_week": 3,
              "end_period": 6,
              "minutes_before": 10
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(CampusAIActionPayload.self, from: data)

        XCTAssertEqual(payload.countdownTitle, "期末考试")
        XCTAssertEqual(payload.targetDate, "2026-07-01")
        XCTAssertEqual(payload.dayOfWeek, 3)
        XCTAssertEqual(payload.endPeriod, 6)
        XCTAssertEqual(payload.minutesBefore, 10)
    }

    func testManagedDonePayloadDecodesActions() throws {
        var parser = CampusAISSEParser()
        let raw = """
        data: {"type":"done","answer":"已整理。","actions":[{"kind":"open_academic_route","title":"","payload":{"route":"trainingProgram"}},{"kind":"create_countdown","title":"创建重要日期","payload":{"countdown_title":"期末考试","target_date":"2026-07-01"}}],"citations":[{"id":"web-1","title":"通知","url":"https://www.bjfu.edu.cn/notice"}],"agentTrace":[{"id":"trace-1","kind":"tool","title":"联网搜索","status":"completed"}],"deliverables":[{"id":"pack-1","title":"论文格式资料包","query":"北京林业大学 论文格式","summary":"已找到教务处官方页面。","generated_at":"2026-07-02T00:00:00Z","sources":[{"id":"source-1","title":"本科论文格式","url":"https://jwc.bjfu.edu.cn/info/1012/1234.htm","site_name":"北京林业大学教务处","summary":"页面含论文格式附件。","trust_score":0.95,"attachments":[{"title":"论文模板.docx","url":"https://jwc.bjfu.edu.cn/files/template.docx","file_type":"docx"}]}],"formats":["html","markdown","txt"],"content":{"html":"<main><h1>Artifact</h1></main>","markdown":"# Artifact","text":"Artifact"}}]}

        """

        var events = try parser.append(Data(raw.utf8))
        events.append(contentsOf: try parser.finish())
        let response = try XCTUnwrap(events.compactMap { event -> CampusAIResponse? in
            if case .done(let response) = event {
                return response
            }
            return nil
        }.first)

        XCTAssertEqual(response.actions.count, 2)
        XCTAssertEqual(response.actions.first?.kind, .openAcademicRoute)
        XCTAssertEqual(response.actions.first?.payload.route, "trainingProgram")
        XCTAssertEqual(response.actions.last?.payload.countdownTitle, "期末考试")
        XCTAssertEqual(response.citations.first?.url, "https://www.bjfu.edu.cn/notice")
        XCTAssertEqual(response.agentTrace.first?.title, "联网搜索")
        XCTAssertEqual(response.deliverables.first?.title, "论文格式资料包")
        XCTAssertEqual(response.deliverables.first?.sources.first?.siteName, "北京林业大学教务处")
        XCTAssertEqual(response.deliverables.first?.sources.first?.attachments.first?.fileType, "docx")
        XCTAssertEqual(response.deliverables.first?.formats, [.html, .markdown, .txt])
        XCTAssertEqual(response.deliverables.first?.content?.markdown, "# Artifact")
    }

    func testCampusAIServiceSendPreservesActions() async throws {
        let action = CampusAIActionDraft(
            kind: .openAcademicRoute,
            title: "打开培养方案",
            payload: CampusAIActionPayload(route: "trainingProgram")
        )
        let citation = CampusAICitation(
            id: "web-1",
            title: "培养方案通知",
            url: "https://www.bjfu.edu.cn/notice"
        )
        let trace = CampusAIAgentTraceStep(
            id: "trace-1",
            kind: "tool",
            title: "联网搜索",
            detail: nil,
            status: "completed",
            tool: "web.search",
            role: nil,
            timestamp: nil
        )
        let deliverable = CampusAIDeliverable(
            id: "pack-1",
            title: "论文格式资料包",
            query: "论文格式",
            summary: "已整理官方来源。",
            generatedAt: "2026-07-02T00:00:00Z",
            sources: [
                CampusAIDeliverableSource(
                    id: "source-1",
                    title: "教务处页面",
                    url: "https://jwc.bjfu.edu.cn/info/1012/1234.htm"
                )
            ]
        )
        let service = CampusAIService { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.delta("已整理。"))
                continuation.yield(.done(CampusAIResponse(
                    answer: "已整理。",
                    actions: [action],
                    citations: [citation],
                    agentTrace: [trace],
                    deliverables: [deliverable]
                )))
                continuation.finish()
            }
        }

        let response = try await service.send(
            message: "帮我打开培养方案",
            context: minimalAIContext(),
            recentMessages: []
        )

        XCTAssertEqual(response.answer, "已整理。")
        XCTAssertEqual(response.actions, [action])
        XCTAssertEqual(response.citations, [citation])
        XCTAssertEqual(response.agentTrace, [trace])
        XCTAssertEqual(response.deliverables, [deliverable])
    }

    func testDeliverableFileBuilderEscapesHTMLAndIncludesLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusAIDeliverableTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let deliverable = CampusAIDeliverable(
            id: "pack-1",
            title: "论文<格式>资料包",
            query: "北京林业大学 论文格式",
            summary: "已整理 <官方> 来源。",
            generatedAt: "2026-07-02T00:00:00Z",
            sources: [
                CampusAIDeliverableSource(
                    id: "source-1",
                    title: "教务处论文格式",
                    url: "https://jwc.bjfu.edu.cn/info/1012/1234.htm",
                    siteName: "北京林业大学教务处",
                    summary: "页面含论文模板。",
                    trustScore: 0.95,
                    attachments: [
                        CampusAIDeliverableAttachment(
                            title: "论文模板.docx",
                            url: "https://jwc.bjfu.edu.cn/files/template.docx",
                            fileType: "docx"
                        )
                    ]
                )
            ]
        )

        let htmlURL = try CampusAIDeliverableFileBuilder.writeFile(
            for: deliverable,
            messageID: UUID(),
            format: .html,
            rootDirectory: root
        )
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        XCTAssertTrue(html.contains("论文&lt;格式&gt;资料包"))
        XCTAssertTrue(html.contains("已整理 &lt;官方&gt; 来源。"))
        XCTAssertTrue(html.contains("https://jwc.bjfu.edu.cn/info/1012/1234.htm"))
        XCTAssertTrue(html.contains("https://jwc.bjfu.edu.cn/files/template.docx"))

        let markdown = CampusAIDeliverableFileBuilder.content(for: deliverable, format: .markdown)
        XCTAssertTrue(markdown.contains("[教务处论文格式](https://jwc.bjfu.edu.cn/info/1012/1234.htm)"))
        XCTAssertTrue(markdown.contains("[论文模板.docx](https://jwc.bjfu.edu.cn/files/template.docx)"))
    }

    func testDeliverableFileBuilderPrefersArtifactContentWhenPresent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusAIArtifactContentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let deliverable = CampusAIDeliverable(
            id: "artifact-pack",
            title: "Artifact",
            query: "生成网页",
            summary: "已生成。",
            generatedAt: "2026-07-02T00:00:00Z",
            sources: [],
            formats: [.html, .markdown, .txt],
            content: CampusAIArtifactContent(
                html: "<main><h1>Custom HTML</h1></main>",
                markdown: "# Custom Markdown",
                text: "Custom Text"
            )
        )

        let htmlURL = try CampusAIDeliverableFileBuilder.writeFile(
            for: deliverable,
            messageID: UUID(),
            format: .html,
            rootDirectory: root
        )
        let markdown = CampusAIDeliverableFileBuilder.content(for: deliverable, format: .markdown)
        let text = CampusAIDeliverableFileBuilder.content(for: deliverable, format: .txt)

        XCTAssertEqual(try String(contentsOf: htmlURL, encoding: .utf8), "<main><h1>Custom HTML</h1></main>")
        XCTAssertEqual(markdown, "# Custom Markdown")
        XCTAssertEqual(text, "Custom Text")
    }

    func testDeliverableFileBuilderRemovesStaleArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusAIDeliverableLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let retainedID = UUID()
        let staleID = UUID()
        let deliverable = CampusAIDeliverable(
            id: "pack-1",
            title: "资料包",
            query: "论文格式",
            summary: "已整理。",
            generatedAt: "2026-07-02T00:00:00Z",
            sources: []
        )

        let retainedURL = try CampusAIDeliverableFileBuilder.writeFile(
            for: deliverable,
            messageID: retainedID,
            format: .txt,
            rootDirectory: root
        )
        let staleURL = try CampusAIDeliverableFileBuilder.writeFile(
            for: deliverable,
            messageID: staleID,
            format: .txt,
            rootDirectory: root
        )

        try CampusAIDeliverableFileBuilder.pruneArtifacts(keeping: [retainedID], rootDirectory: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))

        try CampusAIDeliverableFileBuilder.removeArtifacts(for: retainedID, rootDirectory: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retainedURL.path))
    }

    func testLocalArtifactBuilderGeneratesDeliverableFromLocalRetrieval() throws {
        let context = CampusAIContextBuilder.build(
            courses: [],
            grades: [],
            exams: [],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            learningTasks: [
                LearningProjectTask(title: "整理论文提纲", note: "周五前完成 <初稿>")
            ]
        )
        let request = CampusAIRequest(
            message: "请把学习任务整理成 HTML Markdown TXT 资料包",
            context: context,
            recentMessages: [],
            capabilities: CampusAICapabilitySet(serviceMode: .ownAPIKey, webSearchEnabled: false),
            localRetrieval: CampusAILocalKnowledgeIndex.search(query: "学习任务 资料包", context: context)
        )

        let deliverable = try XCTUnwrap(CampusAILocalArtifactBuilder.deliverables(for: request, answer: "已整理 <任务>。").first)

        XCTAssertEqual(deliverable.formats, [.html, .markdown, .txt])
        XCTAssertEqual(deliverable.sources.first?.siteName, "Leafy 学习资料")
        XCTAssertTrue(deliverable.sources.first?.url.hasPrefix("leafy://local/learning/") == true)
        let html = CampusAIDeliverableFileBuilder.content(for: deliverable, format: .html)
        XCTAssertTrue(html.contains("已整理 &lt;任务&gt;。"))
        XCTAssertTrue(html.contains("周五前完成 &lt;初稿&gt;"))

        let defaultRequest = CampusAIRequest(
            message: "请把学习任务整理成资料包",
            context: context,
            recentMessages: [],
            capabilities: CampusAICapabilitySet(serviceMode: .ownAPIKey, webSearchEnabled: false),
            localRetrieval: CampusAILocalKnowledgeIndex.search(query: "学习任务 资料包", context: context)
        )
        XCTAssertEqual(
            CampusAILocalArtifactBuilder.deliverables(for: defaultRequest, answer: "已整理。").first?.formats,
            [.html]
        )
    }

    func testActionPlannerExtractsAndValidatesJSONActions() {
        let content = """
        ```json
        {
          "actions": [
            {"kind":"create_timetable_reminder","title":"","detail":"提醒提交实验报告","payload":{"week":2,"day_of_week":3,"period":5,"end_period":4,"title":"提交实验报告","minutes_before":-5}},
            {"kind":"open_academic_route","title":"","payload":{"route":"communityPost"}}
          ]
        }
        ```
        """

        let actions = CampusAIService.actionPlannerActions(fromContent: content)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, .createTimetableReminder)
        XCTAssertEqual(actions.first?.payload.title, "提交实验报告")
        XCTAssertNil(actions.first?.payload.endPeriod)
        XCTAssertEqual(actions.first?.payload.minutesBefore, 0)
    }

    func testSettingsStoreNormalizesLegacyManagedModeAndWebSearch() throws {
        let suiteName = "CampusAIAssistantTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyCurrentJSON = """
        {
          "serviceMode":"leafyManaged",
          "selectedProviderID":"deepseek",
          "systemPrompt":"保留这个偏好",
          "contextSettings":{
            "includesTimetable":true,
            "includesGrades":true,
            "includesExamsAndPlans":true,
            "includesLearningWorkspace":true,
            "includesPostgraduateAndCareer":true,
            "includesHonorsFitnessQuality":true,
            "includesMedicalLedger":true,
            "includesCommunityCache":true
          },
          "webSearchEnabled":true
        }
        """
        defaults.set(Data(legacyCurrentJSON.utf8), forKey: "campusAI.userSettings.v2")

        let settings = CampusAISettingsStore.load(userDefaults: defaults)

        XCTAssertEqual(settings.serviceMode, .ownAPIKey)
        XCTAssertFalse(settings.webSearchEnabled)
        XCTAssertEqual(settings.systemPrompt, "保留这个偏好")
    }

    func testArtifactIntentSupportsAutomaticAndForcedModes() {
        XCTAssertTrue(CampusAIArtifactIntentResolver.shouldGenerateArtifact(
            message: "帮我做一份期末复习计划",
            mode: .automatic
        ))
        XCTAssertTrue(CampusAIArtifactIntentResolver.shouldGenerateArtifact(
            message: "明天有什么课？",
            mode: .artifact
        ))
        XCTAssertFalse(CampusAIArtifactIntentResolver.shouldGenerateArtifact(
            message: "明天有什么课？",
            mode: .automatic
        ))
    }

    func testCampusAIRequestOutputModeDefaultsAndDecodesOldPayload() throws {
        let request = CampusAIRequest(
            message: "整理计划",
            context: minimalAIContext(),
            recentMessages: []
        )
        XCTAssertEqual(request.outputMode, .automatic)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        object.removeValue(forKey: "outputMode")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CampusAIRequest.self, from: oldData)
        XCTAssertEqual(decoded.outputMode, .automatic)
    }

    func testCompletionPlanParsesArtifactAndValidatesActions() throws {
        let content = """
        ```json
        {
          "actions": [
            {"kind":"open_academic_route","title":"","payload":{"route":"trainingProgram"}},
            {"kind":"open_academic_route","title":"无效","payload":{"route":"not-a-route"}}
          ],
          "artifact": {
            "title": "期末复习计划",
            "summary": "按周整理复习节奏。",
            "markdown": "# 期末复习计划\\n\\n## 第一周\\n- 梳理范围"
          }
        }
        ```
        """

        let plan = try CampusAICompletionPlanParser.parse(content)

        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.payload.route, "trainingProgram")
        XCTAssertEqual(plan.artifact?.title, "期末复习计划")
        XCTAssertTrue(plan.artifact?.markdown.contains("第一周") == true)
    }

    func testCompletionPlanRejectsInvalidJSONAndEmptyArtifact() {
        XCTAssertThrowsError(try CampusAICompletionPlanParser.parse("不是 JSON"))
        XCTAssertNoThrow(try CampusAICompletionPlanParser.parse("{\"actions\":[],\"artifact\":null}"))

        let plan = try? CampusAICompletionPlanParser.parse(
            "{\"actions\":[],\"artifact\":{\"title\":\"\",\"summary\":\"\",\"markdown\":\"\"}}"
        )
        XCTAssertNil(plan?.artifact)
    }

    func testArtifactAssemblerAttachesOnlyLocalSources() throws {
        let context = CampusAIContextBuilder.build(
            courses: [],
            grades: [],
            exams: [],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            learningTasks: [LearningProjectTask(title: "复习数据结构", note: "周五前")]
        )
        let retrieval = CampusAILocalKnowledgeIndex.search(query: "复习计划", context: context)
        let request = CampusAIRequest(
            message: "生成复习计划",
            context: context,
            recentMessages: [],
            capabilities: CampusAICapabilitySet(serviceMode: .ownAPIKey, webSearchEnabled: false),
            localRetrieval: retrieval,
            outputMode: .artifact
        )
        let draft = CampusAIArtifactDraft(
            title: "复习计划",
            summary: "一周执行清单",
            markdown: "# 复习计划\n\n- 复习数据结构"
        )

        let artifact = try XCTUnwrap(CampusAIArtifactAssembler.deliverable(from: draft, request: request))

        XCTAssertEqual(artifact.content?.markdown, draft.markdown)
        XCTAssertTrue(artifact.sources.allSatisfy { $0.url.hasPrefix("leafy://local/") })
        XCTAssertTrue(artifact.sources.allSatisfy { $0.siteName == "Leafy 本机数据" })
    }

    func testLegacyAgentMetadataDefaultsArtifactState() throws {
        let empty = try JSONDecoder().decode(
            CampusAIMessageAgentMetadata.self,
            from: Data("{\"statusText\":null,\"citations\":[],\"agentTrace\":[],\"deliverables\":[]}".utf8)
        )
        XCTAssertEqual(empty.artifactState, .none)
        XCTAssertNil(empty.artifactErrorMessage)

        let legacyReady = try JSONDecoder().decode(
            CampusAIMessageAgentMetadata.self,
            from: Data(
                """
                {"citations":[],"agentTrace":[],"deliverables":[{"id":"a","title":"成品","query":"q","summary":"s","generatedAt":"now","sources":[],"formats":["markdown"],"content":{"markdown":"# 成品"}}]}
                """.utf8
            )
        )
        XCTAssertEqual(legacyReady.artifactState, .ready)
    }

    @MainActor
    func testArtifactExportServiceExportsFourSafeFormats() async throws {
        let messageID = UUID()
        let artifact = CampusAIDeliverable(
            id: "export-artifact",
            title: "复习计划",
            query: "生成复习计划",
            summary: "一周安排",
            generatedAt: "2026-07-10T00:00:00Z",
            sources: [],
            content: CampusAIArtifactContent(
                markdown: "# 复习计划\n\n## 周一\n\n- 高等数学\n- 数据结构"
            )
        )
        let service = CampusAIArtifactExportService()

        let markdownURL = try await service.export(artifact, messageID: messageID, format: .markdown)
        let htmlURL = try await service.export(artifact, messageID: messageID, format: .html)
        let textURL = try await service.export(artifact, messageID: messageID, format: .plainText)
        let pdfURL = try await service.export(artifact, messageID: messageID, format: .pdf)
        defer { try? FileManager.default.removeItem(at: markdownURL.deletingLastPathComponent()) }

        XCTAssertEqual(try String(contentsOf: markdownURL, encoding: .utf8), artifact.content?.markdown)
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        XCTAssertFalse(CampusAIArtifactExportService.containsExecutableScript(html))
        XCTAssertTrue(html.contains("复习计划"))
        XCTAssertTrue(try String(contentsOf: textURL, encoding: .utf8).contains("高等数学"))
        XCTAssertTrue(try Data(contentsOf: pdfURL).starts(with: Data("%PDF".utf8)))
    }

    private func minimalAIContext() -> CampusAIContextPayload {
        CampusAIContextBuilder.build(
            courses: [],
            grades: [],
            exams: [],
            teachingPlan: [],
            trainingProgram: nil,
            countdowns: [],
            now: SemesterConfig.startOfSemesterDate
        )
    }
}
