import Foundation
import NIO

struct AnyError: Error {}

final class SMTPClientOutboundHandler: MessageToByteEncoder {
    public typealias OutboundIn = SMTPClientMessage
    
    init() {}
    
    public func encode(data: SMTPClientMessage, out: inout ByteBuffer) throws {
        switch data {
        case .helo(let hostname):
            out.writeStaticString("HELO ")
            out.writeString(hostname)
        case .ehlo(let hostname):
            out.writeStaticString("EHLO ")
            out.writeString(hostname)
        case .custom(let request):
            out.writeString(request.text)
        case .startMail(let mail):
            out.writeStaticString("MAIL FROM: <")
            out.writeString(mail.from.email)
            out.writeString("> BODY=8BITMIME")
        case .mailRecipient(let address):
            out.writeString("RCPT TO: <\(address)>")
        case .startMailData:
            out.writeStaticString("DATA")
        case .mailData(let mail):
            out.writeString(createRawMailText(mail))
        case .starttls:
            out.writeStaticString("STARTTLS")
        case .authenticatePlain:
            out.writeStaticString("AUTH PLAIN")
        case .authenticateLogin:
            out.writeStaticString("AUTH LOGIN")
        case .authenticateCramMd5:
            out.writeStaticString("AUTH CRAM-MD5")
        case .authenticateXOAuth2(let credentials):
            out.writeStaticString("AUTH XOAUTH2 ")
            out.writeString(credentials)
        case .authenticateUser(let user):
            out.writeString(user.base64Encoded)
        case .authenticatePassword(let password):
            out.writeString(password.base64Encoded)
        case .quit:
            out.writeStaticString("QUIT")
        }
        
        out.writeInteger(cr)
        out.writeInteger(lf)
    }

    private func createRawMailText(_ mail: Mail) -> String {
        var rawText = ""
        for header in mail.headers {
            rawText += "\(header.key): \(header.value)\r\n"
        }

        let mixedBoundary = self.boundary()
        rawText += "Content-Type: multipart/mixed; boundary=\"\(mixedBoundary)\"\r\n\r\n"
        rawText += "--\(mixedBoundary)\r\n"
        rawText += "Content-Type: text/plain; charset=\"utf-8\"\r\n"
        rawText += "Content-Transfer-Encoding: 7bit\r\n\r\n"
        rawText += "\(mail.text)\r\n\r\n"

        for attachment in mail.attachments {
            rawText += "--\(mixedBoundary)\r\n"
            rawText += "Content-Type: \(attachment.contentType)\r\n"
            rawText += "Content-Transfer-Encoding: base64\r\n"
            rawText += "Content-Disposition: \(attachment.disposition.rawValue); filename=\"\(attachment.name.mimeEncoded ?? attachment.name)\"\r\n\r\n"
            rawText += "\(attachment.data.base64EncodedString(options: .lineLength76Characters))\r\n\r\n"
        }

        rawText += "--\(mixedBoundary)--\r\n."

        return rawText
    }

    private func boundary() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

final class SMTPClientInboundHandler: ByteToMessageDecoder {
    public typealias InboundOut = Never
    let context: SMTPClientContext
    
    init(context: SMTPClientContext) {
        self.context = context
    }
    
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        var messages = [SMTPServerMessage]()
        
        while buffer.readableBytes > 0 {
            guard let responseCode = try getResponseCode(buffer: &buffer) else {
                throw SMTPError.incompleteMessage
            }
            
            guard let message = try getResponseMessage(buffer: &buffer) else {
                throw SMTPError.incompleteMessage
            }
            
            messages.append(SMTPServerMessage(code: responseCode, message: message))
        }

        self.context.promise?.succeed(messages)
        return .continue
    }
    
    func getResponseCode(buffer: inout ByteBuffer) throws -> Int? {
        guard let code = buffer.readString(length: 3) else {
            throw SMTPError.invalidCode(nil)
        }
        
        guard let responseCode = Int(code) else {
            throw SMTPError.invalidCode(code)
        }
        
        return responseCode
    }
    
    func getResponseMessage(buffer: inout ByteBuffer) throws -> String? {
        guard
            buffer.readableBytes >= 2,
            let bytes = buffer.getBytes(
                at: buffer.readerIndex,
                length: buffer.readableBytes
            )
        else {
            return nil
        }
        
        for i in 0..<bytes.count - 1 {
            if bytes[i] == cr && bytes[i + 1] == lf {
                guard
                    let messageBytes = buffer.readBytes(length: i),
                    var message = String(bytes: messageBytes, encoding: .utf8)
                else {
                    throw SMTPError.invalidMessage
                }
                
                buffer.moveReaderIndex(forwardBy: 2)
                
                if message.first == " " || message.first == "-" {
                    message.removeFirst()
                }
                
                return message
            }
        }
        
        return nil
    }
    
    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        return try decode(context: context, buffer: &buffer)
    }
}
