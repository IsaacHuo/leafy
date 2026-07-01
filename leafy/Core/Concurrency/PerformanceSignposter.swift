import Foundation
import os

nonisolated enum LeafyPerformanceSignposter {
    static let timetable = OSSignposter(subsystem: "com.isaachuo.leafy", category: "Timetable")
    static let widget = OSSignposter(subsystem: "com.isaachuo.leafy", category: "Widget")
    static let imageProcessing = OSSignposter(subsystem: "com.isaachuo.leafy", category: "ImageProcessing")
}
