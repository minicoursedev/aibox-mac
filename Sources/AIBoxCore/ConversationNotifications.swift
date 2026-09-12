import AppKit
import Foundation

@MainActor
private final class ConversationMenuItem: NSMenuItem {
    var onOpened: (() -> Void)?
}

public enum CodexConversationLink {
    public static func url(threadID: String) -> URL? {
        guard !threadID.isEmpty else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        guard let segment = threadID.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "codex://threads/" + segment)
    }
}

/// Each menu item owns its target ID; opening one never uses the latest notification.
@MainActor
public final class ConversationNotificationMenu: NSObject {
    private let openURL: (URL) -> Bool
    private let onFailure: (String) -> Void

    public init(openURL: @escaping (URL) -> Bool, onFailure: @escaping (String) -> Void) {
        self.openURL = openURL
        self.onFailure = onFailure
    }

    public func item(notification: TurnCompletion, title: String, onOpened: (() -> Void)? = nil) -> NSMenuItem {
        let item = ConversationMenuItem(title: title, action: #selector(openConversation(_:)), keyEquivalent: "")
        item.onOpened = onOpened
        item.target = self
        item.representedObject = notification.threadID
        item.toolTip = String(localized: "\(String(notification.eventLabel))\n\(String(notification.displayText))\nConversation: \(String(notification.threadID))\nClick to open this conversation", bundle: AppLanguage.bundle)
        return item
    }

    @objc private func openConversation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let url = CodexConversationLink.url(threadID: id) else {
            onFailure(String(localized: "This notification has no conversation ID to open.", bundle: AppLanguage.bundle))
            return
        }
        guard openURL(url) else {
            onFailure(String(localized: "macOS could not open the Codex conversation. Make sure Codex App is installed.", bundle: AppLanguage.bundle))
            return
        }
        (sender as? ConversationMenuItem)?.onOpened?()
    }
}
