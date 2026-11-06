import Foundation

/// The normalized, read-only task shape exposed to the Gemini briefing.
enum TodoistTaskBucket: String, Codable, Sendable {
    case dueToday
    case overdue
}

struct TodoistReadTask: Codable, Sendable, Identifiable {
    struct Due: Codable, Sendable {
        let dateTime: String?
        let date: String?
        let timeZone: String?
        let isRecurring: Bool?
    }

    struct Deadline: Codable, Sendable {
        let date: String
    }

    let id: String
    let bucket: TodoistTaskBucket
    let title: String
    let projectID: String?
    let priority: Int?
    let due: Due?
    let deadline: Deadline?
    let durationMinutes: Int?
}

struct TodoistWorkloadSignals: Codable, Sendable {
    let taskCount: Int
    let highPriorityCount: Int
    let timedDueCount: Int
    let deadlineCount: Int
    let knownDurationMinutes: Int
    let unknownDurationCount: Int
}

struct TodoistFindTasksRequest: Codable, Sendable {
    let date: String
    let timeZone: String
    let includeOverdue: Bool
    let pageCursor: String?
    let limit: Int

    static let defaultLimit = 25
    static let maxLimit = 25
}

enum TodoistReadStatus: String, Codable, Sendable {
    case success
    case partial
    case permissionDenied
    case unavailable
    case invalidArguments
}

struct TodoistFindTasksResult: Codable, Sendable {
    let requestedDate: String
    let requestedTimeZone: String
    let tasks: [TodoistReadTask]
    let fetchedAt: String
    let source: String
    let status: TodoistReadStatus
    let message: String?
    let caveats: [String]
    let complete: Bool
    let nextCursor: String?
    let workload: TodoistWorkloadSignals

    static func empty(
        date: String,
        timeZone: String,
        status: TodoistReadStatus,
        message: String?,
        fetchedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> TodoistFindTasksResult {
        TodoistFindTasksResult(
            requestedDate: date,
            requestedTimeZone: timeZone,
            tasks: [],
            fetchedAt: fetchedAt,
            source: "todoist-v1-live",
            status: status,
            message: message,
            caveats: [
                "Todoist today/overdue filters use the Todoist account timezone.",
                "Deadline-only tasks are not guaranteed to be included by due filters."
            ],
            complete: false,
            nextCursor: nil,
            workload: TodoistWorkloadSignals(
                taskCount: 0,
                highPriorityCount: 0,
                timedDueCount: 0,
                deadlineCount: 0,
                knownDurationMinutes: 0,
                unknownDurationCount: 0
            )
        )
    }
}
