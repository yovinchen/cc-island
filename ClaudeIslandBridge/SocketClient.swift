//
//  SocketClient.swift
//  ClaudeIslandBridge
//
//  Unix domain socket client for communicating with the main app.
//

import Foundation

class SocketClient {
    let path: String

    init(path: String) {
        self.path = path
    }

    /// Send data and return immediately (fire-and-forget)
    func send(data: Data) {
        guard let fd = connect() else { return }
        defer { close(fd) }

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            _ = Foundation.write(fd, baseAddress, data.count)
        }
    }

    /// Send data and wait for a response (for permission requests)
    func sendAndReceive(data: Data, timeout: TimeInterval) -> Data? {
        guard let fd = connect() else { return nil }
        defer { close(fd) }

        // Set receive timeout
        var tv = timeval()
        tv.tv_sec = Int(timeout)
        tv.tv_usec = 0
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Send
        let sendResult = data.withUnsafeBytes { bytes -> Int in
            guard let baseAddress = bytes.baseAddress else { return -1 }
            return Foundation.write(fd, baseAddress, data.count)
        }
        guard sendResult > 0 else { return nil }

        // Shutdown write side to signal we're done sending
        shutdown(fd, SHUT_WR)

        // Read response
        var buffer = [UInt8](repeating: 0, count: 65536)
        var allData = Data()

        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                allData.append(contentsOf: buffer[0..<bytesRead])
            } else {
                break
            }
        }

        return allData.isEmpty ? nil : allData
    }

    // MARK: - Private

    private func connect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Foundation.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(fd)
            return nil
        }

        return fd
    }
}
