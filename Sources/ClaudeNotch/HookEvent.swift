import Foundation

/// En-têtes de contexte ajoutés par le script de hook (variables d'environnement du hook).
struct HookHeaders {
    var ppid: pid_t?
    var termProgram: String?
    var bundleId: String?
    var entrypoint: String?
    var taskListId: String?
    var configDir: String?

    init(_ headers: [String: String] = [:]) {
        func value(_ key: String) -> String? {
            guard let raw = headers[key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            return raw
        }
        ppid = value("x-claude-ppid").flatMap { pid_t($0) }
        termProgram = value("x-term-program")
        bundleId = value("x-bundle-id")
        entrypoint = value("x-entrypoint")
        taskListId = value("x-task-list-id")
        configDir = value("x-config-dir")
    }
}

/// Événement de hook Claude Code.
/// Tout est optionnel et lu à la demande dans le JSON brut : un champ absent ou d'un type inattendu
/// donne `nil`, jamais un plantage.
struct HookEvent {
    let raw: [String: Any]
    let headers: HookHeaders

    init?(data: Data, headers: HookHeaders = HookHeaders()) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else { return nil }
        self.init(raw: dict, headers: headers)
    }

    init(raw: [String: Any], headers: HookHeaders = HookHeaders()) {
        self.raw = raw
        self.headers = headers
    }

    // MARK: - Champs communs

    var name: String { string("hook_event_name") ?? "" }
    var sessionId: String? { string("session_id") }
    var transcriptPath: String? { string("transcript_path") }
    var cwd: String? { string("cwd") }
    var permissionMode: String? { string("permission_mode") }
    var agentId: String? { string("agent_id") }
    var agentType: String? { string("agent_type") }

    // MARK: - Champs par événement

    /// UserPromptSubmit
    var prompt: String? { string("prompt") }
    /// Stop, SubagentStop
    var lastAssistantMessage: String? { string("last_assistant_message") }
    /// SessionStart : startup / resume / clear / compact
    var source: String? { string("source") }
    var sessionTitle: String? { string("session_title") }
    var model: String? {
        if let name = string("model") { return name }
        if let model = raw["model"] as? [String: Any] {
            return (model["display_name"] as? String) ?? (model["id"] as? String)
        }
        return nil
    }

    /// PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest
    var toolName: String? { string("tool_name") }
    var toolInput: [String: Any]? { raw["tool_input"] as? [String: Any] }
    var toolResponse: Any? { raw["tool_response"] }
    var toolUseId: String? { string("tool_use_id") }

    /// Notification
    var message: String? { string("message") }
    var title: String? { string("title") }
    var notificationType: String? { string("notification_type") }

    /// PostToolUseFailure, StopFailure
    var errorText: String? {
        for key in ["error", "error_type", "error_message"] {
            if let text = string(key) { return text }
            if let dict = raw[key] as? [String: Any] {
                if let text = (dict["type"] as? String) ?? (dict["message"] as? String) { return text }
            }
        }
        return nil
    }

    /// SessionEnd
    var reason: String? { string("reason") }
    /// PreCompact, PostCompact
    var trigger: String? { string("trigger") }

    /// TaskCreated, TaskCompleted
    var taskId: String? { string("task_id") }
    var taskSubject: String? { string("task_subject", "subject") }

    // MARK: - Lecture tolérante

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let text = raw[key] as? String, !text.isEmpty { return text }
            if let number = raw[key] as? NSNumber { return number.stringValue }
        }
        return nil
    }
}
