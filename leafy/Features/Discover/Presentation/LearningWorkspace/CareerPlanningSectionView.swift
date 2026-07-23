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

struct CareerPlanningSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.leafyLanguage) private var leafyLanguage

    @Query(sort: \CareerResumeDocument.updatedAt, order: .reverse) private var resumes: [CareerResumeDocument]
    @Query(sort: \CareerTask.createdAt, order: .reverse) private var tasks: [CareerTask]
    @Query(sort: \CareerOpportunity.updatedAt, order: .reverse) private var opportunities: [CareerOpportunity]

    @State private var isResumeImporterPresented = false
    @State private var resumeBeingReplaced: CareerResumeDocument?
    @State private var editingResume: CareerResumeDocument?
    @State private var previewURL: CareerPreviewURL?
    @State private var shareItem: CareerShareItem?
    @State private var editingTask: CareerTask?
    @State private var isTaskEditorPresented = false
    @State private var editingOpportunity: CareerOpportunity?
    @State private var isOpportunityEditorPresented = false
    @State private var resumePendingDeletion: CareerResumeDocument?
    @State private var alertMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    private var sortedTasks: [CareerTask] {
        tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            switch (lhs.dueAt, rhs.dueAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate < rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle("职业规划", subtitle: "简历、待办和岗位链接先保存在本机，方便把求职、升学材料集中管理。")

            resumeSection
            tasksSection
            opportunitiesSection
            suggestionsSection
        }
        .fileImporter(
            isPresented: $isResumeImporterPresented,
            allowedContentTypes: CareerDocumentFileStore.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleResumeImport
        )
        .sheet(item: $editingResume) { resume in
            CareerResumeEditorSheet(resume: resume)
        }
        .sheet(item: $previewURL) { item in
            CareerDocumentPreviewSheet(url: item.url)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .sheet(isPresented: $isTaskEditorPresented) {
            CareerTaskEditorSheet(task: nil) { task in
                insertTask(task)
            }
        }
        .sheet(item: $editingTask) { task in
            CareerTaskEditorSheet(task: task) { _ in
                saveContext()
                operationAlert = .success(L10n.text("任务已保存！", language: leafyLanguage))
            }
        }
        .sheet(isPresented: $isOpportunityEditorPresented) {
            CareerOpportunityEditorSheet(opportunity: nil) { opportunity in
                insertOpportunity(opportunity)
            }
        }
        .sheet(item: $editingOpportunity) { opportunity in
            CareerOpportunityEditorSheet(opportunity: opportunity) { _ in
                saveContext()
                operationAlert = .success(L10n.text("岗位已保存！", language: leafyLanguage))
            }
        }
        .alert("职业规划操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("删除个人简历？", isPresented: Binding(
            get: { resumePendingDeletion != nil },
            set: { if !$0 { resumePendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let resume = resumePendingDeletion {
                    deleteResume(resume)
                }
                resumePendingDeletion = nil
            }
        } message: {
            Text("删除后会同时移除本地简历文件，无法恢复。")
        }
        .leafyOperationAlert($operationAlert)
    }

    private var resumeSection: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: AppSpacing.compact) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("个人简历")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text("PDF、Word 和图片会导入到本机私有目录，不会上传到云端。")
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppSpacing.micro)

                    if !resumes.isEmpty {
                        CareerSectionAddButton(title: "添加简历", systemName: "plus") {
                            beginResumeImport()
                        }
                    }
                }

                if resumes.isEmpty {
                    CareerEmptyResumeRow {
                        beginResumeImport()
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(resumes.enumerated()), id: \.element.id) { index, resume in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            CareerResumeRow(
                                resume: resume,
                                previewAction: { preview(resume) },
                                editAction: { editingResume = resume },
                                replaceAction: { beginResumeImport(replacing: resume) },
                                shareAction: { share(resume) },
                                deleteAction: { resumePendingDeletion = resume }
                            )
                        }
                    }
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: "求职/升学任务")
                Spacer()
                CareerSectionAddButton(title: "添加任务", systemName: "plus") {
                    isTaskEditorPresented = true
                }
            }

            AcademicDetailCard {
                if tasks.isEmpty {
                    ContentUnavailableView("暂无任务", systemImage: "checklist", description: Text("可以记录改简历、投递、联系导师或面试准备。"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.compact)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            CareerTaskRow(
                                task: task,
                                toggleAction: { toggleTask(task) },
                                editAction: { editingTask = task },
                                deleteAction: { deleteTask(task) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var opportunitiesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: "岗位/链接收藏")
                Spacer()
                CareerSectionAddButton(title: "添加岗位", systemName: "plus") {
                    isOpportunityEditorPresented = true
                }
            }

            AcademicDetailCard {
                if opportunities.isEmpty {
                    ContentUnavailableView("暂无收藏", systemImage: "briefcase", description: Text("保存岗位、宣讲会、导师主页或申请入口。"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.compact)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(opportunities.enumerated()), id: \.element.id) { index, opportunity in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            CareerOpportunityRow(
                                opportunity: opportunity,
                                openAction: { openOpportunity(opportunity) },
                                editAction: { editingOpportunity = opportunity },
                                deleteAction: { deleteOpportunity(opportunity) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var suggestionsSection: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("后续可扩展", systemImage: "sparkles")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                VStack(alignment: .leading, spacing: 9) {
                    CareerSuggestionRow(icon: "target", title: "岗位关键词匹配", detail: "用岗位描述检查简历关键词覆盖。")
                    CareerSuggestionRow(icon: "rectangle.grid.1x2", title: "投递进度看板", detail: "按关注、已投递、面试中和结束汇总进度。")
                    CareerSuggestionRow(icon: "person.crop.rectangle.stack", title: "面试准备清单", detail: "沉淀项目经历、常见问题和复盘记录。")
                    CareerSuggestionRow(icon: "calendar.badge.clock", title: "宣讲会日历", detail: "把宣讲会、网申截止和面试时间放进日程。")
                    CareerSuggestionRow(icon: "building.2", title: "目标行业收藏", detail: "按城市、行业和单位类型整理长期目标。")
                }
            }
        }
    }

    private func handleResumeImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                resumeBeingReplaced = nil
                return
            }
            let stored = try CareerDocumentFileStore.importFile(from: url)

            if let resumeBeingReplaced {
                let previousLocalFilename = resumeBeingReplaced.localFilename
                resumeBeingReplaced.originalFilename = url.lastPathComponent
                resumeBeingReplaced.localFilename = stored.localFilename
                resumeBeingReplaced.contentTypeIdentifier = stored.contentTypeIdentifier
                resumeBeingReplaced.updatedAt = Date()

                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    try? CareerDocumentFileStore.deleteFile(named: stored.localFilename)
                    throw error
                }

                do {
                    try CareerDocumentFileStore.deleteFile(named: previousLocalFilename)
                    operationAlert = .success(L10n.text("简历文件已替换！", language: leafyLanguage))
                } catch {
                    alertMessage = "新简历已保存，但旧文件未能清理：\(error.localizedDescription)"
                }
            } else {
                let title = url.deletingPathExtension().lastPathComponent
                let resume = CareerResumeDocument(
                    title: title.isEmpty ? "个人简历" : title,
                    originalFilename: url.lastPathComponent,
                    localFilename: stored.localFilename,
                    contentTypeIdentifier: stored.contentTypeIdentifier
                )
                modelContext.insert(resume)

                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    try? CareerDocumentFileStore.deleteFile(named: stored.localFilename)
                    throw error
                }

                Task { @MainActor in
                    await Task.yield()
                    editingResume = resume
                }
            }
            resumeBeingReplaced = nil
        } catch {
            resumeBeingReplaced = nil
            alertMessage = error.localizedDescription
        }
    }

    private func beginResumeImport(replacing resume: CareerResumeDocument? = nil) {
        resumeBeingReplaced = resume
        isResumeImporterPresented = true
    }

    private func preview(_ resume: CareerResumeDocument) {
        guard let url = CareerDocumentFileStore.fileURL(for: resume) else {
            alertMessage = "无法找到本地简历文件。"
            return
        }
        previewURL = CareerPreviewURL(url: url)
    }

    private func share(_ resume: CareerResumeDocument) {
        guard let url = CareerDocumentFileStore.fileURL(for: resume) else {
            alertMessage = "无法找到本地简历文件。"
            return
        }
        shareItem = CareerShareItem(url: url)
    }

    private func deleteResume(_ resume: CareerResumeDocument) {
        do {
            try CareerDocumentFileStore.deleteFile(named: resume.localFilename)
            modelContext.delete(resume)
            try modelContext.save()
            operationAlert = .success(L10n.text("简历已删除！", language: leafyLanguage))
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func insertTask(_ task: CareerTask) {
        modelContext.insert(task)
        saveContext()
        operationAlert = .success(L10n.text("任务已添加！", language: leafyLanguage))
    }

    private func toggleTask(_ task: CareerTask) {
        task.isCompleted.toggle()
        task.updatedAt = Date()
        saveContext()
    }

    private func deleteTask(_ task: CareerTask) {
        modelContext.delete(task)
        saveContext()
        operationAlert = .success(L10n.text("任务已删除！", language: leafyLanguage))
    }

    private func insertOpportunity(_ opportunity: CareerOpportunity) {
        modelContext.insert(opportunity)
        saveContext()
        operationAlert = .success(L10n.text("岗位已添加！", language: leafyLanguage))
    }

    private func openOpportunity(_ opportunity: CareerOpportunity) {
        guard let url = opportunity.validURL else {
            alertMessage = "链接格式无效。"
            return
        }
        openURL(url)
    }

    private func deleteOpportunity(_ opportunity: CareerOpportunity) {
        modelContext.delete(opportunity)
        saveContext()
        operationAlert = .success(L10n.text("岗位已删除！", language: leafyLanguage))
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct CareerPreviewURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CareerShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct CareerSectionAddButton: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13 * leafyControlScale, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .padding(.horizontal, 12 * leafyControlScale)
                .frame(height: 34 * leafyControlScale)
                .leafyCapsuleChipSurface(isSelected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct CareerResumeRow: View {
    let resume: CareerResumeDocument
    let previewAction: () -> Void
    let editAction: () -> Void
    let replaceAction: () -> Void
    let shareAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: previewAction) {
                HStack(alignment: .center, spacing: 10) {
                    CareerDocumentThumbnail(document: resume)
                        .frame(width: 40, height: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(resume.title)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)

                        Text("\(resume.displayType) · \(resume.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)

                        if !resume.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(resume.note)
                                .microCaption()
                                .foregroundStyle(AppTheme.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("预览简历")

            Menu {
                Button(action: editAction) {
                    Label("编辑", systemImage: "pencil")
                }
                Button(action: replaceAction) {
                    Label("替换", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(action: shareAction) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: deleteAction) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.softFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多简历操作")
        }
        .padding(.vertical, 2)
    }
}

private struct CareerEmptyResumeRow: View {
    let uploadAction: () -> Void

    var body: some View {
        Button(action: uploadAction) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 38, height: 44)
                    .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("还没有导入简历")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("导入当前简历，可随时替换、备注和预览。")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("导入")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .leafyCapsuleChipSurface(isSelected: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("导入简历")
        .padding(.vertical, 2)
    }
}

private struct CareerDocumentThumbnail: View {
    let document: CareerResumeDocument

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppTheme.softFill)

            Image(systemName: document.thumbnailIcon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(document.thumbnailColor)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }
}

private struct CareerTaskRow: View {
    let task: CareerTask
    let toggleAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.micro) {
            Button(action: toggleAction) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(task.isCompleted ? AppTheme.accentEmphasis : AppTheme.tertiaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "标记为未完成" : "标记为完成")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .leafyHeadline()
                    .foregroundStyle(task.isCompleted ? AppTheme.secondaryText : AppTheme.primaryText)
                    .strikethrough(task.isCompleted)
                    .lineLimit(2)

                if let dueAt = task.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if !task.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.note)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CareerRowActionMenu(
                editLabel: "编辑任务",
                deleteLabel: "删除任务",
                editAction: editAction,
                deleteAction: deleteAction
            )
        }
        .padding(.vertical, 4)
    }
}

private struct CareerOpportunityRow: View {
    let opportunity: CareerOpportunity
    let openAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.micro) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis)
                .frame(width: 30, height: 30)
                .background(AppTheme.softFill, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(opportunity.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)

                    Text(opportunity.status.rawValue)
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.accentSoft, in: Capsule())
                }

                if !opportunity.organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(opportunity.organization)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if !opportunity.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(opportunity.note)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                }

                if opportunity.validURL != nil {
                    Button(action: openAction) {
                        Label("打开链接", systemImage: "arrow.up.right")
                            .microCaption()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accentEmphasis)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CareerRowActionMenu(
                editLabel: "编辑岗位",
                deleteLabel: "删除岗位",
                editAction: editAction,
                deleteAction: deleteAction
            )
        }
        .padding(.vertical, 4)
    }
}

