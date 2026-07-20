import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A minimal, blocking HTTP/1.1 server bound to **127.0.0.1** only. Reads one
/// POST body per connection, hands it to `handler`, and writes the returned JSON
/// back. Single-threaded on purpose — the agent handles one command at a time.
struct HTTPServer {
    private let listenFD: Int32

    enum ServerError: Error { case socketFailed, bindFailed, listenFailed }

    init(port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")   // loopback only

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(fd); throw ServerError.bindFailed }
        guard listen(fd, 8) == 0 else { close(fd); throw ServerError.listenFailed }
        self.listenFD = fd
    }

    /// Accepts connections forever, calling `handler` with each request body.
    func serve(_ handler: (Data) -> Data) -> Never {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { continue }
            // Bound each connection: the token is only checked after the body is
            // read, so without a timeout an unauthenticated peer that connects
            // and stalls would wedge this single-threaded loop for the whole run.
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let request = readAll(clientFD)
            let body = Self.httpBody(of: request)
            let responseBody = handler(body)
            write(clientFD, Self.httpResponse(responseBody))
            close(clientFD)
        }
    }

    // MARK: - I/O

    private func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Read headers, then exactly Content-Length bytes of body.
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }   // EOF, error, or the recv timeout fired
            data.append(contentsOf: buffer[0..<bytesRead])
            if let headerEnd = Self.headerEnd(in: data) {
                let length = Self.contentLength(in: data)
                if data.count - headerEnd >= length { break }
            }
        }
        return data
    }

    private func write(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while offset < data.count {
                let written = Darwin.write(fd, base + offset, data.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }

    // MARK: - Tiny HTTP parsing/formatting

    private static let separator = Data("\r\n\r\n".utf8)

    static func headerEnd(in data: Data) -> Int? {
        guard let range = data.range(of: separator) else { return nil }
        return range.upperBound
    }

    static func contentLength(in data: Data) -> Int {
        guard let headerEnd = headerEnd(in: data),
              let headers = String(data: data[..<headerEnd], encoding: .utf8) else { return 0 }
        for line in headers.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    static func httpBody(of data: Data) -> Data {
        guard let headerEnd = headerEnd(in: data) else { return Data() }
        return data[headerEnd...]
    }

    static func httpResponse(_ body: Data) -> Data {
        let headers = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(body)
        return response
    }
}
