import Foundation

nonisolated enum OSCArgument: Sendable, Equatable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)

    var stringValue: String? {
        if case .string(let s) = self { s } else { nil }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): i
        case .float(let f): Int(f)
        default: nil
        }
    }
}

nonisolated struct OSCMessage: Sendable, Equatable {
    var address: String
    var arguments: [OSCArgument] = []

    /// Decodes a datagram into its messages, unpacking bundles.
    static func parse(_ data: Data) -> [OSCMessage] {
        let bytes = [UInt8](data)
        if bytes.starts(with: Array("#bundle".utf8)) {
            var messages: [OSCMessage] = []
            var pos = 16
            while pos + 4 <= bytes.count {
                let size = Int(readUInt32(bytes, pos))
                pos += 4
                guard size > 0, pos + size <= bytes.count else { break }
                messages += parse(Data(bytes[pos..<pos + size]))
                pos += size
            }
            return messages
        }

        var pos = 0
        guard let address = readString(bytes, &pos), address.hasPrefix("/") else { return [] }
        var message = OSCMessage(address: address)
        guard let tags = readString(bytes, &pos), tags.hasPrefix(",") else { return [message] }
        for tag in tags.dropFirst() {
            switch tag {
            case "i":
                guard pos + 4 <= bytes.count else { return [message] }
                message.arguments.append(.int(Int(Int32(bitPattern: readUInt32(bytes, pos)))))
                pos += 4
            case "f":
                guard pos + 4 <= bytes.count else { return [message] }
                message.arguments.append(.float(Double(Float(bitPattern: readUInt32(bytes, pos)))))
                pos += 4
            case "h":
                guard pos + 8 <= bytes.count else { return [message] }
                message.arguments.append(.int(Int(Int64(bitPattern: readUInt64(bytes, pos)))))
                pos += 8
            case "d":
                guard pos + 8 <= bytes.count else { return [message] }
                message.arguments.append(.float(Double(bitPattern: readUInt64(bytes, pos))))
                pos += 8
            case "s", "S":
                guard let s = readString(bytes, &pos) else { return [message] }
                message.arguments.append(.string(s))
            case "b":
                guard pos + 4 <= bytes.count else { return [message] }
                pos += 4 + (Int(readUInt32(bytes, pos)) + 3) / 4 * 4
            case "t":
                pos += 8
            case "T": message.arguments.append(.bool(true))
            case "F": message.arguments.append(.bool(false))
            case "N", "I": break
            default: return [message]
            }
        }
        return [message]
    }

    private static func readUInt32(_ b: [UInt8], _ p: Int) -> UInt32 {
        UInt32(b[p]) << 24 | UInt32(b[p + 1]) << 16 | UInt32(b[p + 2]) << 8 | UInt32(b[p + 3])
    }

    private static func readUInt64(_ b: [UInt8], _ p: Int) -> UInt64 {
        UInt64(readUInt32(b, p)) << 32 | UInt64(readUInt32(b, p + 4))
    }

    /// Reads a null-terminated string padded to a 4-byte boundary.
    private static func readString(_ b: [UInt8], _ pos: inout Int) -> String? {
        guard pos < b.count, let end = b[pos...].firstIndex(of: 0) else { return nil }
        let string = String(decoding: b[pos..<end], as: UTF8.self)
        pos = (end / 4 + 1) * 4
        return string
    }
}

/// Listens for OSC over UDP on all IPv4 interfaces.
nonisolated final class OSCServer: @unchecked Sendable {
    struct BindError: LocalizedError {
        let port: UInt16
        let code: Int32
        var errorDescription: String? { "Can't listen on UDP port \(port): \(String(cString: strerror(code)))" }
    }

    private let queue = DispatchQueue(label: "EditNotes.OSC")
    private var source: DispatchSourceRead?

    func start(port: UInt16, handler: @escaping @Sendable (OSCMessage) -> Void) throws {
        stop()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw BindError(port: port, code: errno) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw BindError(port: port, code: code)
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = recv(fd, &buffer, buffer.count, 0)
                guard count > 0 else { break }
                OSCMessage.parse(Data(buffer[0..<count])).forEach(handler)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        queue.sync { self.source = source }
    }

    func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
    }
}