private struct CareerRowActionMenu: View {
    let editLabel: String
    let deleteLabel: String
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        Menu {
            Button(action: editAction) {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive, action: deleteAction) {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 28, height: 28)
                .background(AppTheme.softFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(editLabel) / \(deleteLabel)")
    }

    private var systemName: String {
        "ellipsis"
    }
}

private struct CareerSuggestionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accentEmphasis)
                .frame(width: 28, height: 28)
                .background(AppTheme.softFill, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CareerResumeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var resume: CareerResumeDocument

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $resume.title)
                    TextField("备注", text: $resume.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    LabeledContent("文件", value: resume.originalFilename)
                    LabeledContent("类型", value: resume.displayType)
                } footer: {
                    Text("文件本体保存在本机私有目录，仅当前 App 可访问。")
                }
            }
            .navigationTitle("编辑简历")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        resume.updatedAt = Date()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct CareerTaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: CareerTask?
    let onSave: (CareerTask) -> Void

    @State private var title: String
    @State private var note: String
    @State private var hasDueDate: Bool
    @State private var dueAt: Date

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(task: CareerTask?, onSave: @escaping (CareerTask) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? "")
        _note = State(initialValue: task?.note ?? "")
        _hasDueDate = State(initialValue: task?.dueAt != nil)
        _dueAt = State(initialValue: task?.dueAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称", text: $title)
                    Toggle("设置截止日期", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("截止日期", selection: $dueAt, displayedComponents: .date)
                    }
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(task == nil ? "添加任务" : "编辑任务")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedDueAt = hasDueDate ? dueAt : nil
        if let task {
            task.title = trimmedTitle
            task.note = trimmedNote
            task.dueAt = selectedDueAt
            task.updatedAt = Date()
            onSave(task)
        } else {
            onSave(CareerTask(title: trimmedTitle, note: trimmedNote, dueAt: selectedDueAt))
        }
        dismiss()
    }
}

