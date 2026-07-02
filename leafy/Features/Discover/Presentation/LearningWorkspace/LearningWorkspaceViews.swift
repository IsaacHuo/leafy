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

private enum LearningProjectDeletionText {
    static let dialogTitle = "删除学习项目？"
    static let dialogMessage = "可以只删除项目并把内容移到“其他”，也可以连同资料、任务和学习记录一起删除。"
    static let keepContentsAction = "保留内容"
    static let deleteAllAction = "全部删除"
    static let fullDeleteTitle = "同时删除项目和内容？"
    static let fullDeleteMessage = "继续前请先导出需要保留的学习资料。确认后会删除项目内资料文件、任务和学习记录，无法恢复。"
    static let cancelAction = "取消"
    static let keepContentsSuccess = "项目已删除，内容已移到其他。"
    static let deleteAllSuccess = "项目和内容已删除！"
}

struct LearningWorkspaceView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let openRoute: (AcademicDetailRoute) -> Void

    @Query(sort: \LearningProject.updatedAt, order: .reverse) private var projects: [LearningProject]
    @Query(sort: \LearningMaterialDocument.updatedAt, order: .reverse) private var materials: [LearningMaterialDocument]
    @Query(sort: \LearningProjectTask.updatedAt, order: .reverse) private var tasks: [LearningProjectTask]
    @Query(sort: \StudyTimeRecord.startedAt, order: .reverse) private var records: [StudyTimeRecord]

    @State private var isProjectEditorPresented = false
    @State private var editingProject: LearningProject?
    @State private var projectPendingDeletion: LearningProject?
    @State private var projectPendingFullDeletion: LearningProject?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var workspaceIndex = LearningWorkspaceIndex.empty
    @State private var workspaceIndexSignature = LearningWorkspaceIndexSignature()

    private var activeProjects: [LearningProject] {
        projects.filter { !$0.isArchived }
    }

    private var archivedProjects: [LearningProject] {
        projects.filter(\.isArchived)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            LeafySectionTitle(
                "学习相关",
                subtitle: "固定空间收纳四六级、考试资料和课件，自定义项目用于长期学习目标；资料可导入也可导出。"
            )

            fixedSpacesSection(index: workspaceIndex)
            customProjectsSection(index: workspaceIndex)
            archivedProjectsSection(index: workspaceIndex)
        }
        .onAppear(perform: refreshWorkspaceIndexIfNeeded)
        .onChange(of: LearningWorkspaceIndexSignature(materials: materials, tasks: tasks, records: records)) { _, _ in
            refreshWorkspaceIndexIfNeeded()
        }
        .sheet(isPresented: $isProjectEditorPresented) {
            LearningProjectEditorSheet(project: nil) { draft in
                insertProject(draft)
            }
        }
        .sheet(item: $editingProject) { project in
            LearningProjectEditorSheet(project: project) { draft in
                update(project, with: draft)
            }
        }
        .confirmationDialog(
            LearningProjectDeletionText.dialogTitle,
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LearningProjectDeletionText.keepContentsAction) {
                if let project = projectPendingDeletion {
                    deleteProjectKeepingContents(project)
                }
                projectPendingDeletion = nil
            }
            Button(LearningProjectDeletionText.deleteAllAction, role: .destructive) {
                projectPendingFullDeletion = projectPendingDeletion
                projectPendingDeletion = nil
            }
            Button(LearningProjectDeletionText.cancelAction, role: .cancel) {}
        } message: {
            Text(LearningProjectDeletionText.dialogMessage)
        }
        .confirmationDialog(
            LearningProjectDeletionText.fullDeleteTitle,
            isPresented: Binding(
                get: { projectPendingFullDeletion != nil },
                set: { if !$0 { projectPendingFullDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LearningProjectDeletionText.deleteAllAction, role: .destructive) {
                if let project = projectPendingFullDeletion {
                    deleteProjectAndContents(project)
                }
                projectPendingFullDeletion = nil
            }
            Button(LearningProjectDeletionText.cancelAction, role: .cancel) {}
        } message: {
            Text(LearningProjectDeletionText.fullDeleteMessage)
        }
        .leafyOperationAlert($operationAlert)
    }

    private func fixedSpacesSection(index workspaceIndex: LearningWorkspaceIndex) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AcademicDetailSectionHeader(title: "固定学习空间")
            AcademicDetailCard {
                VStack(spacing: 0) {
                    LearningWorkspaceTableHeader(title: "空间", durationTitle: "本周", trailingWidth: 8)
                    AcademicDetailDivider()
                    ForEach(Array(LearningMaterialCategory.fixedSpaceOrder.enumerated()), id: \.element.id) { index, category in
                        if index > 0 {
                            AcademicDetailDivider()
                        }
                        LearningWorkspaceFixedSpaceRow(
                            category: category,
                            summary: workspaceIndex.summary(for: .fixed(category))
                        ) {
                            openRoute(.learningWorkspace(.fixed(category)))
                        }
                    }
                }
            }
        }
    }

    private func customProjectsSection(index workspaceIndex: LearningWorkspaceIndex) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: "自定义学习项目")
                Spacer()
                CareerSectionAddButton(title: "新建项目", systemName: "plus") {
                    isProjectEditorPresented = true
                }
            }

            if activeProjects.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("暂无自定义项目", systemImage: "folder.badge.plus", description: Text("可以为高数期末、蓝桥杯备赛或专业课复习创建独立项目。"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.compact)
                }
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        LearningWorkspaceTableHeader(title: "项目", durationTitle: "累计", trailingWidth: 28)
                        AcademicDetailDivider()
                        ForEach(Array(activeProjects.enumerated()), id: \.element.id) { index, project in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            LearningProjectRow(
                                project: project,
                                summary: workspaceIndex.summary(for: .project(project.id)),
                                openAction: { openRoute(.learningWorkspace(.project(project.id))) },
                                editAction: { editingProject = project },
                                deleteAction: { projectPendingDeletion = project }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func archivedProjectsSection(index workspaceIndex: LearningWorkspaceIndex) -> some View {
        if !archivedProjects.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                AcademicDetailSectionHeader(title: "已归档项目")
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        LearningWorkspaceTableHeader(title: "项目", durationTitle: "累计", trailingWidth: 28)
                        AcademicDetailDivider()
                        ForEach(Array(archivedProjects.enumerated()), id: \.element.id) { index, project in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            LearningProjectRow(
                                project: project,
                                summary: workspaceIndex.summary(for: .project(project.id)),
                                openAction: { openRoute(.learningWorkspace(.project(project.id))) },
                                editAction: { editingProject = project },
                                deleteAction: { projectPendingDeletion = project }
                            )
                        }
                    }
                }
            }
        }
    }

    private func refreshWorkspaceIndexIfNeeded() {
        let signature = LearningWorkspaceIndexSignature(materials: materials, tasks: tasks, records: records)
        guard signature != workspaceIndexSignature else { return }
        workspaceIndexSignature = signature
        workspaceIndex = LearningWorkspaceIndex.make(materials: materials, tasks: tasks, records: records)
    }

    private func insertProject(_ draft: LearningProjectDraft) {
        modelContext.insert(LearningProject(
            title: draft.title,
            kindRawValue: draft.kind.rawValue,
            goal: draft.goal,
            isArchived: draft.isArchived
        ))
        save(successMessage: "项目已创建！")
    }

    private func update(_ project: LearningProject, with draft: LearningProjectDraft) {
        project.title = draft.title
        project.kind = draft.kind
        project.goal = draft.goal
        project.isArchived = draft.isArchived
        project.updatedAt = Date()
        save(successMessage: "项目已保存！")
    }

    private func deleteProjectKeepingContents(_ project: LearningProject) {
        do {
            try LearningProjectContentRelocation.deleteProjectKeepingContents(
                project,
                materials: materials,
                tasks: tasks,
                records: records,
                modelContext: modelContext
            )
            operationAlert = .success(LearningProjectDeletionText.keepContentsSuccess)
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func deleteProjectAndContents(_ project: LearningProject) {
        do {
            try LearningProjectContentRelocation.deleteProjectAndContents(
                project,
                materials: materials,
                tasks: tasks,
                records: records,
                modelContext: modelContext
            )
            operationAlert = .success(LearningProjectDeletionText.deleteAllSuccess)
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func save(successMessage: String) {
        do {
            try modelContext.save()
            operationAlert = .success(L10n.text(successMessage, language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

private struct LearningMaterialRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let material: LearningMaterialDocument
    let previewAction: () -> Void
    let editAction: () -> Void
    let shareAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: previewAction) {
                HStack(alignment: .center, spacing: 10) {
                    LearningMaterialThumbnail(material: material)
                        .frame(width: 40, height: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(material.title)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)

                        Text(metadataText)
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)

                        if !detailText.isEmpty {
                            Text(detailText)
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
            .accessibilityLabel(L10n.text("预览学习资料", language: leafyLanguage))

            Menu {
                Button(action: editAction) {
                    Label("编辑", systemImage: "pencil")
                }
                Button(action: shareAction) {
                    Label("导出", systemImage: "square.and.arrow.up")
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
            .accessibilityLabel(L10n.text("更多学习资料操作", language: leafyLanguage))
        }
        .padding(.vertical, 6)
    }

    private var metadataText: String {
        [
            L10n.text(material.category.rawValue, language: leafyLanguage),
            L10n.text(material.displayType, language: leafyLanguage),
            material.updatedAt.formatted(date: .abbreviated, time: .shortened)
        ].joined(separator: " · ")
    }

    private var detailText: String {
        let courseName = material.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = material.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !courseName.isEmpty && !note.isEmpty {
            return "\(courseName) · \(note)"
        }
        return courseName.isEmpty ? note : courseName
    }
}

private struct LearningMaterialThumbnail: View {
    let material: LearningMaterialDocument

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppTheme.softFill)

            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(tint)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

    private var icon: String {
        switch material.displayType {
        case "PDF":
            return "doc.richtext.fill"
        case "图片":
            return "photo.fill"
        case "Word", "文本", "RTF":
            return "doc.text.fill"
        case "PPT":
            return "rectangle.on.rectangle.angled"
        case "表格":
            return "tablecells.fill"
        default:
            return "doc.fill"
        }
    }

    private var tint: Color {
        switch material.displayType {
        case "PDF", "PPT":
            return AppTheme.warning
        case "图片":
            return AppTheme.accentEmphasis
        case "表格":
            return AppTheme.accent
        default:
            return AppTheme.primaryText
        }
    }
}

private struct LearningMaterialEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    @Bindable var material: LearningMaterialDocument
    let lockedCategory: LearningMaterialCategory?

    init(material: LearningMaterialDocument, lockedCategory: LearningMaterialCategory? = nil) {
        self.material = material
        self.lockedCategory = lockedCategory
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.text("资料标题", language: leafyLanguage), text: $material.title)
                    if let lockedCategory {
                        LabeledContent(L10n.text("分类", language: leafyLanguage), value: L10n.text(lockedCategory.rawValue, language: leafyLanguage))
                    } else {
                        Picker(L10n.text("分类", language: leafyLanguage), selection: categoryBinding) {
                            ForEach(LearningMaterialCategory.allCases) { category in
                                Text(L10n.text(category.rawValue, language: leafyLanguage)).tag(category)
                            }
                        }
                    }
                    TextField(L10n.text("课程/考试", language: leafyLanguage), text: $material.courseName)
                    TextField(L10n.text("备注", language: leafyLanguage), text: $material.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    LabeledContent(L10n.text("文件", language: leafyLanguage), value: material.originalFilename)
                    LabeledContent(L10n.text("类型", language: leafyLanguage), value: L10n.text(material.displayType, language: leafyLanguage))
                } footer: {
                    Text(L10n.text("文件本体保存在本机私有目录，仅当前 App 可访问。", language: leafyLanguage))
                }
            }
            .navigationTitle(L10n.text("编辑学习资料", language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完成", language: leafyLanguage)) {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var categoryBinding: Binding<LearningMaterialCategory> {
        Binding(
            get: { material.category },
            set: { material.category = $0 }
        )
    }

    private func save() {
        let trimmedTitle = material.title.trimmingCharacters(in: .whitespacesAndNewlines)
        material.title = trimmedTitle.isEmpty
            ? material.originalFilename
            : trimmedTitle
        if let lockedCategory {
            material.category = lockedCategory
        }
        material.courseName = material.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        material.note = material.note.trimmingCharacters(in: .whitespacesAndNewlines)
        material.updatedAt = Date()
        dismiss()
    }
}

private struct LearningMaterialPreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct LearningMaterialShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct LearningMaterialPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let url: URL

    @State private var shareItem: LearningMaterialShareItem?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            LearningMaterialQuickLookPreview(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .leafyInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .leafyLeading) {
                        Button(L10n.text("关闭", language: leafyLanguage)) {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .leafyTrailing) {
                        Button(L10n.text("导出", language: leafyLanguage), action: share)
                            .fontWeight(.semibold)
                    }
                }
                .sheet(item: $shareItem) { item in
                    ShareSheet(activityItems: [item.url])
                }
                .alert("学习资料操作失败", isPresented: Binding(
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
            alertMessage = L10n.text("无法找到本地学习资料文件。", language: leafyLanguage)
            return
        }
        shareItem = LearningMaterialShareItem(url: url)
    }
}

#if canImport(UIKit)
private struct LearningMaterialQuickLookPreview: UIViewControllerRepresentable {
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
private typealias LearningMaterialQuickLookPreview = LeafyDocumentPreview
#endif

private struct LearningSummaryTableRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
            Text(title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: AppSpacing.micro)

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }
}

private struct LearningWorkspaceTableHeader: View {
    let title: String
    let durationTitle: String
    let trailingWidth: CGFloat

    var body: some View {
        HStack(spacing: AppSpacing.micro) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("资料")
                .frame(width: 24, alignment: .trailing)
            Text("待办")
                .frame(width: 24, alignment: .trailing)
            Text(durationTitle)
                .frame(width: 36, alignment: .trailing)
            Color.clear
                .frame(width: trailingWidth)
        }
        .microCaption()
        .foregroundStyle(AppTheme.tertiaryText)
        .padding(.bottom, 6)
    }
}

private struct LearningCompactIconBadge: View {
    let systemName: String?
    let text: String?

    init(systemName: String) {
        self.systemName = systemName
        text = nil
    }

    init(text: String) {
        systemName = nil
        self.text = text
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppTheme.softFill)

            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis)
            } else if let text {
                Text(text)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 28, height: 28)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }
}

private struct LearningWorkspaceFixedSpaceRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let category: LearningMaterialCategory
    let summary: LearningWorkspaceSummary
    let openAction: () -> Void

    var body: some View {
        Button(action: openAction) {
            HStack(alignment: .center, spacing: AppSpacing.micro) {
                iconBadge

                Text(L10n.text(category.rawValue, language: leafyLanguage))
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                LearningWorkspaceCountText("\(summary.materialCount)", width: 24)
                LearningWorkspaceCountText("\(summary.pendingTaskCount)", width: 24)
                LearningWorkspaceCountText(StudyTimeDurationFormatter.compactText(for: summary.weekDuration, language: leafyLanguage), width: 36)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(width: 8)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(category.rawValue, language: leafyLanguage))
    }

    @ViewBuilder
    private var iconBadge: some View {
        if category == .cet {
            LearningCompactIconBadge(text: "EN")
        } else {
            LearningCompactIconBadge(systemName: icon)
        }
    }

    private var icon: String {
        switch category {
        case .cet:
            return "character.book.closed"
        case .exam:
            return "doc.text.magnifyingglass"
        case .courseware:
            return "rectangle.on.rectangle.angled"
        case .other:
            return "tray.full"
        }
    }
}

private struct LearningWorkspaceCountText: View {
    let text: String
    let width: CGFloat

