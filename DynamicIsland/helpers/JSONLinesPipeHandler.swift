// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

actor JSONLinesPipeHandler {
    private let pipe = Pipe()
    private var continuation: AsyncStream<Data>.Continuation?
    func getPipe() -> Pipe { pipe }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        let file = pipe.fileHandleForReading
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.continuation = continuation
        file.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { continuation.finish() } else { continuation.yield(data) }
        }
        var buffer = Data()
        for await chunk in stream {
            if Task.isCancelled { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if let decoded = try? JSONDecoder().decode(T.self, from: line) { await onLine(decoded) }
            }
        }
        file.readabilityHandler = nil
        self.continuation = nil
    }
    func close() {
        pipe.fileHandleForReading.readabilityHandler = nil
        continuation?.finish()
        self.continuation = nil
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
}
