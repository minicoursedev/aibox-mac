import Foundation

/// Selection is newest-unopened by notification arrival order, not by thread ID.
@MainActor
public final class ConversationAlertFlow {
    public let history: CompletionHistory
    private let setPattern: (BoxLightPattern) -> Void
    private let openURL: (URL) -> Bool
    private let onFailure: (String) -> Void

    public init(history: CompletionHistory, setPattern: @escaping (BoxLightPattern) -> Void,
                openURL: @escaping (URL) -> Bool, onFailure: @escaping (String) -> Void) {
        self.history = history
        self.setPattern = setPattern
        self.openURL = openURL
        self.onFailure = onFailure
    }

    public func receive(_ notification: TurnCompletion) {
        history.receive(notification)
        updatePattern()
    }

    public func didOpen(_ id: UUID) {
        history.markOpened(id)
        updatePattern()
    }

    private func updatePattern() {
        guard let notification = history.latestUnopened?.notification else {
            setPattern(.idle)
            return
        }
        setPattern(notification.type == "PermissionRequest" || notification.type == "UserInputRequest" ? .permission : .completion)
    }

    public func shake() {
        guard let record = history.latestUnopened else { return }
        guard let url = CodexConversationLink.url(threadID: record.notification.threadID), openURL(url) else {
            onFailure("macOS 無法開啟 Codex 對話；此通知仍保留為待開啟。")
            return
        }
        didOpen(record.id)
    }
}
