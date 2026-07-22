nonisolated enum CampusAILocalKnowledgeDomain: String, Codable, CaseIterable, Hashable, Identifiable {
    case schedule
    case learning
    case academics
    case postgraduateCareer
    case fitnessSports
    case honorsQuality
    case medical
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "时间日程"
        case .learning: return "学习资料"
        case .academics: return "学业成绩"
        case .postgraduateCareer: return "考研职业"
        case .fitnessSports: return "体育体测"
        case .honorsQuality: return "荣誉综测"
        case .medical: return "医疗台账"
        case .community: return "社区公开摘要"
        }
    }

    var intentKeywords: [String] {
        switch self {
        case .schedule:
            return ["日程", "安排", "课表", "考试", "提醒", "待办", "倒计时", "重要日期", "自定日程", "今天", "明天", "本周"]
        case .learning:
            return ["学习", "资料", "任务", "项目", "复习", "笔记", "材料", "自习"]
        case .academics:
            return ["成绩", "绩点", "gpa", "排名", "学分", "培养方案", "教学计划", "毕业"]
        case .postgraduateCareer:
            return ["考研", "保研", "推免", "职业", "实习", "简历", "投递", "目标院校"]
        case .fitnessSports:
            return ["体育", "体测", "长跑", "阳光", "运动", "场馆", "跑步"]
        case .honorsQuality:
            return ["荣誉", "综测", "综合素质", "证明", "奖项", "材料"]
        case .medical:
            return ["医疗", "医保", "报销", "就诊", "医院", "台账", "材料", "发票"]
        case .community:
            return ["社区", "帖子", "动态", "同学", "公开", "讨论"]
        }
    }
}

nonisolated private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func clampedForAIContext(_ limit: Int = 240) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(limit - 1, 0))) + "…"
    }
}

nonisolated struct CampusAILocalKnowledgeResult: Identifiable, Codable, Hashable {
    var id: String
    var domain: CampusAILocalKnowledgeDomain
    var title: String
    var summary: String
    var sourceID: String
    var routeHint: String?
    var updatedAt: String?
    var score: Int

    enum CodingKeys: String, CodingKey {
        case id
        case domain
        case title
        case summary
        case sourceID
        case sourceIDSnake = "source_id"
        case routeHint
        case routeHintSnake = "route_hint"
        case updatedAt
        case updatedAtSnake = "updated_at"
        case score
    }

    init(
        id: String,
        domain: CampusAILocalKnowledgeDomain,
        title: String,
        summary: String,
        sourceID: String,
        routeHint: String? = nil,
        updatedAt: String? = nil,
        score: Int = 0
    ) {
        self.id = id
        self.domain = domain
        self.title = title
        self.summary = summary
        self.sourceID = sourceID
        self.routeHint = routeHint
        self.updatedAt = updatedAt
        self.score = score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        domain = try container.decodeIfPresent(CampusAILocalKnowledgeDomain.self, forKey: .domain) ?? .academics
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
            ?? container.decodeIfPresent(String.self, forKey: .sourceIDSnake)
            ?? id
        routeHint = try container.decodeIfPresent(String.self, forKey: .routeHint)
            ?? container.decodeIfPresent(String.self, forKey: .routeHintSnake)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .updatedAtSnake)
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(domain, forKey: .domain)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encodeIfPresent(routeHint, forKey: .routeHint)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(score, forKey: .score)
    }
}

nonisolated struct CampusAILocalRetrievalPayload: Codable, Hashable {
    var query: String
    var generatedAt: String
    var results: [CampusAILocalKnowledgeResult]

    var isEmpty: Bool { results.isEmpty }

    enum CodingKeys: String, CodingKey {
        case query
        case generatedAt
        case generatedAtSnake = "generated_at"
        case results
    }

    init(query: String, generatedAt: String = ISO8601DateFormatter().string(from: Date()), results: [CampusAILocalKnowledgeResult]) {
        self.query = query
        self.generatedAt = generatedAt
        self.results = results
    }

    static func empty(query: String) -> CampusAILocalRetrievalPayload {
        CampusAILocalRetrievalPayload(query: query, results: [])
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generatedAtSnake)
            ?? ""
        results = try container.decodeIfPresent([CampusAILocalKnowledgeResult].self, forKey: .results) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(results, forKey: .results)
    }
}

