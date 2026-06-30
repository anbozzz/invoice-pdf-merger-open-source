import AppKit
import Foundation
import Network
import PDFKit
import Security

struct QQMailImportRequest {
    let emailAddress: String
    let authCode: String
    let daysBack: Int
    let skipTravelPDF: Bool
}

struct QQMailImportResult {
    let pdfURLs: [URL]
    let skippedTravelPDFCount: Int
    let extractedZipCount: Int
    let downloadDirectory: URL
}

enum QQMailImportError: LocalizedError {
    case connectionClosed
    case loginFailed(String)
    case imapCommandFailed(String)
    case zipExtractFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionClosed:
            return "邮箱连接已关闭。"
        case .loginFailed(let message):
            return "QQ 邮箱登录失败，请确认已开启 IMAP 并使用授权码。\(message)"
        case .imapCommandFailed(let message):
            return "邮箱命令执行失败：\(message)"
        case .zipExtractFailed(let filename):
            return "压缩包解压失败：\(filename)"
        }
    }
}

final class QQMailImporter {
    func importRecentInvoices(
        request: QQMailImportRequest,
        progress: @escaping (String) -> Void
    ) async throws -> QQMailImportResult {
        let downloadDirectory = try makeDownloadDirectory()
        let client = IMAPClient(host: "imap.qq.com", port: 993)

        progress("正在连接 imap.qq.com...")
        try await client.connect()
        defer {
            Task {
                try? await client.logout()
            }
        }

        progress("正在登录 QQ 邮箱...")
        try await client.login(email: request.emailAddress, authCode: request.authCode)

        progress("正在读取收件箱...")
        try await client.selectInbox()

        progress("正在筛选近 \(request.daysBack) 日邮件...")
        let uids = try await client.searchUIDs(since: Date().addingTimeInterval(TimeInterval(-request.daysBack * 24 * 60 * 60)))

        var attachments: [MailAttachment] = []
        for (offset, uid) in uids.enumerated() {
            progress("正在读取邮件附件 \(offset + 1)/\(uids.count)...")
            let messageData = try await client.fetchMessage(uid: uid)
            attachments.append(contentsOf: MIMEAttachmentParser.attachments(from: messageData))
        }

        progress("正在处理 PDF 和压缩包...")
        return try AttachmentProcessor.process(
            attachments: attachments,
            downloadDirectory: downloadDirectory,
            skipTravelPDF: request.skipTravelPDF
        )
    }

    private func makeDownloadDirectory() throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = downloads
            .appendingPathComponent("发票PDF合并", isDirectory: true)
            .appendingPathComponent("邮箱导入-\(formatter.string(from: Date()))", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

final class IMAPClient {
    private let host: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "invoice-pdf-merger.imap")
    private var commandIndex = 0
    private var connection: NWConnection?

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func connect() async throws {
        let tls = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tls)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        self.connection = connection

        connection.start(queue: queue)
        _ = try await receiveUntilTextContains(["* OK", "* PREAUTH"])
    }

    func login(email: String, authCode: String) async throws {
        let response = try await sendCommand("LOGIN \(quote(email)) \(quote(authCode))")
        guard response.contains(" OK ") else {
            throw QQMailImportError.loginFailed(response)
        }
    }

    func selectInbox() async throws {
        let response = try await sendCommand("SELECT INBOX")
        guard response.contains(" OK ") else {
            throw QQMailImportError.imapCommandFailed(response)
        }
    }

    func searchUIDs(since date: Date) async throws -> [Int] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MMM-yyyy"
        let response = try await sendCommand("UID SEARCH SINCE \(formatter.string(from: date))")
        guard response.contains(" OK ") else {
            throw QQMailImportError.imapCommandFailed(response)
        }