private struct CareerOpportunityEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let opportunity: CareerOpportunity?
    let onSave: (CareerOpportunity) -> Void

    @State private var title: String
    @State private var organization: String
    @State private var urlString: String
    @State private var status: CareerOpportunityStatus
    @State private var note: String

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(opportunity: CareerOpportunity?, onSave: @escaping (CareerOpportunity) -> Void) {
        self.opportunity = opportunity
        self.onSave = onSave
        _title = State(initialValue: opportunity?.title ?? "")
        _organization = State(initialValue: opportunity?.organization ?? "")
        _urlString = State(initialValue: opportunity?.urlString ?? "")
        _status = State(initialValue: opportunity?.status ?? .watching)
        _note = State(initialValue: opportunity?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("岗位或链接标题", text: $title)
                    TextField("组织/公司", text: $organization)
                    TextField("链接", text: $urlString)
                        .leafyDisableAutocapitalization()
                        .keyboardType(.URL)
                }

                Section {
                    Picker("状态", selection: $status) {
                        ForEach(CareerOpportunityStatus.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(opportunity == nil ? "添加岗位" : "编辑岗位")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrganization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let opportunity {
            opportunity.title = trimmedTitle
            opportunity.organization = trimmedOrganization
            opportunity.urlString = trimmedURL
            opportunity.status = status
            opportunity.note = trimmedNote
            opportunity.updatedAt = Date()
            onSave(opportunity)
        } else {
            onSave(CareerOpportunity(
                title: trimmedTitle,
                organization: trimmedOrganization,
                urlString: trimmedURL,
                statusRawValue: status.rawValue,
                note: trimmedNote
            ))
        }
        dismiss()
    }
}

private struct CareerDocumentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    @State private var shareItem: CareerShareItem?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            CareerDocumentPreview(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.deletingPathExtension().lastPathComponent)
                .leafyInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .leafyLeading) {
                        Button("关闭") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .leafyTrailing) {
                        Button("分享", action: share)
                            .fontWeight(.semibold)
                    }
                }
                .sheet(item: $shareItem) { item in
                    ShareSheet(activityItems: [item.url])
                }
                .alert("职业规划操作失败", isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )) {
                    Button("知道了", role: .cancel) {}
                } message: {
                    Text(alertMessage ?? "")
                }
        }
    }

    private func share() {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            alertMessage = "无法找到本地简历文件。"
            return
        }
        shareItem = CareerShareItem(url: url)
    }
}

