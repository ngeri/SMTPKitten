import Foundation
import NIO

public struct Mail {
    public enum ContentType: String {
        case plain = "text/plain"
        case html = "text/html"
    }
    
    public let messageId: String
    public var from: MailUser
    public var to: Set<MailUser>
    public var cc: Set<MailUser>
    public var bcc: Set<MailUser>
    public var subject: String
    public var contentType: ContentType
    public var text: String
    public var attachments: [MailAttachment]
    
    public init(
        from: MailUser,
        to: Set<MailUser>,
        cc: Set<MailUser> = [],
        bcc: Set<MailUser> = [],
        subject: String,
        contentType: ContentType,
        text: String,
        attachments: [MailAttachment]
    ) {
        self.messageId = UUID().uuidString
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.contentType = contentType
        self.text = text
        self.attachments = attachments
    }
    
    internal var headers: [String: String] {
        var headers = [String: String]()
        headers.reserveCapacity(16)
        
        headers["Message-Id"] = "<\(UUID().uuidString)@localhost>"
        headers["Date"] = Date().smtpFormatted
        headers["From"] = from.smtpFormatted
        headers["To"] = to.map { $0.smtpFormatted }
            .joined(separator: ", ")

        if !cc.isEmpty {
            headers["Cc"] = cc.map { $0.smtpFormatted }
                .joined(separator: ", ")
        }

        headers["Subject"] = subject
        headers["MIME-Version"] = "1.0"
        
        return headers
    }
}

public struct MailUser: Hashable, ExpressibleByStringLiteral {
    /// The user's name that is displayed in an email. Optional.
    public let name: String?

    /// The user's email address.
    public let email: String
    
    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }
    
    public init(stringLiteral email: String) {
        self.email = email
        self.name = nil
    }

    var smtpFormatted: String {
        if let name = name {
            return "\(name) <\(email)>"
        } else {
            return "<\(email)>"
        }
    }
}

public struct MailAttachment {
    public enum ContentDisposition: String {
        case inline
        case attachment
    }

    public let name: String
    public let contentType: String
    public let disposition: ContentDisposition
    public let data: Data

    public init(name: String, contentType: String, disposition: ContentDisposition = .attachment, data: Data) {
        self.name = name
        self.contentType = contentType
        self.disposition = disposition
        self.data = data
    }
}