        return response
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("* SEARCH") }?
            .components(separatedBy: .whitespaces)
            .compactMap { Int($0) } ?? []
    }

    func fetchMessage(uid: Int) async throws -> Data {
        let tag = nextTag()
        try await sendRaw("\(tag) UID FETCH \(uid) BODY.PEEK[]\r\n")
        let response = try await receiveUntilTextContains(["\(tag) OK", "\(tag) NO", "\(tag) BAD"])
        guard String(decoding: response, as: UTF8.self).contains("\(tag) OK") else {
            throw QQMailImportError.imapCommandFailed(String(decoding: response, as: UTF8.self))
        }
        return extractFirstLiteral(from: response) ?? response
    }

    func logout() async throws {
        _ = try await sendCommand("LOGOUT")
        connection?.cancel()
    }

    private func sendCommand(_ command: String) async throws -> String {
        let tag = nextTag()
        try await sendRaw("\(tag) \(command)\r\n")
        let response = try await receiveUntilTextContains(["\(tag) OK", "\(tag) NO", "\(tag) BAD"])
        return String(decoding: response, as: UTF8.self)
    }

    private func nextTag() -> String {
        commandIndex += 1
        return "A\(String(format: "%04d", commandIndex))"
    }

    private func quote(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func sendRaw(_ text: String) async throws {
        guard let data = text.data(using: .utf8), let connection else {
            throw QQMailImportError.connectionClosed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func receiveUntilTextContains(_ markers: [String]) async throws -> Data {
        var response = Data()

        while true {
            let chunk = try await receiveChunk()
            response.append(chunk)
            let text = String(decoding: response, as: UTF8.self)
            if markers.contains(where: { text.contains($0) }) {
                return response
            }
        }
    }

    private func receiveChunk() async throws -> Data {
        guard let connection else {
            throw QQMailImportError.connectionClosed
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.isEmpty == false {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: QQMailImportError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private func extractFirstLiteral(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        var index = 0

        while index < bytes.count {
            guard bytes[index] == 123 else {
                index += 1
                continue
            }

            var cursor = index + 1
            var digits = ""
            while cursor < bytes.count, bytes[cursor] >= 48, bytes[cursor] <= 57 {
                digits.append(Character(UnicodeScalar(bytes[cursor])))
                cursor += 1
            }

            guard
                cursor + 2 < bytes.count,
                bytes[cursor] == 125,
                bytes[cursor + 1] == 13,
                bytes[cursor + 2] == 10,
                let length = Int(digits)
            else {
                index += 1
                continue
            }

            let start = cursor + 3
            let end = start + length
            guard end <= data.count else {
                return nil
            }

            return data.subdata(in: start..<end)
        }

        return nil
    }
}

struct MailAttachment {
    let filename: String
    let data: Data
}

enum MIMEAttachmentParser {
    static func attachments(from data: Data) -> [MailAttachment] {
        let text = normalizedMessageText(from: data)
        return boundaryParts(in: text).compactMap(parseAttachmentPart)
    }

    private static func normalizedMessageText(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func boundaryParts(in text: String) -> [String] {
        var parts: [String] = []
        var currentLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("--"), line.count > 4 {
                if currentLines.isEmpty == false {
                    parts.append(currentLines.joined(separator: "\n"))
                    currentLines.removeAll()
                }
                continue
            }

            currentLines.append(line)
        }

        if currentLines.isEmpty == false {
            parts.append(currentLines.joined(separator: "\n"))
        }

        return parts
    }

    private static func parseAttachmentPart(_ partText: String) -> MailAttachment? {
        guard
            let data = partText.data(using: .utf8),
            let (headerText, bodyData) = splitHeaderAndBody(data)
        else {
            return nil
        }

        let headers = parseHeaders(headerText)
        let contentType = headers["content-type"] ?? ""
        let disposition = headers["content-disposition"] ?? ""
        let filename = decodedFilename(from: disposition) ?? decodedFilename(from: contentType)
        guard let filename else {
            return nil
        }

        let lowercasedFilename = filename.lowercased()
        guard lowercasedFilename.hasSuffix(".pdf") || lowercasedFilename.hasSuffix(".zip") else {
            return nil
        }

        let encoding = (headers["content-transfer-encoding"] ?? "").lowercased()
        let decodedData: Data
        if encoding.contains("base64") {
            decodedData = Data(base64Encoded: bodyText(bodyData).components(separatedBy: .whitespacesAndNewlines).joined()) ?? Data()
        } else if encoding.contains("quoted-printable") {
            decodedData = decodeQuotedPrintable(bodyText(bodyData))
        } else {
            decodedData = bodyData
        }

        guard decodedData.isEmpty == false else {
            return nil
        }

        return MailAttachment(filename: sanitizeFilename(filename), data: decodedData)
    }

    private static func parsePart(_ data: Data) -> [MailAttachment] {
        guard let (headerText, bodyData) = splitHeaderAndBody(data) else {
            return []
        }

        let headers = parseHeaders(headerText)
        let contentType = headers["content-type"] ?? ""

        if contentType.lowercased().contains("multipart/"),
           let boundary = parameter(named: "boundary", in: contentType) {
            return splitMultipartBody(bodyData, boundary: boundary).flatMap(parsePart)
        }

        let disposition = headers["content-disposition"] ?? ""
        let filename = decodedFilename(from: disposition) ?? decodedFilename(from: contentType)
        guard let filename else {
            return []
        }

        let lowercasedFilename = filename.lowercased()
        guard lowercasedFilename.hasSuffix(".pdf") || lowercasedFilename.hasSuffix(".zip") else {
            return []
        }

        let encoding = (headers["content-transfer-encoding"] ?? "").lowercased()
        let decodedData: Data
        if encoding.contains("base64") {
            decodedData = Data(base64Encoded: bodyText(bodyData).components(separatedBy: .whitespacesAndNewlines).joined()) ?? Data()
        } else if encoding.contains("quoted-printable") {
            decodedData = decodeQuotedPrintable(bodyText(bodyData))
        } else {
            decodedData = bodyData
        }

        guard decodedData.isEmpty == false else {
            return []
        }

        return [MailAttachment(filename: sanitizeFilename(filename), data: decodedData)]
    }

    private static func splitHeaderAndBody(_ data: Data) -> (String, Data)? {
        let separators = [
            Data([13, 10, 13, 10]),
            Data([10, 10])
        ]

        for separator in separators {
            if let range = data.range(of: separator) {
                let headerData = data.subdata(in: 0..<range.lowerBound)
                let bodyStart = range.upperBound
                let headerText = String(decoding: headerData, as: UTF8.self)
                return (headerText, data.subdata(in: bodyStart..<data.count))
            }
        }

        return nil
    }

    private static func parseHeaders(_ headerText: String) -> [String: String] {
        var unfolded: [String] = []

        for line in headerText.components(separatedBy: .newlines) {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), let last = unfolded.popLast() {
                unfolded.append(last + line.trimmingCharacters(in: .whitespaces))
            } else {
                unfolded.append(line)
            }
        }

        var headers: [String: String] = [:]
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[String(key)] = value
        }

        return headers
    }

    private static func splitMultipartBody(_ data: Data, boundary: String) -> [Data] {
        let text = bodyText(data)
        let delimiter = "--\(boundary)"
        return text
            .components(separatedBy: delimiter)
            .dropFirst()
            .compactMap { section in
                let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false, trimmed.hasPrefix("--") == false else {
                    return nil
                }
                return trimmed.data(using: .utf8)
            }
    }

    private static func decodedFilename(from header: String) -> String? {
        continuedParameter(prefix: "filename", in: header).map(decodeRFC2231)
            ?? continuedParameter(prefix: "name", in: header).map(decodeRFC2231)
            ?? parameter(named: "filename*", in: header).flatMap(decodeRFC2231)
            ?? parameter(named: "filename", in: header).map(decodeEncodedWords)
            ?? parameter(named: "name*", in: header).flatMap(decodeRFC2231)
            ?? parameter(named: "name", in: header).map(decodeEncodedWords)
    }

    private static func parameter(named name: String, in header: String) -> String? {
        let parts = header.components(separatedBy: ";")
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard pair.count == 2, pair[0].lowercased() == name.lowercased() else {
                continue
            }

            return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        return nil
    }

    private static func continuedParameter(prefix: String, in header: String) -> String? {
        let parts = header.components(separatedBy: ";").dropFirst()
        var segments: [(Int, String)] = []

        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard pair.count == 2 else {
                continue
            }

            let key = pair[0].lowercased()
            guard key.hasPrefix("\(prefix.lowercased())*") else {
                continue
            }

            let suffix = key
                .dropFirst(prefix.count + 1)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*"))

            guard let index = Int(suffix) else {
                continue
            }

            let value = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            segments.append((index, value))
        }

        guard segments.isEmpty == false else {
            return nil
        }

        return segments
            .sorted { $0.0 < $1.0 }
            .map(\.1)
            .joined()
    }

    private static func decodeRFC2231(_ value: String) -> String {
        let parts = value.split(separator: "'", maxSplits: 2).map(String.init)
        guard parts.count == 3 else {
            return value.removingPercentEncoding ?? value
        }
        return parts[2].removingPercentEncoding ?? parts[2]
    }

    private static func decodeEncodedWords(_ value: String) -> String {
        var result = value
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in regex.matches(in: result, range: nsRange).reversed() {
            guard
                let fullRange = Range(match.range(at: 0), in: result),
                let charsetRange = Range(match.range(at: 1), in: result),
                let encodingRange = Range(match.range(at: 2), in: result),
                let payloadRange = Range(match.range(at: 3), in: result)
            else {
                continue
            }

            let charset = String(result[charsetRange]).lowercased()
            let encoding = String(result[encodingRange]).lowercased()
            let payload = String(result[payloadRange])

            let data: Data?
            if encoding == "b" {
                data = Data(base64Encoded: payload)
            } else {
                data = decodeQuotedPrintable(payload.replacingOccurrences(of: "_", with: " "))
            }

            guard let data else {
                continue
            }

            let decoded = string(from: data, charset: charset) ?? payload
            result.replaceSubrange(fullRange, with: decoded)
        }

        return result
    }

    private static func string(from data: Data, charset: String) -> String? {
        if charset.contains("utf-8") {
            return String(data: data, encoding: .utf8)
        }
        if charset.contains("gb") {
            return String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func decodeQuotedPrintable(_ text: String) -> Data {
        var bytes: [UInt8] = []
        let scalars = Array(text.utf8)
        var index = 0

        while index < scalars.count {
            if scalars[index] == 61, index + 2 < scalars.count {
                if scalars[index + 1] == 13 || scalars[index + 1] == 10 {
                    index += 1
                    while index < scalars.count, scalars[index] == 13 || scalars[index] == 10 {
                        index += 1
                    }
                    continue
                }

                let hex = String(bytes: scalars[(index + 1)...(index + 2)], encoding: .ascii) ?? ""
                if let value = UInt8(hex, radix: 16) {
                    bytes.append(value)
                    index += 3
                    continue
                }
            }

            bytes.append(scalars[index])
            index += 1
        }

        return Data(bytes)
    }

    private static func bodyText(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private static func sanitizeFilename(_ filename: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return filename
            .components(separatedBy: forbidden)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AttachmentProcessor {
    static func process(
        attachments: [MailAttachment],
        downloadDirectory: URL,
        skipTravelPDF: Bool
    ) throws -> QQMailImportResult {
        var pdfURLs: [URL] = []
        var skippedTravelPDFCount = 0
        var extractedZipCount = 0

        for attachment in attachments {
            let lowercasedFilename = attachment.filename.lowercased()

            if lowercasedFilename.hasSuffix(".zip") {
                let zipURL = uniqueURL(for: attachment.filename, in: downloadDirectory)
                try attachment.data.write(to: zipURL)
                let extractDirectory = downloadDirectory.appendingPathComponent(zipURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
                try extractZip(zipURL: zipURL, to: extractDirectory)
                extractedZipCount += 1

                for pdfURL in recursivePDFs(in: extractDirectory) {
                    if skipTravelPDF, isTravelDocument(pdfURL) {
                        skippedTravelPDFCount += 1
                    } else {
                        let copiedURL = uniqueURL(for: pdfURL.lastPathComponent, in: downloadDirectory)
                        try? FileManager.default.copyItem(at: pdfURL, to: copiedURL)
                        pdfURLs.append(copiedURL)
                    }
                }
            } else if lowercasedFilename.hasSuffix(".pdf") {
                let pdfURL = uniqueURL(for: attachment.filename, in: downloadDirectory)
                try attachment.data.write(to: pdfURL)

                if skipTravelPDF, isTravelDocument(pdfURL) {
                    skippedTravelPDFCount += 1
                    try? FileManager.default.removeItem(at: pdfURL)
                } else {
                    pdfURLs.append(pdfURL)
                }
            }
        }

        return QQMailImportResult(
            pdfURLs: pdfURLs,
            skippedTravelPDFCount: skippedTravelPDFCount,
            extractedZipCount: extractedZipCount,
            downloadDirectory: downloadDirectory
        )
    }

    private static func extractZip(zipURL: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, directory.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw QQMailImportError.zipExtractFailed(zipURL.lastPathComponent)
        }
    }

    private static func recursivePDFs(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension.lowercased() == "pdf" else {
                return nil
            }
            return url
        }
    }

    private static func isTravelDocument(_ url: URL) -> Bool {
        let filename = url.deletingPathExtension().lastPathComponent.lowercased()
        let text = PDFDocument(url: url)?.string?.lowercased() ?? ""
        let combinedText = filename + "\n" + text

        let flightInvoiceKeywords = [
            "航空运输电子客票行程单",
            "电子客票行程单",
            "航空电子客票",
            "航空公司",
            "航班",
            "机票",
            "客票",
            "民航"
        ]

        if containsAny(flightInvoiceKeywords, in: combinedText) {
            return false
        }

        let rideHailingKeywords = [
            "滴滴",
            "曹操",
            "网约车",
            "t3出行",
            "高德打车",
            "首汽约车",
            "出行行程报销单",
            "出租车"
        ]
        let travelKeywords = ["行程单", "行程报销单", "行程明细", "行程详单", "itinerary", "trip"]

        return containsAny(rideHailingKeywords, in: combinedText)
            && containsAny(travelKeywords, in: combinedText)
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }

    private static func uniqueURL(for filename: String, in directory: URL) -> URL {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var index = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            index += 1
        }

        return candidate
    }
}

final class QQMailCredentialStore {
    static let shared = QQMailCredentialStore()

    private let service = "InvoicePDFMerger.QQMail"
    private let emailAccount = "email"
    private let authCodeAccount = "authCode"

    var emailAddress: String? {
        read(account: emailAccount)
    }

    var authCode: String? {
        read(account: authCodeAccount)
    }

    func save(emailAddress: String, authCode: String) {
        write(emailAddress, account: emailAccount)
        write(authCode, account: authCodeAccount)
    }

    func clear() {
        delete(account: emailAccount)
        delete(account: authCodeAccount)
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
