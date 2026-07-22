import Foundation
import os

nonisolated enum LeafyPerformanceSignposter {
    static let timetable = OSSignposter(subsystem: "com.isaachuo.leafy", category: "Timetable")
    static let leafyAI = OSSignposter(subsystem: "com.isaachuo.leafy", category: "LeafyAI")
    static let community = OSSignposter(subsystem: "com.isaachuo.leafy", category: "Community")
    static let ratings = OSSignposter(subsystem: "com.isaachuo.leafy", category: "Ratings")
    static let widget = OSSignposter(subsystem: "com.isaachuo.leafy", category: "Widget")
    static let imageProcessing = OSSignposter(subsystem: "com.isaachuo.leafy", category: "ImageProcessing")
}
