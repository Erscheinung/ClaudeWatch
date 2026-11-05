import Foundation
import WatchConnectivity
import Combine

/// Foreground handoff avoids leaving credentials in an application-context or transfer queue.
final class CompanionConnection: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "Open ClaudeWatch on both your iPhone and watch."
    @Published private(set) var isSending = false
    #if os(watchOS)
    var receiveSetup: ((CompanionSetup) -> Bool)?
    #endif
    private var session: WCSession?
    private var operationID = UUID()

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            status = "Watch connection is unavailable on this device."
            return
        }
        session = .default
        session?.delegate = self
        session?.activate()
    }

    #if os(iOS)
    func checkConnection() {
        guard !isSending else { return }
        guard let session, session.activationState == .activated, session.isReachable else {
            status = "Open ClaudeWatch on your paired watch, then check again."
            return
        }
        let id = UUID()
        operationID = id
        status = "Checking watch connection…"
        session.sendMessage(["probe": true], replyHandler: { [weak self] reply in
            let ready = reply["ready"] as? Bool == true
            DispatchQueue.main.async {
                guard let self, self.operationID == id else { return }
                self.status = ready ? "Watch connected and ready for setup." : "Open ClaudeWatch on your watch, then check again."
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.operationID == id else { return }
                self.status = "Could not reach your watch. Open both apps and try again."
            }
        })
    }

    func send(_ setup: CompanionSetup) {
        guard !isSending else { return }
        operationID = UUID()
        guard setup.isValid, let data = try? JSONEncoder().encode(setup) else {
            status = "Verify your key and select a model first."
            return
        }
        guard data.count <= 60_000 else {
            status = "The model list is too large to transfer. Try verifying again later."
            return
        }
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled, session.isReachable else {
            status = "Open ClaudeWatch on your paired watch, then tap Send to Watch again."
            return
        }
        isSending = true
        status = "Sending to your watch…"
        session.sendMessage(["setup": data], replyHandler: { [weak self] reply in
            let saved = reply["saved"] as? Bool == true
            DispatchQueue.main.async {
                self?.isSending = false
                self?.status = saved ? "Saved on your watch. You can start speaking." : "Your watch could not save the key. Try again."
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.isSending = false
                self?.status = "The transfer did not finish. Open both apps and try again."
            }
        })
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if error != nil { self?.status = "Could not connect. Open both apps and try again." }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        #if os(watchOS)
        if message["probe"] as? Bool == true {
            DispatchQueue.main.async { [weak self] in
                replyHandler(["ready": self?.receiveSetup != nil])
            }
            return
        }
        guard let data = message["setup"] as? Data, data.count <= 60_000,
              let setup = try? JSONDecoder().decode(CompanionSetup.self, from: data), setup.isValid else {
            replyHandler(["saved": false])
            return
        }
        DispatchQueue.main.async { [weak self] in
            let saved = self?.receiveSetup?(setup) == true
            self?.status = saved ? "Key saved from iPhone." : "Could not save the key. Try again from iPhone."
            replyHandler(["saved": saved])
        }
        #else
        replyHandler(["saved": false])
        #endif
    }
}