#if canImport(UIKit)
private struct CareerDocumentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#else
private typealias CareerDocumentPreview = LeafyDocumentPreview
#endif

enum CareerDocumentFileStore {
    struct StoredFile {
        let localFilename: String
        let contentTypeIdentifier: String
    }

    static let allowedContentTypes: [UTType] = [
        .pdf,
        .image,
        .plainText,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "docx") ?? .data
    ]

    static func importFile(from sourceURL: URL) throws -> StoredFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let extensionText = sourceURL.pathExtension
        let localFilename = extensionText.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(extensionText)"
        let destinationURL = directoryURL.appendingPathComponent(localFilename)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let contentType = UTType(filenameExtension: extensionText)
            ?? sourceURL.resourceContentType
            ?? .data
        return StoredFile(
            localFilename: localFilename,
            contentTypeIdentifier: contentType.identifier
        )
    }

    static func fileURL(for document: CareerResumeDocument) -> URL? {
        let url = directoryURL.appendingPathComponent(document.localFilename)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    static func deleteFile(named filename: String) throws {
        let url = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func deleteAllFiles() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directoryURL)
        }
    }

    private static var directoryURL: URL {
        if AppRuntimeEnvironment.isRunningUnitTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("LeafyCareerDocumentsTests", isDirectory: true)
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CareerDocuments", isDirectory: true)
    }
}

