import CryptoKit
import Foundation

/// Direct Todoist v1 GET-only adapter. There is intentionally no write-capable API in this type.
struct TodoistReadService: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let maxTitleLength = 240
    private static let cursorMarker = "ClaudeWatchTodoistRead"
    /// Per-instance HMAC key, so only cursors this adapter issued can be continued.
    /// A model-forged cursor (even one with the right marker) is rejected before any request.
    private let cursorKey: Data

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
        /// Malformed records (missing/wrong-typed fields, out-of-range priority). They are dropped and
        /// reported so coverage is partial; their fields are never guessed.
        let skipped: Int

        enum CodingKeys: String, CodingKey {
            case results
            case nextCursor = "next_cursor"
        }

        private struct LossyTask: Decodable {
            let task: RemoteTask?
            init(from decoder: Decoder) throws { task = try? RemoteTask(from: decoder) }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let lossy = try container.decode([LossyTask].self, forKey: .results)
            results = lossy.compactMap(\.task)
            skipped = lossy.count - results.count
            nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
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

        /// Todoist API v1 sends `duration` as `{"amount": Int, "unit": "minute" | "day"}`.
        struct RemoteDuration: Decodable {
            let amount: Int
            let unit: String
        }

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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            content = try container.decode(String.self, forKey: .content)
            projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
            priority = try container.decodeIfPresent(Int.self, forKey: .priority)
            if let priority, !(1...4).contains(priority) {
                throw DecodingError.dataCorruptedError(forKey: .priority, in: container, debugDescription: "priority out of range")
            }
            due = try container.decodeIfPresent(RemoteDue.self, forKey: .due)
            deadline = try container.decodeIfPresent(RemoteDeadline.self, forKey: .deadline)
            // Prefer the v1 object shape; accept the flat amount + `duration_unit` form as a fallback.
            // An unrecognized duration shape is unknown duration, never a failed page.
            if let object = try? container.decodeIfPresent(RemoteDuration.self, forKey: .duration) {
                duration = object.amount
                durationUnit = object.unit
            } else {
                duration = try? container.decodeIfPresent(Int.self, forKey: .duration)
                durationUnit = try? container.decodeIfPresent(String.self, forKey: .durationUnit)
            }
        }

        func normalized(maxTitleLength: Int, bucket: TodoistTaskBucket) -> TodoistReadTask {
            // Bound by Unicode scalars, not grapheme clusters: one "character" can carry thousands of
            // combining marks, which would defeat both the title bound and the tool-result budget.
            var title = String(content.prefix(maxTitleLength))
            if title.unicodeScalars.count > maxTitleLength {
                title = String(String.UnicodeScalarView(title.unicodeScalars.prefix(maxTitleLength)))
            }
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
        case rateLimited
        case unavailable
        case invalidResponse
    }

    init(
        baseURL: URL = URL(string: "https://api.todoist.com/api/v1")!,
        session: URLSession = TodoistReadService.defaultSession
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cursorKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// The production session keeps the same bounded transport defaults as the rest of the app.
    /// Tests may inject a URLProtocol-backed session so no provider request can escape the harness.
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

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
        var skipped = 0
        func finish(_ status: TodoistReadStatus, _ message: String?, complete: Bool, next: String?) -> TodoistFindTasksResult {
            result(tasks: tasks, request: request, status: status, message: message, complete: complete,
                   nextCursor: next, skipped: skipped, fetchedAt: fetchedAt)
        }
        let repeatedCursor = "Todoist repeated a page cursor, so paging stopped early."
        do {
            if state.phase == .today {
                // Only these three fixed filters are ever sent (no free-form filter from a transcript).
                let dayQuery = ["tomorrow", "7 days"].contains(request.dayQuery ?? "") ? request.dayQuery! : "today"
                let page = try await fetch(query: dayQuery, cursor: state.today, limit: limit, token: token)
                append(page.results, bucket: .dueToday, to: &tasks, seen: &seen)
                skipped += page.skipped
                if let next = page.nextCursor {
                    // A provider cursor that points back at the page just read would loop forever.
                    if next == state.today { return finish(.partial, repeatedCursor, complete: false, next: nil) }
                    state.today = next
                    state.phase = .today
                    return finish(.success, nil, complete: false, next: encodeCursor(state))
                }
                state.today = nil
                state.phase = .overdue
            }

            if request.includeOverdue {
                if tasks.count >= limit {
                    return finish(.success, nil, complete: false, next: encodeCursor(state))
                }
                let pageLimit = max(1, limit - tasks.count)
                let page = try await fetch(query: "overdue", cursor: state.overdue, limit: pageLimit, token: token)
                append(page.results, bucket: .overdue, to: &tasks, seen: &seen)
                skipped += page.skipped
                if let next = page.nextCursor {
                    if next == state.overdue { return finish(.partial, repeatedCursor, complete: false, next: nil) }
                    state.overdue = next
                    state.phase = .overdue
                    return finish(.success, nil, complete: false, next: encodeCursor(state))
                }
            }

            return finish(.success, nil, complete: true, next: nil)
        } catch ReadError.permissionDenied {
            return finish(tasks.isEmpty ? .permissionDenied : .partial,
                          tasks.isEmpty ? "Todoist denied this read. Check the token's data:read access." : "Todoist returned only part of the requested read.",
                          complete: false, next: nil)
        } catch ReadError.rateLimited {
            // No automatic retry: the user can ask again once Todoist's rate limit clears.
            return finish(tasks.isEmpty ? .unavailable : .partial,
                          tasks.isEmpty ? "Todoist is rate limiting reads. Try again shortly." : "Todoist rate limited the read, so only part of it was returned.",
                          complete: false, next: nil)
        } catch is CancellationError {
            return finish(.partial, "The Todoist read was canceled before it completed.", complete: false, next: nil)
        } catch {
            return finish(tasks.isEmpty ? .unavailable : .partial,
                          tasks.isEmpty ? "Todoist is unavailable right now." : "Todoist returned only part of the requested read.",
                          complete: false, next: nil)
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
        if http.statusCode == 429 { throw ReadError.rateLimited }
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
        message: String?, complete: Bool, nextCursor: String?, skipped: Int = 0, fetchedAt: String
    ) -> TodoistFindTasksResult {
        var status = status
        var message = message
        var complete = complete
        if skipped > 0 {
            // Unreadable tasks are dropped, so coverage can never be reported as complete.
            if status == .success { status = .partial }
            complete = false
            let note = "Todoist sent \(skipped) task(s) ClaudeWatch could not read; they were skipped."
            message = message.map { "\($0) \(note)" } ?? note
        }
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
            workload: TodoistWorkloadSignals(tasks: tasks)
        )
    }

    private func decodeCursor(_ encoded: String?) throws -> CursorState {
        guard let encoded else {
            return CursorState(marker: Self.cursorMarker, version: 1, phase: .today, today: nil, overdue: nil)
        }
        let pieces = encoded.split(separator: ".", omittingEmptySubsequences: false)
        guard encoded.count <= 1_024, pieces.count == 2,
              let data = Self.base64URLDecode(String(pieces[0])),
              let signature = Self.base64URLDecode(String(pieces[1])),
              HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: data,
                                                     using: SymmetricKey(data: cursorKey)),
              let state = try? JSONDecoder().decode(CursorState.self, from: data),
              state.marker == Self.cursorMarker,
              state.version == 1 else { throw ReadError.invalidResponse }
        return state
    }

    private func encodeCursor(_ state: CursorState) -> String? {
        let normalized = CursorState(marker: Self.cursorMarker, version: 1, phase: state.phase,
                                     today: state.today, overdue: state.overdue)
        guard let data = try? JSONEncoder().encode(normalized) else { return nil }
        let signature = Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: cursorKey)))
        return "\(Self.base64URLEncode(data)).\(Self.base64URLEncode(signature))"
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        let standard = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - standard.count % 4) % 4)
        return Data(base64Encoded: standard + padding)
    }
}
