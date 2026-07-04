import SwiftUI

struct AcademicRouteDestinationView: View {
    let route: AcademicDetailRoute
    let openRoute: (AcademicDetailRoute) -> Void

    var body: some View {
        switch route {
        case .grades:
            GradesView {
                openRoute(.gradeAnalytics)
            }
        case .gradeAnalytics:
            GradeAnalyticsDetailView()
        case .examSchedule:
            ExamScheduleView()
        case .scheduleReports:
            ScheduleReportsView()
        case .timetableProcessing:
            TimetableProcessingView()
        case .honorRecords:
            HonorRecordsView()
        case .comprehensiveQuality:
            ComprehensiveQualityView()
        case .teachingPlan:
            TeachingPlanView()
        case .trainingProgram:
            TrainingProgramView()
        case .emptyClassroom:
            EmptyClassroomView()
        case .classroomLookup(let building, let room):
            EmptyClassroomView(
                initialMode: .byRoom,
                initialBuilding: building,
                initialRoom: room,
                autoSubmit: true
            )
        case .campusHeatmap:
            CampusHeatmapView()
        case .studyTimeRecords:
            StudyTimeRecordsView()
        case .learningWorkspace(let destination, let initialTab):
            LearningWorkspaceDetailView(destination: destination, initialTab: initialTab)
        case .sunshineRun:
            SunshineRunView()
        case .fitnessTestRecords:
            FitnessTestRecordsView()
        case .sportsVenues:
            SportsVenuesView()
        case .schoolCalendar:
            SchoolCalendarView()
        case .countdowns:
            ExamScheduleView()
        case .customCountdowns:
            CustomScheduleListView()
        case .medicalPolicy:
            MedicalPolicyView()
        case .medicalScenarioAssistant:
            MedicalScenarioAssistantView()
        case .medicalLedger:
            MedicalLedgerView()
        }
    }
}
