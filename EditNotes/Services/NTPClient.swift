import Foundation
import Network
import os

/// Minimal SNTP client: measures how far the local clock is from an NTP server.
nonisolated enum NTPClient {
    struct Sample: Sendable {
        /// Seconds to add to the local clock to get server time.
        let offset: TimeInterval
        let delay: TimeInterval
    }

    enum NTPError: LocalizedError {
        case timeout, badResponse

        var errorDescription: String? {
            switch self {
            case .timeout: "No reply from server"
            case .badResponse: "Invalid reply from server"
            }
        }
    }

    private static let epochOffset: TimeInterval = 2_208_988_800

    /// Takes several samples and returns the one with the shortest round trip.
    static func measure(host: String, samples: Int = 4) async throws -> Sample {
        var best: Sample?
        var lastError: Error = NTPError.timeout
        for _ in 0..<samples {
            do {
                let sample = try await query(host: host)
                if best == nil || sample.delay < best!.delay { best = sample }
            } catch {
                lastError = error
            }
        }
        guard let best else { throw lastError }
        return best
    }

    static func query(host: String, timeout: TimeInterval = 2) async throws -> Sample {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 123, using: .udp)
        let queue = DispatchQueue(label: "EditNotes.NTP")
        let finished = OSAllocatedUnfairLock(initialState: false)

        return try await withCheckedThrowingContinuation { continuation in
            let finish: @Sendable (Result<Sample, Error>) -> Void = { result in
                let isFirst = finished.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                guard isFirst else { return }
                connection.cancel()
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var packet = Data(count: 48)
                    packet[0] = 0x23 // LI 0, version 4, mode 3 (client)
                    let t0 = Date().timeIntervalSince1970
                    write(timestamp: t0, to: &packet, at: 40)
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error { finish(.failure(error)) }
                    })
                    connection.receiveMessage { data, _, _, error in
                        let t3 = Date().timeIntervalSince1970
                        guard let data, data.count >= 48, data[data.startIndex + 1] != 0 else {
                            finish(.failure(error ?? NTPError.badResponse))
                            return
                        }
                        let t1 = read(timestampFrom: data, at: 32)
                        let t2 = read(timestampFrom: data, at: 40)
                        finish(.success(Sample(offset: ((t1 - t0) + (t2 - t3)) / 2,
                                               delay: (t3 - t0) - (t2 - t1))))
                    }
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(NTPError.timeout)) }
        }
    }

    private static func write(timestamp unix: TimeInterval, to packet: inout Data, at offset: Int) {
        let ntp = unix + epochOffset
        let seconds = UInt32(ntp)
        let fraction = UInt32((ntp - Double(seconds)) * 4_294_967_296)
        for i in 0..<4 {
            packet[offset + i] = UInt8(truncatingIfNeeded: seconds >> (24 - 8 * i))
            packet[offset + 4 + i] = UInt8(truncatingIfNeeded: fraction >> (24 - 8 * i))
        }
    }

    private static func read(timestampFrom data: Data, at offset: Int) -> TimeInterval {
        var seconds: UInt32 = 0
        var fraction: UInt32 = 0
        for i in 0..<4 {
            seconds = seconds << 8 | UInt32(data[data.startIndex + offset + i])
            fraction = fraction << 8 | UInt32(data[data.startIndex + offset + 4 + i])
        }
        return Double(seconds) - epochOffset + Double(fraction) / 4_294_967_296
    }
}
