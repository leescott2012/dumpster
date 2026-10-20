import Foundation
import SwiftData

@Model
final class DumpChatMessage {

    @Attribute(.unique) var id: String
    var dumpId: String
    var role: String              // "user" or "assistant"
    var text: String
    var actionsJSON: String?      // Serialized [ChatAction] for assistant messages
    var createdAt: Date
    /// Valet suggested these actions but nothing has moved yet (user must tap Apply).
    var proposed: Bool = false
    /// JSON {ids, vibe} of the dump before this message's actions ran — powers Undo.
    var undoJSON: String?
    var undone: Bool = false

    init(
        dumpId: String,
        role: String,
        text: String,
        actionsJSON: String? = nil
    ) {
        self.id = UUID().uuidString
        self.dumpId = dumpId
        self.role = role
        self.text = text
        self.actionsJSON = actionsJSON
        self.createdAt = Date()
    }
}
