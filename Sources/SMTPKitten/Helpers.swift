import NIO
import Foundation

let cr: UInt8 = 0x0d
let lf: UInt8 = 0x0a
fileprivate let smtpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss ZZZ"
    return formatter
}()

extension String {
    var base64Encoded: String {
        Data(utf8).base64EncodedString()
    }

    var mimeEncoded: String? {
        guard let encoded = addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let quoted = encoded
            .replacingOccurrences(of: "%20", with: "_")
            .replacingOccurrences(of: ",", with: "%2C")
            .replacingOccurrences(of: "%", with: "=")
        return "=?UTF-8?Q?\(quoted)?="
    }
}

extension Date {
    var smtpFormatted: String {
        return smtpDateFormatter.string(from: self)
    }
}