private extension URL {
    var resourceContentType: UTType? {
        (try? resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }
}

private extension CareerResumeDocument {
    var contentType: UTType? {
        UTType(contentTypeIdentifier)
    }

    var displayType: String {
        guard let contentType else { return "文件" }
        if contentType.conforms(to: .pdf) { return "PDF" }
        if contentType.conforms(to: .image) { return "图片" }
        if contentType.conforms(to: .plainText) { return "文本" }
        if contentType.identifier.contains("word") || originalFilename.lowercased().hasSuffix(".docx") || originalFilename.lowercased().hasSuffix(".doc") {
            return "Word"
        }
        return "文件"
    }

    var thumbnailIcon: String {
        guard let contentType else { return "doc.fill" }
        if contentType.conforms(to: .pdf) { return "doc.richtext.fill" }
        if contentType.conforms(to: .image) { return "photo.fill" }
        if displayType == "Word" { return "doc.text.fill" }
        return "doc.fill"
    }

    var thumbnailColor: Color {
        guard let contentType else { return AppTheme.accentEmphasis }
        if contentType.conforms(to: .pdf) { return AppTheme.warning }
        if contentType.conforms(to: .image) { return AppTheme.accentEmphasis }
        return AppTheme.primaryText
    }
}

private extension CareerOpportunity {
    var status: CareerOpportunityStatus {
        get { CareerOpportunityStatus(rawValue: statusRawValue) ?? .watching }
        set { statusRawValue = newValue.rawValue }
    }

    var validURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}
