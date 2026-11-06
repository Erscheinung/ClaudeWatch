import Foundation

/// Direct Todoist v1 GET-only adapter. There is intentionally no write-capable API in this type.
struct TodoistReadService: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let maxTitleLength = 240
    private static let cursorMarker = "ClaudeWatchTodoistRead"

    private enum Phase: String, Codable {
        case today
        case overdue
    }

    private struct CursorState: Codable {
        let marker: String
        let version: Int
        var phase: Phase
        var today: String?
        var overdue: String?
    }

    private struct Page: Decodable {
        let results: [RemoteTask]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case results
            case nextCursor = "next_cursor"
        }
    }

    private struct RemoteTask: Decodable {
        struct RemoteDue: Decodable {
            let date: String?
            let timezone: String?
            let isRecurring: Bool?

            enum CodingKeys: String, CodingKey {
                case date
                case timezone
                case isRecurring = "is_recurring"
            }
        }

        struct RemoteDeadline: Decodable {
            let date: String
        }

        let id: String
        let content: String
        let projectID: String?
        let priority: Int?
        let due: RemoteDue?
        let deadline: RemoteDeadline?
        let duration: Int?
        let durationUnit: String?

        enum CodingKeys: String, CodingKey {
            case id
            case content
            case projectID = "project_id"
            case priority
            case due
            case deadline
            case duration
            case durationUnit = "duration_unit"
        }

        func normalized(maxTitleLength: Int, bucket: TodoistTaskBucket) -> TodoistReadTask {
            let title = String(content.prefix(maxTitleLength))
            let due = due.map {
                TodoistReadTask.Due(
                    dateTime: $0.date?.contains("T") == true ? $0.date : nil,
                    date: $0.date,
                    timeZone: $0.timezone,
                    isRecurring: $0.isRecurring
                )
            }
            let durationMinutes: Int?
            switch durationUnit?.lowercased() {
            case "minute", "minutes": durationMinutes = duration.flatMap { $0 > 0 ? $0 : nil }
            case "day", "days": durationMinutes = duration.flatMap { $0 > 0 ? $0 * 24 * 60 : nil }
            default: durationMinutes = nil
            }
            return TodoistReadTask(
                id: id,
                bucket: bucket,
                title: title,
                projectID: projectID,
                priority: priority,
                due: due,
                deadline: deadline.map { TodoistReadTask.Deadline(date: $0.date) },
                durationMinutes: durationMinutes
            )
        }
    }

    private enum ReadError: Error {
        case permissionDenied
        case unavailable
        case invalidResponse
    }

    init(
        baseURL: URL = URL(string: "https://api.todoist.com/api/v1")!,
        session: URLSession = ChatAPIService.session
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func findTasks(
        _ request: TodoistFindTasksRequest,
        token: String
    ) async -> TodoistFindTasksResult {
        let fetchedAt = ISO8601DateFormatter().string(from: Date())
        guard !token.isEmpty else {
            return .empty(date: request.date, timeZone: request.timeZone, status: .permissionDenied,
                          message: "Connect a separate Todoist read credential in Settings.", fetchedAt: fetchedAt)
        }

        let limit = min(max(request.limit, 1), TodoistFindTasksRequest.maxLimit)
        var state: CursorState
        do {
            state = try decodeCursor(request.pageCursor)
        } catch {
            return .empty(date: request.date, timeZone: request.timeZone, status: .invalidArguments,
                          message: "The continuation cursor was not issued by ClaudeWatch.", fetchedAt: fetchedAt)
        }

        var tasks: [TodoistReadTask] = []
        var seen = Set<String>()
        do {
            if state.phase == .today {
                let page = try await fetch(query: "today", cursor: state.today, limit: limit, token: token)
                append(page.results, bucket: .dueToday, to: &tasks, seen: &seen)
                if let next = page.nextCursor {
                    state.today = next
                    state.phase = .today
                    return result(tasks: tasks, request: request, status: .success, message: nil,
                                  complete: false, nextCursor: encodeCursor(state), fetchedAt: fetchedAt)
                }
                state.today = nil
                state.phase = .overdue
            }

            if request.includeOverdue {
                if tasks.count >= limit {
                    return result(tasks: tasks, request: request, status: .success, message: nil,
                                  complete: false, nextCursor: encodeCursor(state), fetchedAt: fetchedAt)
                }
                let pageLimit = max(1, limit - tasks.count)
                let page = try await fetch(query: "overdue", cursor: state.overdue, limit: pageLimit, token: token)
                append(page.results, bucket: .overdue, to: &tasks, seen: &seen)
                if let next = page.nextCursor {
                    state.overdue = next
                    state.phase = .overdue
                    return result(tasks: tasks, request: request, status: .success, message: nil,
                                  complete: false, nextCursor: encodeCursor(state), fetchedAt: fetchedAt)
                }
            }

            return result(tasks: tasks, request: request, status: .success, message: nil,
                          complete: true, nextCursor: nil, fetchedAt: fetchedAt)
        } catch ReadError.permissionDenied {
            return result(tasks: tasks, request: request, status: tasks.isEmpty ? .permissionDenied : .partial,
                          message: tasks.isEmpty ? "Todoist denied this read. Check the token's data:read access." : "Todoist returned only part of the requested read.",
                          complete: false, nextCursor: nil, fetchedAt: fetchedAt)
        } catch is CancellationError {
            return result(tasks: tasks, request: request, status: .partial,
                          message: "The Todoist read was canceled before it completed.",
                          complete: false, nextCursor: nil, fetchedAt: fetchedAt)
        } catch {
            return result(tasks: tasks, request: request, status: tasks.isEmpty ? .unavailable : .partial,
                          message: tasks.isEmpty ? "Todoist is unavailable right now." : "Todoist returned only part of the requested read.",
                          complete: false, nextCursor: nil, fetchedAt: fetchedAt)
        }
    }

    private func fetch(query: String, cursor: String?, limit: Int, token: String) async throws -> Page {
        try Task.checkCancellation()
        var components = URLComponents(url: baseURL.appendingPathComponent("tasks/filter"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ReadError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw ReadError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw ReadError.permissionDenied }
        guard http.statusCode == 200 else { throw ReadError.unavailable }
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw ReadError.invalidResponse }
        return page
    }

    private func append(
        _ remote: [RemoteTask],
        bucket: TodoistTaskBucket,
        to tasks: inout [TodoistReadTask],
        seen: inout Set<String>
    ) {
        for item in remote {
            guard seen.insert(item.id).inserted else { continue }
            tasks.append(item.normalized(maxTitleLength: maxTitleLength, bucket: bucket))
        }
    }

    private func result(
        tasks: [TodoistReadTask], request: TodoistFindTasksRequest, status: TodoistReadStatus,
        message: String?, complete: Bool, nextCursor: String?, fetchedAt: String
    ) -> TodoistFindTasksResult {
        let workload = TodoistWorkloadSignals(
            taskCount: tasks.count,
            highPriorityCount: tasks.filter { ($0.priority ?? 0) >= 3 }.count,
            timedDueCount: tasks.filter { $0.due?.dateTime != nil }.count,
            deadlineCount: tasks.filter { $0.deadline != nil }.count,
            knownDurationMinutes: tasks.compactMap(\.durationMinutes).reduce(0, +),
            unknownDurationCount: tasks.filter { $0.durationMinutes == nil }.count
        )
        return TodoistFindTasksResult(
            requestedDate: request.date,
            requestedTimeZone: request.timeZone,
            tasks: tasks,
            fetchedAt: fetchedAt,
            source: "todoist-v1-live",
            status: status,
            message: message,
            caveats: [
                "Todoist today/overdue filters use the Todoist account timezone.",
                "Deadline-only tasks are not guaranteed to be included by due filters."
            ],
            complete: complete,
            nextCursor: nextCursor,
            workload: workload
        )
    }

    private func decodeCursor(_ encoded: String?) throws -> CursorState {
        guard let encoded else {
            return CursorState(marker: Self.cursorMarker, version: 1, phase: .today, today: nil, overdue: nil)
        }
        let standard = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - standard.count % 4) % 4)
        guard encoded.count <= 1_024,
              let data = Data(base64Encoded: standard + padding),
              let state = try? JSONDecoder().decode(CursorState.self, from: data),
              state.marker == Self.cursorMarker,
              state.version == 1 else { throw ReadError.invalidResponse }
        return state
    }

    private func encodeCursor(_ state: CursorState) -> String? {
        let normalized = CursorState(marker: Self.cursorMarker, version: 1, phase: state.phase,
                                     today: state.today, overdue: state.overdue)
        guard let data = try? JSONEncoder().encode(normalized) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