    init(_ text: String, width: CGFloat = 24) {
        self.text = text
        self.width = width
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: width, alignment: .trailing)
    }
}

private struct LearningProjectRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let project: LearningProject
    let summary: LearningWorkspaceSummary
    let openAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.compact) {
            Button(action: openAction) {
                HStack(alignment: .center, spacing: AppSpacing.micro) {
                    LearningCompactIconBadge(systemName: project.kind.icon)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.title)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(project.kind.title)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)

                            if project.isArchived {
                                PlanBadge(text: "已归档")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    LearningWorkspaceCountText("\(summary.materialCount)", width: 24)
                    LearningWorkspaceCountText("\(summary.pendingTaskCount)", width: 24)
                    LearningWorkspaceCountText(StudyTimeDurationFormatter.compactText(for: summary.totalDuration, language: leafyLanguage), width: 36)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: editAction) {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive, action: deleteAction) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多项目操作")
        }
        .padding(.vertical, 7)
    }
}

private enum LearningWorkspaceDetailTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case materials = "资料"
    case tasks = "任务"
    case records = "记录"

    var id: String { rawValue }

    init(initialTab: LearningWorkspaceInitialTab) {
        switch initialTab {
        case .overview:
            self = .overview
        case .materials:
            self = .materials
        case .tasks:
            self = .tasks
        case .records:
            self = .records
        }
    }
}