nonisolated enum CampusAILocalKnowledgeIndex {
    private struct Candidate {
        var domain: CampusAILocalKnowledgeDomain
        var title: String
        var summary: String
        var sourceID: String
        var routeHint: String?
        var updatedAt: String?
        var baseScore: Int
    }

    static let defaultMaxResults = 12
    static let defaultCharacterBudget = 6_000

    static func search(
        query: String,
        context: CampusAIContextPayload,
        maxResults: Int = defaultMaxResults,
        characterBudget: Int = defaultCharacterBudget
    ) -> CampusAILocalRetrievalPayload {
        let trimmedQuery = query.nonEmptyTrimmed ?? query
        let candidates = buildCandidates(from: context)
        guard !candidates.isEmpty, maxResults > 0, characterBudget > 0 else {
            return .empty(query: trimmedQuery)
        }

        let scored = candidates.compactMap { candidate -> CampusAILocalKnowledgeResult? in
            let score = relevanceScore(candidate: candidate, query: trimmedQuery)
            guard score > 0 else { return nil }
            return CampusAILocalKnowledgeResult(
                id: stableID(domain: candidate.domain, sourceID: candidate.sourceID),
                domain: candidate.domain,
                title: candidate.title.clampedForAIContext(100),
                summary: candidate.summary.clampedForAIContext(520),
                sourceID: candidate.sourceID,
                routeHint: candidate.routeHint,
                updatedAt: candidate.updatedAt,
                score: score
            )
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.title < $1.title
        }

        return CampusAILocalRetrievalPayload(
            query: trimmedQuery,
            results: fit(scored, maxResults: maxResults, characterBudget: characterBudget)
        )
    }

    private static func buildCandidates(from context: CampusAIContextPayload) -> [Candidate] {
        var candidates: [Candidate] = []

        for (index, course) in context.timetable.today.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "今日课程：\(course.name)",
                summary: join([
                    "第\(periodText(course.periods))节",
                    weekdayText(course.dayOfWeek),
                    course.room.nonEmptyTrimmed,
                    course.teacher.nonEmptyTrimmed.map { "教师：\($0)" }
                ]),
                sourceID: "timetable.today.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                baseScore: 18
            ))
        }

        for (index, course) in context.timetable.currentWeek.prefix(40).enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "本周课程：\(course.name)",
                summary: join([
                    weekdayText(course.dayOfWeek),
                    "第\(periodText(course.periods))节",
                    course.room.nonEmptyTrimmed,
                    course.teacher.nonEmptyTrimmed.map { "教师：\($0)" },
                    course.weeks.isEmpty ? nil : "周次：\(course.weeks.map(String.init).joined(separator: ","))"
                ]),
                sourceID: "timetable.week.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                baseScore: 8
            ))
        }

        for (index, exam) in context.exams.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "考试：\(exam.name)",
                summary: join([exam.date, "\(exam.start)-\(exam.end)", exam.location.nonEmptyTrimmed]),
                sourceID: "exam.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                baseScore: 24
            ))
        }

        for (index, countdown) in context.countdowns.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "重要日期：\(countdown.title)",
                summary: "目标日期：\(countdown.targetDate)",
                sourceID: "countdown.\(index)",
                routeHint: CampusAIAcademicRouteID.customCountdowns.rawValue,
                baseScore: 18
            ))
        }

        for (index, reminder) in context.timetable.cellReminders.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "课表提醒：\(reminder.title)",
                summary: join([
                    "第\(reminder.week)周",
                    weekdayText(reminder.dayOfWeek),
                    "第\(reminder.period)\(reminder.endPeriod.map { "-\($0)" } ?? "")节",
                    reminder.location?.nonEmptyTrimmed,
                    reminder.note?.nonEmptyTrimmed
                ]),
                sourceID: "timetable.reminder.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                updatedAt: reminder.updatedAt,
                baseScore: 18
            ))
        }

        for (index, note) in context.timetable.courseNotes.enumerated() {
            candidates.append(candidate(
                domain: .schedule,
                title: "课程备注：\(note.courseName)",
                summary: note.text,
                sourceID: "course.note.\(index)",
                routeHint: CampusAIAcademicRouteID.examSchedule.rawValue,
                updatedAt: note.updatedAt,
                baseScore: 12
            ))
        }

        for (index, project) in context.learningWorkspace.projects.enumerated() {
            candidates.append(candidate(
                domain: .learning,
                title: "学习空间：\(project.title)",
                summary: join([project.kind.nonEmptyTrimmed, project.goal.nonEmptyTrimmed, project.isArchived ? "已归档" : "进行中"]),
                sourceID: "learning.project.\(index)",
                updatedAt: project.updatedAt,
                baseScore: 16
            ))
        }

        for (index, task) in context.learningWorkspace.tasks.enumerated() {
            candidates.append(candidate(
                domain: .learning,
                title: "学习任务：\(task.title)",
                summary: join([
                    task.category.nonEmptyTrimmed,
                    task.dueAt.map { "截止：\($0)" },
                    task.isCompleted ? "已完成" : "未完成",
                    task.note.nonEmptyTrimmed
                ]),
                sourceID: "learning.task.\(index)",
                updatedAt: task.updatedAt,
                baseScore: task.isCompleted ? 12 : 22
            ))
        }

        for (index, material) in context.learningWorkspace.materials.enumerated() {
            candidates.append(fileCandidate(
                domain: .learning,
                prefix: "学习资料",
                file: material,
                sourceID: "learning.material.\(index)",
                baseScore: 16
            ))
        }

        for (index, record) in context.learningWorkspace.studyRecords.enumerated() {
            candidates.append(candidate(
                domain: .learning,
                title: "学习记录：\(record.content)",
                summary: join([
                    record.category.nonEmptyTrimmed,
                    record.location.nonEmptyTrimmed,
                    "开始：\(record.startedAt)",
                    "时长：\(record.minutes) 分钟",
                    record.note.nonEmptyTrimmed
                ]),
                sourceID: "study.record.\(index)",
                baseScore: 12
            ))
        }

        for (index, grade) in context.grades.recentCourses.enumerated() {
            candidates.append(candidate(
                domain: .academics,
                title: "成绩：\(grade.name)",
                summary: join([grade.term.nonEmptyTrimmed, "成绩：\(grade.score)", "学分：\(grade.credit)", grade.type.nonEmptyTrimmed]),
                sourceID: "grade.course.\(index)",
                routeHint: CampusAIAcademicRouteID.grades.rawValue,
                baseScore: 18
            ))
        }

        for (index, ranking) in context.grades.rankings.enumerated() {
            let rankText = ranking.rank.map { "排名：\($0)" }
            let totalText = ranking.totalCount.map { "总人数：\($0)" }
            let percentileText = ranking.percentile.map { "百分位：\(Int(($0 * 100).rounded()))%" }
            candidates.append(candidate(
                domain: .academics,
                title: "成绩排名：\(ranking.term)",
                summary: join([ranking.range.nonEmptyTrimmed, ranking.metric.nonEmptyTrimmed, rankText, totalText, percentileText]),
                sourceID: "grade.ranking.\(index)",
                routeHint: CampusAIAcademicRouteID.gradeAnalytics.rawValue,
                baseScore: 20
            ))
        }

        for (index, plan) in context.teachingPlan.enumerated() {
            candidates.append(candidate(
                domain: .academics,
                title: "教学计划：\(plan.term)",
                summary: join(["总学分：\(plan.totalCredits)", plan.courses.prefix(12).joined(separator: "、")]),
                sourceID: "teaching.plan.\(index)",
                routeHint: CampusAIAcademicRouteID.teachingPlan.rawValue,
                baseScore: 16
            ))
        }

        if let trainingProgram = context.trainingProgram {
            candidates.append(candidate(
                domain: .academics,
                title: trainingProgram.title,
                summary: join([
                    trainingProgram.creditRequirements.prefix(8).joined(separator: "；"),
                    trainingProgram.sections.prefix(4).joined(separator: "；")
                ]),
                sourceID: "training.program",
                routeHint: CampusAIAcademicRouteID.trainingProgram.rawValue,
                baseScore: 18
            ))
        }

        for (index, target) in context.postgraduateAndCareer.postgraduateTargets.enumerated() {
            candidates.append(candidate(
                domain: .postgraduateCareer,
                title: "考研目标：\(join([target.school.nonEmptyTrimmed, target.unit.nonEmptyTrimmed, target.major.nonEmptyTrimmed], separator: " "))",
                summary: join([
                    "年份：\(target.examYear)",
                    target.direction.nonEmptyTrimmed,
                    target.subjects.nonEmptyTrimmed,
                    target.scoreAndPlanNote.nonEmptyTrimmed,
                    target.personalNote.nonEmptyTrimmed,
                    target.state.nonEmptyTrimmed
                ]),
                sourceID: "postgraduate.target.\(index)",
                updatedAt: target.updatedAt,
                baseScore: 18
            ))
        }

        for (index, task) in context.postgraduateAndCareer.careerTasks.enumerated() {
            candidates.append(candidate(
                domain: .postgraduateCareer,
                title: "职业任务：\(task.title)",
                summary: join([
                    task.dueAt.map { "截止：\($0)" },
                    task.isCompleted ? "已完成" : "未完成",
                    task.note.nonEmptyTrimmed
                ]),
                sourceID: "career.task.\(index)",
                updatedAt: task.updatedAt,
                baseScore: task.isCompleted ? 12 : 20
            ))
        }

        for (index, opportunity) in context.postgraduateAndCareer.opportunities.enumerated() {
            candidates.append(candidate(
                domain: .postgraduateCareer,
                title: "机会：\(opportunity.title)",
                summary: join([opportunity.organization.nonEmptyTrimmed, opportunity.status.nonEmptyTrimmed, opportunity.note.nonEmptyTrimmed]),
                sourceID: "career.opportunity.\(index)",
                updatedAt: opportunity.updatedAt,
                baseScore: 14
            ))
        }

        for (index, resume) in context.postgraduateAndCareer.resumes.enumerated() {
            candidates.append(fileCandidate(
                domain: .postgraduateCareer,
                prefix: "简历资料",
                file: resume,
                sourceID: "career.resume.\(index)",
                baseScore: 12
            ))
        }

        for (index, test) in context.honorsFitnessQuality.fitnessTests.enumerated() {
            candidates.append(candidate(
                domain: .fitnessSports,
                title: "体测：\(test.item)",
                summary: join([test.value.nonEmptyTrimmed, test.testedAt.nonEmptyTrimmed, test.note.nonEmptyTrimmed]),
                sourceID: "fitness.test.\(index)",
                routeHint: CampusAIAcademicRouteID.fitnessTestRecords.rawValue,
                baseScore: 18
            ))
        }

        for (index, honor) in context.honorsFitnessQuality.honors.enumerated() {
            candidates.append(fileCandidate(
                domain: .honorsQuality,
                prefix: "荣誉记录",
                file: honor,
                sourceID: "honor.\(index)",
                routeHint: CampusAIAcademicRouteID.honorRecords.rawValue,
                baseScore: 16
            ))
        }

        for (index, record) in context.honorsFitnessQuality.comprehensiveQualityRecords.enumerated() {
            candidates.append(candidate(
                domain: .honorsQuality,
                title: "综测记录：\(record.collegeName)",
                summary: join([
                    record.cohort.nonEmptyTrimmed,
                    record.academicStandardScore.map { "学业标准分：\($0)" },
                    record.officialQualityScore.map { "素质分：\($0)" },
                    record.officialCompositeScore.map { "综合分：\($0)" },
                    record.note.nonEmptyTrimmed
                ]),
                sourceID: "quality.record.\(index)",
                routeHint: CampusAIAcademicRouteID.comprehensiveQuality.rawValue,
                updatedAt: record.updatedAt,
                baseScore: 18
            ))
        }

        for (index, component) in context.honorsFitnessQuality.comprehensiveQualityComponents.enumerated() {
            candidates.append(candidate(
                domain: .honorsQuality,
                title: "综测项目：\(component.component)",
                summary: join([
                    component.collegeName.nonEmptyTrimmed,
                    component.cohort.nonEmptyTrimmed,
                    component.rawScore.map { "原始分：\($0)" },
                    component.officialStandardScore.map { "标准分：\($0)" },
                    component.materialReady ? "材料已准备" : "材料未标记完成",
                    component.note.nonEmptyTrimmed
                ]),
                sourceID: "quality.component.\(index)",
                routeHint: CampusAIAcademicRouteID.comprehensiveQuality.rawValue,
                updatedAt: component.updatedAt,
                baseScore: 16
            ))
        }

        for (index, evidence) in context.honorsFitnessQuality.comprehensiveQualityEvidence.enumerated() {
            candidates.append(fileCandidate(
                domain: .honorsQuality,
                prefix: "综测证明",
                file: evidence,
                sourceID: "quality.evidence.\(index)",
                routeHint: CampusAIAcademicRouteID.comprehensiveQuality.rawValue,
                baseScore: 14
            ))
        }

        for (index, entry) in context.medicalLedger.entries.enumerated() {
            candidates.append(candidate(
                domain: .medical,
                title: "医疗台账：\(entry.hospitalName.nonEmptyTrimmed ?? "就诊记录")",
                summary: join([
                    entry.visitDate.nonEmptyTrimmed,
                    entry.department.nonEmptyTrimmed,
                    entry.scenario.nonEmptyTrimmed,
                    "费用：\(entry.totalExpense)",
                    entry.estimatedReimbursement.map { "预计报销：\($0)" },
                    entry.actualReimbursement.map { "实际报销：\($0)" },
                    entry.status.nonEmptyTrimmed,
                    entry.reimbursementDeadline.map { "截止：\($0)" },
                    entry.materials.isEmpty ? nil : "材料：\(entry.materials.joined(separator: "、"))",
                    entry.note.nonEmptyTrimmed
                ]),
                sourceID: "medical.entry.\(index)",
                routeHint: CampusAIAcademicRouteID.medicalLedger.rawValue,
                updatedAt: entry.updatedAt,
                baseScore: 18
            ))
        }

        for (index, post) in context.communityCache.posts.enumerated() {
            candidates.append(candidate(
                domain: .community,
                title: "社区：\(post.title)",
                summary: join([
                    post.category,
                    post.body.nonEmptyTrimmed,
                    "评论 \(post.commentCount)",
                    "点赞 \(post.likeCount)",
                    post.imageCount > 0 ? "含 \(post.imageCount) 张图片" : nil
                ]),
                sourceID: "community.post.\(index)",
                updatedAt: post.updatedAt.nonEmptyTrimmed ?? post.createdAt,
                baseScore: 8
            ))
        }

        return candidates.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func candidate(
        domain: CampusAILocalKnowledgeDomain,
        title: String,
        summary: String,
        sourceID: String,
        routeHint: String? = nil,
        updatedAt: String? = nil,
        baseScore: Int
    ) -> Candidate {
        Candidate(
            domain: domain,
            title: title,
            summary: summary,
            sourceID: sourceID,
            routeHint: routeHint,
            updatedAt: updatedAt,
            baseScore: baseScore
        )
    }

    private static func fileCandidate(
        domain: CampusAILocalKnowledgeDomain,
        prefix: String,
        file: CampusAIFileMetadataContext,
        sourceID: String,
        routeHint: String? = nil,
        baseScore: Int
    ) -> Candidate {
        candidate(
            domain: domain,
            title: "\(prefix)：\(file.title)",
            summary: join([
                file.category.nonEmptyTrimmed,
                file.fileType.nonEmptyTrimmed,
                file.note.nonEmptyTrimmed
            ]),
            sourceID: sourceID,
            routeHint: routeHint,
            updatedAt: file.updatedAt,
            baseScore: baseScore
        )
    }

    private static func relevanceScore(candidate: Candidate, query: String) -> Int {
        let normalizedQuery = query.lowercased()
        let haystack = "\(candidate.title)\n\(candidate.summary)".lowercased()
        var score = candidate.baseScore

        if haystack.contains(normalizedQuery), normalizedQuery.count >= 2 {
            score += 36
        }

        for keyword in candidate.domain.intentKeywords where normalizedQuery.contains(keyword.lowercased()) {
            score += 18
        }

        for domain in CampusAILocalKnowledgeDomain.allCases where domain != candidate.domain {
            if domain.intentKeywords.contains(where: { normalizedQuery.contains($0.lowercased()) }) {
                score -= 4
            }
        }

        for token in queryTokens(query) where token.count >= 2 {
            if haystack.contains(token.lowercased()) {
                score += min(14, token.count + 4)
            }
        }

        return score
    }

    private static func fit(
        _ results: [CampusAILocalKnowledgeResult],
        maxResults: Int,
        characterBudget: Int
    ) -> [CampusAILocalKnowledgeResult] {
        var remaining = characterBudget
        var fitted: [CampusAILocalKnowledgeResult] = []
        for result in results.prefix(maxResults) {
            var next = result
            let fixedCost = next.title.count + next.domain.title.count + next.sourceID.count + 32
            let totalCost = fixedCost + next.summary.count
            if totalCost > remaining {
                let summaryLimit = remaining - fixedCost
                guard summaryLimit >= 80 else { break }
                next.summary = next.summary.clampedForAIContext(summaryLimit)
            }
            let cost = fixedCost + next.summary.count
            guard cost <= remaining else { break }
            fitted.append(next)
            remaining -= cost
        }
        return fitted
    }

    private static func queryTokens(_ value: String) -> [String] {
        let separated = value
            .lowercased()
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: " ", options: .regularExpression)
        var tokens = separated.split(separator: " ").map(String.init)
        let important = CampusAILocalKnowledgeDomain.allCases.flatMap(\.intentKeywords)
        tokens.append(contentsOf: important.filter { value.contains($0) })
        return Array(Set(tokens))
    }

    private static func join(_ values: [String?], separator: String = "，") -> String {
        values.compactMap { $0?.nonEmptyTrimmed }.joined(separator: separator)
    }

    private static func weekdayText(_ day: Int) -> String {
        guard (1...7).contains(day) else { return "星期\(day)" }
        return ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1]
    }

    private static func periodText(_ periods: [Int]) -> String {
        periods.isEmpty ? "未知" : periods.map(String.init).joined(separator: ",")
    }

    private static func stableID(domain: CampusAILocalKnowledgeDomain, sourceID: String) -> String {
        "\(domain.rawValue)-\(sourceID)"
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
    }
}
import Foundation
