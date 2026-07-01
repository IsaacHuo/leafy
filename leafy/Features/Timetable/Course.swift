import Foundation
import SwiftData

@Model
final class Course {
    var id: UUID
    var courseName: String
    var teacher: String
    var classInfo: String
    var room: String
    var location: String
    var dayOfWeek: Int
    var weeks: [Int]
    var duration: [Int]
    
    init(id: UUID = UUID(), courseName: String, teacher: String, classInfo: String = "", room: String, location: String = "", dayOfWeek: Int, weeks: [Int], duration: [Int]) {
        self.id = id
        self.courseName = courseName
        self.teacher = teacher
        self.classInfo = classInfo
        self.room = room
        self.location = location
        self.dayOfWeek = dayOfWeek
        self.weeks = weeks
        self.duration = duration
    }
}
