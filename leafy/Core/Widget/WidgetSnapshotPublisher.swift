import Foundation
import os
import WidgetKit

protocol WidgetSnapshotPublishing: Sendable {
    func publish(_ archive: LeafyWidgetSnapshotArchive) async
    func publishNeedsLogin(_ archive: LeafyWidgetSnapshotArchive) async
}

actor WidgetSnapshotPublisher: WidgetSnapshotPublishing {
    static let shared = WidgetSnapshotPublisher()

    private var lastSignature: WidgetSnapshotSignature?

    func publish(_ archive: LeafyWidgetSnapshotArchive) async {
        await publishIfChanged(archive)
    }

    func publishNeedsLogin(_ archive: LeafyWidgetSnapshotArchive) async {
        await publishIfChanged(archive)
    }

    private func publishIfChanged(_ archive: LeafyWidgetSnapshotArchive) async {
        let signature = WidgetSnapshotSignature(archive: archive)
        guard signature != lastSignature else { return }

        let state = LeafyPerformanceSignposter.widget.beginInterval("publish-snapshot")
        let didSave = LeafyWidgetSnapshotStore.save(archive)
        LeafyPerformanceSignposter.widget.endInterval("publish-snapshot", state)
        guard didSave else { return }

        lastSignature = signature
        WidgetCenter.shared.reloadTimelines(ofKind: LeafyWidgetConstants.widgetKind)
    }
}

struct WidgetSnapshotSignature: Equatable {
    let snapshots: [SnapshotSignature]

    nonisolated init(archive: LeafyWidgetSnapshotArchive) {
        snapshots = archive.snapshots.map(SnapshotSignature.init(daySnapshot:))
    }

    struct SnapshotSignature: Equatable {
        let dayOffset: Int
        let status: LeafyWidgetSnapshot.Status
        let displayDate: String
        let weekText: String
        let dayText: String
        let headline: String
        let subtitle: String
        let syncText: String?
        let lastFailureText: String?
        let nextExamText: String?
        let courses: [CourseSignature]

        nonisolated init(daySnapshot: LeafyWidgetDaySnapshot) {
            let snapshot = daySnapshot.snapshot
            dayOffset = daySnapshot.dayOffset
            status = snapshot.status
            displayDate = snapshot.displayDate
            weekText = snapshot.weekText
            dayText = snapshot.dayText
            headline = snapshot.headline
            subtitle = snapshot.subtitle
            syncText = snapshot.syncText
            lastFailureText = snapshot.lastFailureText
            nextExamText = snapshot.nextExamText
            courses = snapshot.courses.map(CourseSignature.init(course:))
        }
    }

    struct CourseSignature: Equatable {
        let id: UUID
        let title: String
        let timeText: String
        let periodText: String
        let locationText: String
        let teacherText: String?
        let noteText: String?
        let reminderText: String?
        let accentIndex: Int
        let isActive: Bool

        nonisolated init(course: LeafyWidgetCourse) {
            id = course.id
            title = course.title
            timeText = course.timeText
            periodText = course.periodText
            locationText = course.locationText
            teacherText = course.teacherText
            noteText = course.noteText
            reminderText = course.reminderText
            accentIndex = course.accentIndex
            isActive = course.isActive
        }
    }
}
