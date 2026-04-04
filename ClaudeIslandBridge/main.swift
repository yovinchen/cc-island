//
//  main.swift
//  ClaudeIslandBridge
//
//  Native Swift CLI that replaces the Python hook script.
//  Reads hook event JSON from stdin and forwards it to the app via Unix socket.
//
//  Usage:
//    claude-island-bridge --source claude   # Claude Code hook
//    claude-island-bridge --source codex    # Codex CLI hook
//    claude-island-bridge --source gemini   # Gemini CLI hook
//    claude-island-bridge --source cursor   # Cursor hook
//    claude-island-bridge --source copilot  # Copilot hook
//

import Foundation

// MARK: - Argument Parsing

func parseSource() -> String {
    let args = CommandLine.arguments
    for i in 0..<args.count {
        if args[i] == "--source", i + 1 < args.count {
            return args[i + 1]
        }
    }
    return "claude"
}

// MARK: - Main

let source = parseSource()
let ttyPath = TTYDetector.detectTTY()
let ppid = ProcessInfo.processInfo.processIdentifier

// Read stdin
guard let inputData = try? FileHandle.standardInput.availableData,
      !inputData.isEmpty else {
    exit(0)
}

guard let inputJSON = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
    exit(0)
}

// Map the event to unified protocol
let payload = EventMapper.map(input: inputJSON, source: source, tty: ttyPath, ppid: Int(ppid))

// Serialize payload
guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
    exit(0)
}

// Check if this is a permission request that expects a response
let event = payload["event"] as? String ?? ""
let status = payload["status"] as? String ?? ""
let expectsResponse = (event == "PermissionRequest" && status == "waiting_for_approval")

// Send to socket and optionally wait for response
let socketPath = ProcessInfo.processInfo.environment["CLAUDE_ISLAND_SOCKET_PATH"]
    ?? "/tmp/claude-island.sock"

let client = SocketClient(path: socketPath)

if expectsResponse {
    // For permission requests, send and wait for response
    if let responseData = client.sendAndReceive(data: payloadData, timeout: 86400) {
        // Write response to stdout so the calling tool can read it
        FileHandle.standardOutput.write(responseData)
    }
} else {
    // Fire and forget
    client.send(data: payloadData)
}

exit(0)