struct LearningWorkspaceDetailView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let destination: LearningWorkspaceDestination

    @Query(sort: \LearningProject.updatedAt, order: .reverse) private var projects: [LearningProject]
    @Query(sort: \LearningMaterialDocument.updatedAt, order: .reverse) private var materials: [LearningMaterialDocument]
    @Query(sort: \LearningProjectTask.updatedAt, order: .reverse) private var tasks: [LearningProjectTask]
    @Query(sort: \StudyTimeRecord.startedAt, order: .reverse) private var records: [StudyTimeRecord]

    @State private var selectedTab: LearningWorkspaceDetailTab = .overview
    @State private var isImporterPresented = false
    @State private var editingMaterial: LearningMaterialDocument?
    @State private var previewItem: LearningMaterialPreviewItem?
    @State private var shareItem: LearningMaterialShareItem?
    @State private var materialPendingDeletion: LearningMaterialDocument?
    @State private var isTaskEditorPresented = false
    @State private var editingTask: LearningProjectTask?
    @State private var showingRecordEditor = false
    @State private var editingRecord: StudyTimeRecord?
    @State private var selectedFocusTopic = StudyFocusTopicOption.none
    @State private var activeFocusSession: StudyFocusSession?
    @State private var studyTimeShareItem: StudyTimeShareItem?
    @State private var shareErrorMessage: String?
    @State private var editingProject: LearningProject?
    @State private var projectPendingDeletion: LearningProject?
    @State private var projectPendingFullDeletion: LearningProject?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var alertMessage: String?
    @State private var workspaceIndex = LearningWorkspaceIndex.empty
    @State private var workspaceIndexSignature = LearningWorkspaceIndexSignature()

    init(destination: LearningWorkspaceDestination, initialTab: LearningWorkspaceInitialTab = .overview) {
        self.destination = destination
        self._selectedTab = State(initialValue: LearningWorkspaceDetailTab(initialTab: initialTab))
    }

    private var project: LearningProject? {
        guard case .project(let id) = destination else { return nil }
        return projects.first { $0.id == id }
    }

    private var scopedMaterials: [LearningMaterialDocument] {
        workspaceIndex.materials(for: destination)
    }

    private var scopedTasks: [LearningProjectTask] {
        workspaceIndex.tasks(for: destination)
    }

    private var scopedRecords: [StudyTimeRecord] {
        workspaceIndex.records(for: destination)
    }

    private var summary: LearningWorkspaceSummary {
        workspaceIndex.summary(for: destination)
    }

    private var topicOptions: [StudyFocusTopicOption] {
        StudyFocusTopicOption.options(projects: projects)
    }

    private var focusTopic: StudyFocusTopicOption {
        StudyFocusTopicOption.option(for: destination, projects: projects)
    }

    private var title: String {
        if let category = destination.fixedCategory {
            return L10n.text(category.rawValue, language: leafyLanguage)
        }
        return project?.title ?? "学习项目"
    }

    var body: some View {
        AcademicDetailScrollContainer {
            headerCard
            detailTabs

            switch selectedTab {
            case .overview:
                overviewContent
            case .materials:
                materialsContent
            case .tasks:
                tasksContent
            case .records:
                recordsContent
            }

            AcademicDetailFooterText(text: "资料文件只保存在本机私有目录；导出会调用系统分享面板。")
        }
        .navigationTitle(title)
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                if let project {
                    Menu {
                        Button {
                            editingProject = project
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            projectPendingDeletion = project
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多项目操作")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: LearningMaterialFileStore.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .sheet(item: $editingMaterial) { material in
            LearningMaterialEditorSheet(material: material, lockedCategory: lockedCategory)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $previewItem) { item in
            LearningMaterialPreviewSheet(title: item.title, url: item.url)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .sheet(isPresented: $isTaskEditorPresented) {
            LearningProjectTaskEditorSheet(task: nil) { draft in
                insertTask(draft)
            }
        }
        .sheet(item: $editingTask) { task in
            LearningProjectTaskEditorSheet(task: task) { draft in
                update(task, with: draft)
            }
        }
        .sheet(isPresented: $showingRecordEditor) {
            StudyTimeRecordEditorView(record: nil, topicOptions: topicOptions, initialTopic: focusTopic, lockedTopic: focusTopic) { draft in
                insertRecord(draft)
            }
        }
        .sheet(item: $editingRecord) { record in
            StudyTimeRecordEditorView(record: record, topicOptions: topicOptions, initialTopic: focusTopic, lockedTopic: focusTopic) { draft in
                update(record, with: draft)
            }
        }
        .sheet(item: $studyTimeShareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .sheet(item: $editingProject) { project in
            LearningProjectEditorSheet(project: project) { draft in
                update(project, with: draft)
            }
        }
        .confirmationDialog(
            LearningProjectDeletionText.dialogTitle,
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LearningProjectDeletionText.keepContentsAction) {
                if let project = projectPendingDeletion {
                    deleteProjectKeepingContents(project)
                }
                projectPendingDeletion = nil
            }
            Button(LearningProjectDeletionText.deleteAllAction, role: .destructive) {
                projectPendingFullDeletion = projectPendingDeletion
                projectPendingDeletion = nil
            }
            Button(LearningProjectDeletionText.cancelAction, role: .cancel) {}
        } message: {
            Text(LearningProjectDeletionText.dialogMessage)
        }
        .confirmationDialog(
            LearningProjectDeletionText.fullDeleteTitle,
            isPresented: Binding(
                get: { projectPendingFullDeletion != nil },
                set: { if !$0 { projectPendingFullDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LearningProjectDeletionText.deleteAllAction, role: .destructive) {
                if let project = projectPendingFullDeletion {
                    deleteProjectAndContents(project)
                }
                projectPendingFullDeletion = nil
            }
            Button(LearningProjectDeletionText.cancelAction, role: .cancel) {}
        } message: {
            Text(LearningProjectDeletionText.fullDeleteMessage)
        }
        .confirmationDialog("删除这份学习资料？", isPresented: Binding(
            get: { materialPendingDeletion != nil },
            set: { if !$0 { materialPendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let material = materialPendingDeletion {
                    delete(material)
                }
                materialPendingDeletion = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会同时移除本地文件，无法恢复。")
        }
        .alert("学习相关操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("无法生成分享图片", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .onAppear(perform: refreshWorkspaceIndexIfNeeded)
        .onChange(of: LearningWorkspaceIndexSignature(materials: materials, tasks: tasks, records: records)) { _, _ in
            refreshWorkspaceIndexIfNeeded()
        }
        .leafyOperationAlert($operationAlert)
    }

    private var headerCard: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .top, spacing: AppSpacing.compact) {
                    headerIconBadge
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(headerSubtitle)
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: AppSpacing.micro)
                }

                VStack(spacing: 0) {
                    LearningSummaryTableRow(title: "资料", value: "\(summary.materialCount)")
                    AcademicDetailDivider()
                    LearningSummaryTableRow(title: "待办", value: "\(summary.pendingTaskCount)")
                    AcademicDetailDivider()
                    LearningSummaryTableRow(title: "记录", value: "\(summary.recordCount)")
                }
            }
        }
    }

    @ViewBuilder
    private var headerIconBadge: some View {
        if destination.fixedCategory == .cet {
            LearningCompactIconBadge(text: "EN")
        } else {
            LeafyIconBadge(systemName: headerIcon)
        }
    }

    private var detailTabs: some View {
        Picker("学习空间内容", selection: $selectedTab) {
            ForEach(LearningWorkspaceDetailTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var overviewContent: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("下一步", systemImage: "checklist")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                if let nextTask = scopedTasks.first(where: { !$0.isCompleted }) {
                    LearningTaskRow(
                        task: nextTask,
                        toggleAction: { toggle(nextTask) },
                        editAction: { editingTask = nextTask },
                        deleteAction: { deleteTask(nextTask) }
                    )
                } else {
                    Text("暂无待办，可以添加一个下一步任务。")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                HStack(spacing: AppSpacing.micro) {
                    LearningQuickActionButton(title: "添加任务", systemName: "plus") {
                        isTaskEditorPresented = true
                    }
                    LearningQuickActionButton(title: "导入资料", systemName: "tray.and.arrow.down") {
                        isImporterPresented = true
                    }
                }
            }
        }
    }

    private var materialsContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: "学习资料")
                Spacer()
                CareerSectionAddButton(title: "导入资料", systemName: "tray.and.arrow.down") {
                    isImporterPresented = true
                }
            }

            if scopedMaterials.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("还没有学习资料", systemImage: "folder", description: Text("导入 PDF、图片、Word、PPT 或表格后，可预览、编辑和导出。"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.compact)
                }
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(scopedMaterials.enumerated()), id: \.element.id) { index, material in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            LearningMaterialRow(material: material) {
                                preview(material)
                            } editAction: {
                                editingMaterial = material
                            } shareAction: {
                                share(material)
                            } deleteAction: {
                                materialPendingDeletion = material
                            }
                        }
                    }
                }
            }
        }
    }

    private var tasksContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                AcademicDetailSectionHeader(title: "任务")
                Spacer()
                CareerSectionAddButton(title: "添加任务", systemName: "plus") {
                    isTaskEditorPresented = true
                }
            }

            if scopedTasks.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("暂无任务", systemImage: "checklist", description: Text("可以记录复习章节、资料整理、刷题或考试准备。"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.compact)
                }
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(scopedTasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            LearningTaskRow(
                                task: task,
                                toggleAction: { toggle(task) },
                                editAction: { editingTask = task },
                                deleteAction: { deleteTask(task) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var recordsContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            StudyFocusTimerPanel(
                topicOptions: topicOptions,
                lockedTopic: focusTopic,
                selectedTopic: $selectedFocusTopic,
                activeSession: $activeFocusSession,
                stopAction: stopFocusSession
            )

            HStack {
                AcademicDetailSectionHeader(title: "学习记录")
                Spacer()
                CareerSectionAddButton(title: "导出图片", systemName: "square.and.arrow.up") {
                    exportImage()
                }
                CareerSectionAddButton(title: "添加记录", systemName: "plus") {
                    showingRecordEditor = true
                }
            }

            if scopedRecords.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("暂无专注记录", systemImage: "clock.badge.checkmark", description: Text("记录一段学习时间后，会在这里看到当前空间的累计时长。"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.compact)
                }
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(scopedRecords.enumerated()), id: \.element.id) { index, record in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            StudyTimeRecordRow(
                                record: record,
                                editAction: { editingRecord = record },
                                deleteAction: { deleteRecord(record) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var lockedCategory: LearningMaterialCategory? {
        destination.fixedCategory
    }

    private var headerIcon: String {
        if let category = destination.fixedCategory {
            switch category {
            case .cet:
                return "character.book.closed"
            case .exam:
                return "doc.text.magnifyingglass"
            case .courseware:
                return "rectangle.on.rectangle.angled"
            case .other:
                return "tray.full"
            }
        }
        return project?.kind.icon ?? "folder"
    }

    private var headerSubtitle: String {
        if let category = destination.fixedCategory {
            switch category {
            case .cet:
                return "固定空间不可删除，用于集中管理四六级资料、任务和学习记录。"
            case .exam:
                return "固定空间不可删除，用于收纳各类考试复习资料和安排。"
            case .courseware:
                return "固定空间不可删除，用于保存课程课件、讲义和课堂资料。"
            case .other:
                return "未归档内容会先放在这里，之后可以编辑资料分类或移动到项目。"
            }
        }
        return project?.goal.isEmpty == false ? project?.goal ?? "" : "自定义学习项目，适合长期目标或专项复习。"
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var importedMaterials: [LearningMaterialDocument] = []

            for url in urls {
                let stored = try LearningMaterialFileStore.importFile(from: url)
                let title = url.deletingPathExtension().lastPathComponent
                let material = LearningMaterialDocument(
                    projectID: destination.projectID,
                    title: title.isEmpty ? L10n.text("学习资料", language: leafyLanguage) : title,
                    categoryRawValue: destination.fixedCategory?.rawValue ?? LearningMaterialCategory.other.rawValue,
                    originalFilename: url.lastPathComponent,
                    localFilename: stored.localFilename,
                    contentTypeIdentifier: stored.contentTypeIdentifier
                )
                modelContext.insert(material)
                importedMaterials.append(material)
            }

            try modelContext.save()
            switch importedMaterials.count {
            case 0:
                break
            case 1:
                operationAlert = .success(L10n.text("资料已导入！", language: leafyLanguage))
                editingMaterial = importedMaterials.first
            default:
                operationAlert = .success(L10n.text("已导入 %d 份资料！", language: leafyLanguage, importedMaterials.count))
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func preview(_ material: LearningMaterialDocument) {
        guard let url = LearningMaterialFileStore.fileURL(for: material) else {
            alertMessage = L10n.text("无法找到本地学习资料文件。", language: leafyLanguage)
            return
        }
        previewItem = LearningMaterialPreviewItem(title: material.title, url: url)
    }

    private func share(_ material: LearningMaterialDocument) {
        guard let url = LearningMaterialFileStore.fileURL(for: material) else {
            alertMessage = L10n.text("无法找到本地学习资料文件。", language: leafyLanguage)
            return
        }
        shareItem = LearningMaterialShareItem(url: url)
    }

    private func delete(_ material: LearningMaterialDocument) {
        do {
            try LearningMaterialFileStore.deleteFile(named: material.localFilename)
            modelContext.delete(material)
            try modelContext.save()
            operationAlert = .success(L10n.text("资料已删除！", language: leafyLanguage))
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func insertTask(_ draft: LearningProjectTaskDraft) {
        modelContext.insert(LearningProjectTask(
            projectID: destination.projectID,
            categoryRawValue: destination.fixedCategory?.rawValue ?? LearningMaterialCategory.other.rawValue,
            title: draft.title,
            note: draft.note,
            dueAt: draft.dueAt
        ))
        save(successMessage: "任务已添加！")
    }

    private func update(_ task: LearningProjectTask, with draft: LearningProjectTaskDraft) {
        task.title = draft.title
        task.note = draft.note
        task.dueAt = draft.dueAt
        task.updatedAt = Date()
        save(successMessage: "任务已保存！")
    }

    private func toggle(_ task: LearningProjectTask) {
        task.isCompleted.toggle()
        task.updatedAt = Date()
        save(successMessage: task.isCompleted ? "任务已完成！" : "任务已恢复！")
    }

    private func deleteTask(_ task: LearningProjectTask) {
        modelContext.delete(task)
        save(successMessage: "任务已删除！")
    }

    private func insertRecord(_ draft: StudyTimeRecordDraft) {
        let now = Date()
        modelContext.insert(StudyTimeRecord(
            projectID: draft.projectID,
            categoryRawValue: draft.categoryRawValue,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            content: draft.content,
            location: draft.location,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        ))
        save(successMessage: "记录已添加！")
    }

    private func update(_ record: StudyTimeRecord, with draft: StudyTimeRecordDraft) {
        record.startedAt = draft.startedAt
        record.endedAt = draft.endedAt
        record.projectID = draft.projectID
        record.categoryRawValue = draft.categoryRawValue
        record.content = draft.content
        record.location = draft.location
        record.note = draft.note
        record.updatedAt = Date()
        save(successMessage: "记录已保存！")
    }

    private func deleteRecord(_ record: StudyTimeRecord) {
        modelContext.delete(record)
        save(successMessage: "记录已删除！")
    }

    private func stopFocusSession(_ session: StudyFocusSession, endedAt: Date) {
        let endedAt = max(endedAt, session.startedAt.addingTimeInterval(60))
        let now = Date()
        modelContext.insert(StudyTimeRecord(
            projectID: focusTopic.projectID,
            categoryRawValue: focusTopic.categoryRawValue,
            startedAt: session.startedAt,
            endedAt: endedAt,
            content: focusTopic.title,
            location: "图书馆",
            createdAt: now,
            updatedAt: now
        ))
        save(successMessage: "专注记录已保存！")
    }

    @MainActor
    private func exportImage() {
        let content = StudyTimeShareCard(
            title: "专注记录",
            topicTitle: title,
            todayDuration: scopedRecords.filter { Calendar.current.isDateInToday($0.startedAt) }.learningDuration,
            weekDuration: scopedRecords.filter { record in
                Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.contains(record.startedAt) == true
            }.learningDuration,
            totalDuration: scopedRecords.learningDuration,
            records: scopedRecords,
            generatedAt: Date()
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = LeafyImageCodec.displayScale

        guard let image = renderer.leafyPlatformImage else {
            shareErrorMessage = "请稍后重试，或先截图保存当前页面。"
            return
        }

        studyTimeShareItem = StudyTimeShareItem(image: image)
    }

    private func update(_ project: LearningProject, with draft: LearningProjectDraft) {
        project.title = draft.title
        project.kind = draft.kind
        project.goal = draft.goal
        project.isArchived = draft.isArchived
        project.updatedAt = Date()
        save(successMessage: "项目已保存！")
    }

    private func deleteProjectKeepingContents(_ project: LearningProject) {
        do {
            try LearningProjectContentRelocation.deleteProjectKeepingContents(
                project,
                materials: materials,
                tasks: tasks,
                records: records,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func deleteProjectAndContents(_ project: LearningProject) {
        do {
            try LearningProjectContentRelocation.deleteProjectAndContents(
                project,
                materials: materials,
                tasks: tasks,
                records: records,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func save(successMessage: String) {
        do {
            try modelContext.save()
            operationAlert = .success(L10n.text(successMessage, language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func refreshWorkspaceIndexIfNeeded() {
        let signature = LearningWorkspaceIndexSignature(materials: materials, tasks: tasks, records: records)
        guard signature != workspaceIndexSignature else { return }
        workspaceIndexSignature = signature
        workspaceIndex = LearningWorkspaceIndex.make(materials: materials, tasks: tasks, records: records)
    }
}

private struct LearningTaskRow: View {
    let task: LearningProjectTask
    let toggleAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.micro) {
            Button(action: toggleAction) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(task.isCompleted ? AppTheme.accent : AppTheme.secondaryText)
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
                    Label(DateFormatters.headerWithTime.string(from: dueAt), systemImage: "calendar")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if !task.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.note)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑任务")

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除任务")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct LearningQuickActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(AppTheme.softFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct LearningProjectDraft {
    var title: String
    var kind: LearningProjectKind
    var goal: String
    var isArchived: Bool
}

private struct LearningProjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: LearningProject?
    let onSave: (LearningProjectDraft) -> Void

    @State private var title: String
    @State private var kind: LearningProjectKind
    @State private var goal: String
    @State private var isArchived: Bool

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(project: LearningProject?, onSave: @escaping (LearningProjectDraft) -> Void) {
        self.project = project
        self.onSave = onSave
        _title = State(initialValue: project?.title ?? "")
        _kind = State(initialValue: project?.kind ?? .general)
        _goal = State(initialValue: project?.goal ?? "")
        _isArchived = State(initialValue: project?.isArchived ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("项目名称", text: $title)
                    Picker("类型", selection: $kind) {
                        ForEach(LearningProjectKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    TextField("目标/备注", text: $goal, axis: .vertical)
                        .lineLimit(3...6)
                    if project != nil {
                        Toggle("归档项目", isOn: $isArchived)
                    }
                }
            }
            .navigationTitle(project == nil ? "新建项目" : "编辑项目")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(LearningProjectDraft(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            kind: kind,
                            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                            isArchived: isArchived
                        ))
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
}

private struct LearningProjectTaskDraft {
    var title: String
    var note: String
    var dueAt: Date?
}

private struct LearningProjectTaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: LearningProjectTask?
    let onSave: (LearningProjectTaskDraft) -> Void

    @State private var title: String
    @State private var note: String
    @State private var hasDueDate: Bool
    @State private var dueAt: Date

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(task: LearningProjectTask?, onSave: @escaping (LearningProjectTaskDraft) -> Void) {
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
                        onSave(LearningProjectTaskDraft(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            dueAt: hasDueDate ? dueAt : nil
                        ))
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
}

extension LearningProjectKind {
    var icon: String {
        switch self {
        case .course:
            return "book.closed.fill"
        case .exam:
            return "doc.text.magnifyingglass"
        case .certificate:
            return "checkmark.seal.fill"
        case .general:
            return "folder.fill"
        }
    }

    var defaultSubtitle: String {
        switch self {
        case .course:
            return "围绕一门课程整理资料、任务和学习记录。"
        case .exam:
            return "围绕一次考试管理复习节奏。"
        case .certificate:
            return "适合证书、竞赛或资格考试准备。"
        case .general:
            return "用于长期学习目标或专项计划。"
        }
    }
}

@MainActor
struct StudyFocusTopicOption: Identifiable, Hashable {
    let id: String
    let title: String
    let projectID: String
    let categoryRawValue: String
    let icon: String

    static let none = StudyFocusTopicOption(
        id: "none",
        title: "不选主题",
        projectID: "",
        categoryRawValue: LearningMaterialCategory.other.rawValue,
        icon: "circle"
    )

    var category: LearningMaterialCategory {
        LearningMaterialCategory.normalized(categoryRawValue)
    }

    var destination: LearningWorkspaceDestination? {
        if let projectUUID = UUID(uuidString: projectID) {
            return .project(projectUUID)
        }
        if id.hasPrefix("fixed-") {
            return .fixed(category)
        }
        return nil
    }

    static func fixed(_ category: LearningMaterialCategory) -> StudyFocusTopicOption {
        StudyFocusTopicOption(
            id: "fixed-\(category.rawValue)",
            title: category.rawValue,
            projectID: "",
            categoryRawValue: category.rawValue,
            icon: icon(for: category)
        )
    }

    static func project(_ project: LearningProject) -> StudyFocusTopicOption {
        StudyFocusTopicOption(
            id: "project-\(project.id.uuidString)",
            title: project.title,
            projectID: project.id.uuidString,
            categoryRawValue: LearningMaterialCategory.other.rawValue,
            icon: project.kind.icon
        )
    }

    static func options(projects: [LearningProject]) -> [StudyFocusTopicOption] {
        let fixed = LearningMaterialCategory.fixedSpaceOrder.map(StudyFocusTopicOption.fixed)
        let projectOptions = projects
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(StudyFocusTopicOption.project)
        return [.none] + fixed + projectOptions
    }

    static func option(for destination: LearningWorkspaceDestination, projects: [LearningProject]) -> StudyFocusTopicOption {
        switch destination {
        case .fixed(let category):
            return fixed(category)
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                return Self.project(project)
            }
            return StudyFocusTopicOption(
                id: "project-\(id.uuidString)",
                title: "学习项目",
                projectID: id.uuidString,
                categoryRawValue: LearningMaterialCategory.other.rawValue,
                icon: "folder"
            )
        }
    }

    static func option(for record: StudyTimeRecord, projects: [LearningProject]) -> StudyFocusTopicOption {
        if let projectUUID = UUID(uuidString: record.projectID) {
            if let project = projects.first(where: { $0.id == projectUUID }) {
                return Self.project(project)
            }
            return StudyFocusTopicOption(
                id: "project-\(projectUUID.uuidString)",
                title: "学习项目",
                projectID: projectUUID.uuidString,
                categoryRawValue: LearningMaterialCategory.other.rawValue,
                icon: "folder"
            )
        }
        if record.category == .other {
            return .none
        }
        return fixed(record.category)
    }

    private static func icon(for category: LearningMaterialCategory) -> String {
        switch category {
        case .cet:
            return "character.book.closed"
        case .exam:
            return "doc.text.magnifyingglass"
        case .courseware:
            return "rectangle.on.rectangle.angled"
        case .other:
            return "tray.full"
        }
    }
}

private struct StudyFocusSession: Identifiable {
    let id = UUID()
    let startedAt: Date
    let topic: StudyFocusTopicOption
}

private struct StudyTimeShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct StudyFocusTimerPanel: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let topicOptions: [StudyFocusTopicOption]
    let lockedTopic: StudyFocusTopicOption?
    @Binding var selectedTopic: StudyFocusTopicOption
    @Binding var activeSession: StudyFocusSession?
    let stopAction: (StudyFocusSession, Date) -> Void

    private var effectiveTopic: StudyFocusTopicOption {
        lockedTopic ?? selectedTopic
    }

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .top, spacing: AppSpacing.compact) {
                    LeafyIconBadge(systemName: activeSession == nil ? "timer" : "timer.circle.fill")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeSession == nil ? "开始专注" : "专注进行中")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(activeSession == nil ? "点击后立即开始计时，停止时保存为专注记录。" : "停止后会写入当前 Topic 的专注记录。")
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                }

                if let lockedTopic {
                    Label(lockedTopic.title, systemImage: lockedTopic.icon)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Picker("Topic", selection: $selectedTopic) {
                        ForEach(topicOptions) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let activeSession {
                    TimelineView(.periodic(from: activeSession.startedAt, by: 1)) { context in
                        Text(StudyTimeDurationFormatter.text(for: context.date.timeIntervalSince(activeSession.startedAt), language: leafyLanguage))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .monospacedDigit()
                    }

                    Button(role: .destructive) {
                        let session = activeSession
                        self.activeSession = nil
                        stopAction(session, Date())
                    } label: {
                        Label("停止并保存", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(AppTheme.danger))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        activeSession = StudyFocusSession(startedAt: Date(), topic: effectiveTopic)
                    } label: {
                        Label("开始专注", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(AppTheme.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StudyTimeShareCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let topicTitle: String
    let todayDuration: TimeInterval
    let weekDuration: TimeInterval
    let totalDuration: TimeInterval
    let records: [StudyTimeRecord]
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                LeafyIconBadge(systemName: "clock.badge.checkmark")
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(topicTitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StudyTimeShareMetric(title: "今日", duration: todayDuration)
                StudyTimeShareMetric(title: "本周", duration: weekDuration)
                StudyTimeShareMetric(title: "累计", duration: totalDuration)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("最近记录")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                if records.isEmpty {
                    Text("暂无专注记录")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(records.prefix(5), id: \.id) { record in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.content)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.primaryText)
                                Text("\(DateFormatters.headerWithTime.string(from: record.startedAt)) · \(StudyTimeDurationFormatter.text(for: record.endedAt.timeIntervalSince(record.startedAt), language: leafyLanguage))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }
                }
            }

            Text("分享于 \(DateFormatters.headerWithTime.string(from: generatedAt))")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(24)
        .frame(width: 390, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
    }
}

private struct StudyTimeShareMetric: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(StudyTimeDurationFormatter.text(for: duration, language: leafyLanguage))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StudyTimeRecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Query(sort: \LearningProject.updatedAt, order: .reverse) private var projects: [LearningProject]
    @Query(sort: \StudyTimeRecord.startedAt, order: .reverse) private var records: [StudyTimeRecord]

    @State private var showingEditor = false
    @State private var editingRecord: StudyTimeRecord?
    @State private var selectedTopic = StudyFocusTopicOption.none
    @State private var activeFocusSession: StudyFocusSession?
    @State private var shareItem: StudyTimeShareItem?
    @State private var shareErrorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    private var topicOptions: [StudyFocusTopicOption] {
        StudyFocusTopicOption.options(projects: projects)
    }

    private var visibleRecords: [StudyTimeRecord] {
        guard let destination = selectedTopic.destination else { return records }
        return records.filter { $0.belongs(to: destination) }
    }

    private var todayDuration: TimeInterval {
        duration(for: visibleRecords.filter { Calendar.current.isDateInToday($0.startedAt) })
    }

    private var weekDuration: TimeInterval {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return duration(for: visibleRecords.filter { week.contains($0.startedAt) })
    }

    private var totalDuration: TimeInterval {
        duration(for: visibleRecords)
    }

    var body: some View {
        AcademicDetailScrollContainer {
            StudyTimeSummaryCard(
                todayDuration: todayDuration,
                weekDuration: weekDuration,
                totalDuration: totalDuration
            )

            StudyFocusTimerPanel(
                topicOptions: topicOptions,
                lockedTopic: nil,
                selectedTopic: $selectedTopic,
                activeSession: $activeFocusSession,
                stopAction: stopFocusSession
            )

            HStack {
                AcademicDetailSectionHeader(title: L10n.text("学习记录", language: leafyLanguage))
                Spacer()
                CareerSectionAddButton(title: L10n.text("导出图片", language: leafyLanguage), systemName: "square.and.arrow.up") {
                    exportImage()
                }
                CareerSectionAddButton(title: L10n.text("添加记录", language: leafyLanguage), systemName: "plus") {
                    showingEditor = true
                }
            }

            if visibleRecords.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView(
                        L10n.text("暂无专注记录", language: leafyLanguage),
                        systemImage: "clock.badge.checkmark",
                        description: Text(L10n.text("记录一段学习时间后，会在这里看到今日、本周和总时长。", language: leafyLanguage))
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.compact)
                }
            } else {
                AcademicDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                            if index > 0 {
                                AcademicDetailDivider()
                            }
                            StudyTimeRecordRow(
                                record: record,
                                editAction: { editingRecord = record },
                                deleteAction: { delete(record) }
                            )
                        }
                    }
                }
            }

            AcademicDetailFooterText(text: L10n.text("专注记录仅保存在当前设备。", language: leafyLanguage))
        }
        .navigationTitle("专注记录")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.text("添加记录", language: leafyLanguage))
            }
        }
        .sheet(isPresented: $showingEditor) {
            StudyTimeRecordEditorView(record: nil, topicOptions: topicOptions, initialTopic: selectedTopic) { draft in
                insert(draft)
            }
        }
        .sheet(item: $editingRecord) { record in
            StudyTimeRecordEditorView(record: record, topicOptions: topicOptions, initialTopic: StudyFocusTopicOption.option(for: record, projects: projects)) { draft in
                update(record, with: draft)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .alert("无法生成分享图片", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .leafyOperationAlert($operationAlert)
    }

    private func duration(for records: [StudyTimeRecord]) -> TimeInterval {
        records.reduce(0) { partialResult, record in
            partialResult + max(record.endedAt.timeIntervalSince(record.startedAt), 0)
        }
    }

    private func insert(_ draft: StudyTimeRecordDraft) {
        let now = Date()
        modelContext.insert(StudyTimeRecord(
            projectID: draft.projectID,
            categoryRawValue: draft.categoryRawValue,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            content: draft.content,
            location: draft.location,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        ))
        save(successMessage: "记录已添加！")
    }

    private func update(_ record: StudyTimeRecord, with draft: StudyTimeRecordDraft) {
        record.startedAt = draft.startedAt
        record.endedAt = draft.endedAt
        record.projectID = draft.projectID
        record.categoryRawValue = draft.categoryRawValue
        record.content = draft.content
        record.location = draft.location
        record.note = draft.note
        record.updatedAt = Date()
        save(successMessage: "记录已保存！")
    }

    private func delete(_ record: StudyTimeRecord) {
        modelContext.delete(record)
        save(successMessage: "记录已删除！")
    }

    private func stopFocusSession(_ session: StudyFocusSession, endedAt: Date) {
        let endedAt = max(endedAt, session.startedAt.addingTimeInterval(60))
        let now = Date()
        modelContext.insert(StudyTimeRecord(
            projectID: session.topic.projectID,
            categoryRawValue: session.topic.categoryRawValue,
            startedAt: session.startedAt,
            endedAt: endedAt,
            content: session.topic == .none ? "专注学习" : session.topic.title,
            location: "图书馆",
            createdAt: now,
            updatedAt: now
        ))
        save(successMessage: "专注记录已保存！")
    }

    @MainActor
    private func exportImage() {
        let content = StudyTimeShareCard(
            title: "专注记录",
            topicTitle: selectedTopic.destination == nil ? "全部 Topic" : selectedTopic.title,
            todayDuration: todayDuration,
            weekDuration: weekDuration,
            totalDuration: totalDuration,
            records: visibleRecords,
            generatedAt: Date()
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = LeafyImageCodec.displayScale

        guard let image = renderer.leafyPlatformImage else {
            shareErrorMessage = L10n.text("请稍后重试，或先截图保存当前页面。", language: leafyLanguage)
            return
        }

        shareItem = StudyTimeShareItem(image: image)
    }

    private func save(successMessage: String) {
        do {
            try modelContext.save()
            operationAlert = .success(L10n.text(successMessage, language: leafyLanguage))
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

private struct StudyTimeSummaryCard: View {
    let todayDuration: TimeInterval
    let weekDuration: TimeInterval
    let totalDuration: TimeInterval

    var body: some View {
        AcademicDetailCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label("专注记录", systemImage: "clock.badge.checkmark")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
                    StudyTimeSummaryMetric(title: "今日", duration: todayDuration)
                    StudyTimeSummaryMetric(title: "本周", duration: weekDuration)
                    StudyTimeSummaryMetric(title: "总时长", duration: totalDuration)
                }
            }
        }
    }
}

private struct StudyTimeSummaryMetric: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(title, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
            Text(StudyTimeDurationFormatter.text(for: duration, language: leafyLanguage))
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StudyTimeRecordRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let record: StudyTimeRecord
    let editAction: () -> Void
    let deleteAction: () -> Void

    private var durationText: String {
        StudyTimeDurationFormatter.text(for: record.endedAt.timeIntervalSince(record.startedAt), language: leafyLanguage)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            VStack(alignment: .leading, spacing: 8) {
                Text(record.content)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(timeRangeText)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.secondaryText)

                HStack(spacing: 8) {
                    Label(L10n.text(record.location, language: leafyLanguage), systemImage: "mappin.and.ellipse")
                    Text(durationText)
                }
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)

                if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(record.note)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.micro)

            VStack(spacing: AppSpacing.micro) {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.softFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("编辑记录", language: leafyLanguage))

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.danger.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("删除记录", language: leafyLanguage))
            }
        }
        .padding(.vertical, 4)
    }

    private var timeRangeText: String {
        let startText = DateFormatters.headerWithTime.string(from: record.startedAt)
        let endText: String
        if Calendar.current.isDate(record.startedAt, inSameDayAs: record.endedAt) {
            endText = DateFormatters.timeOnly.string(from: record.endedAt)
        } else {
            endText = DateFormatters.headerWithTime.string(from: record.endedAt)
        }
        return "\(startText) - \(endText)"
    }
}

private struct StudyTimeRecordDraft {
    var projectID: String
    var categoryRawValue: String
    var startedAt: Date
    var endedAt: Date
    var content: String
    var location: String
    var note: String
}

private struct StudyTimeRecordEditorView: View {
    let record: StudyTimeRecord?
    let topicOptions: [StudyFocusTopicOption]
    let lockedTopic: StudyFocusTopicOption?
    let onSave: (StudyTimeRecordDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var selectedTopic: StudyFocusTopicOption
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var content: String
    @State private var location: String
    @State private var note: String

    private var locations: [String] {
        ["图书馆"] + ClassroomCatalog.buildings
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveDisabled: Bool {
        trimmedContent.isEmpty || endedAt <= startedAt
    }

    private var effectiveTopic: StudyFocusTopicOption {
        lockedTopic ?? selectedTopic
    }

    init(
        record: StudyTimeRecord?,
        topicOptions: [StudyFocusTopicOption],
        initialTopic: StudyFocusTopicOption,
        lockedTopic: StudyFocusTopicOption? = nil,
        onSave: @escaping (StudyTimeRecordDraft) -> Void
    ) {
        let now = Date()
        let defaultStart = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
        let availableOptions = topicOptions.isEmpty ? [.none] : topicOptions
        let resolvedTopic: StudyFocusTopicOption
        if let lockedTopic {
            resolvedTopic = lockedTopic
        } else if let record {
            let recordTopic = StudyFocusTopicOption.option(for: record, projects: [])
            resolvedTopic = availableOptions.first(where: { $0.id == recordTopic.id }) ?? recordTopic
        } else {
            resolvedTopic = availableOptions.first(where: { $0.id == initialTopic.id }) ?? initialTopic
        }

        self.record = record
        self.topicOptions = availableOptions
        self.lockedTopic = lockedTopic
        self.onSave = onSave
        _selectedTopic = State(initialValue: resolvedTopic)
        _startedAt = State(initialValue: record?.startedAt ?? defaultStart)
        _endedAt = State(initialValue: record?.endedAt ?? now)
        _content = State(initialValue: record?.content ?? "")
        _location = State(initialValue: record?.location ?? "图书馆")
        _note = State(initialValue: record?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("开始时间", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束时间", selection: $endedAt, displayedComponents: [.date, .hourAndMinute])
                    if endedAt <= startedAt {
                        Text("结束时间必须晚于开始时间。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                Section {
                    if let lockedTopic {
                        Label(lockedTopic.title, systemImage: lockedTopic.icon)
                    } else {
                        Picker("Topic", selection: $selectedTopic) {
                            ForEach(topicOptions) { option in
                                Label(option.title, systemImage: option.icon).tag(option)
                            }
                        }
                    }
                    TextField("学习内容", text: $content)
                    Picker("地点", selection: $location) {
                        ForEach(locations, id: \.self) { item in
                            Text(L10n.text(item, language: leafyLanguage)).tag(item)
                        }
                    }
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(record == nil ? "添加记录" : "编辑记录")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(StudyTimeRecordDraft(
                            projectID: effectiveTopic.projectID,
                            categoryRawValue: effectiveTopic.categoryRawValue,
                            startedAt: startedAt,
                            endedAt: endedAt,
                            content: trimmedContent,
                            location: location,
                            note: trimmedNote
                        ))
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
}

private enum StudyTimeDurationFormatter {
    static func text(for duration: TimeInterval, language: AppLanguagePreference) -> String {
        let totalMinutes = max(Int(duration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)分钟"
        }
        if minutes == 0 {
            return "\(hours)小时"
        }
        return "\(hours)小时\(minutes)分钟"
    }

    static func compactText(for duration: TimeInterval, language: AppLanguagePreference) -> String {
        let totalMinutes = max(Int(duration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)分"
        }
        if minutes == 0 {
            return "\(hours)时"
        }
        return "\(hours)时\(minutes)分"
    }
}
