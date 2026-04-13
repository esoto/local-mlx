import Foundation
import SwiftData

/// An image attached to a chat `Message`. Stored separately from the
/// message so that we can mark the blob for external storage, which
/// keeps image bytes out of the SQLite file and prevents chats from
/// bloating the main store. One `Message` can have many attachments.
@Model
final class MessageAttachment: Identifiable {
    @Attribute(.unique) var id: UUID

    /// When the attachment was added, used for stable ordering inside a
    /// single message (drop two images back-to-back → the second ends
    /// up after the first).
    var createdAt: Date

    /// MIME type string used when embedding the image into a
    /// `data:<mime>;base64,...` URL on the wire. Typically
    /// `"image/jpeg"` or `"image/png"`.
    var mimeType: String

    /// Raw image bytes. `.externalStorage` tells SwiftData to keep these
    /// in a separate file under the store's support directory instead
    /// of stuffing them into the SQLite blob column.
    @Attribute(.externalStorage) var data: Data

    /// Optional rendered size, captured at drop time so the UI can
    /// reserve space for the thumbnail without re-decoding the bytes
    /// on every layout pass.
    var width: Int?
    var height: Int?

    /// Back-reference to the owning message; nulled out on cascade
    /// delete. The relationship is declared on `Message.attachments`.
    var message: Message?

    init(id: UUID = UUID(),
         createdAt: Date = .now,
         mimeType: String,
         data: Data,
         width: Int? = nil,
         height: Int? = nil,
         message: Message? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.mimeType = mimeType
        self.data = data
        self.width = width
        self.height = height
        self.message = message
    }
}
