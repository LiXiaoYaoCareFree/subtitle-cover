import Foundation

private var childProcess: Process?

#if os(macOS)
import Dispatch
import Darwin

private var signalSources: [DispatchSourceSignal] = []
#endif

private func runProcessAndCapture(_ executable: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, output)
    } catch {
        return (1, "")
    }
}

private func ensureSwiftProductBuilt(_ product: String) -> Bool {
    #if os(macOS)
    let (status, _) = runProcessAndCapture(
        "/usr/bin/env",
        ["swift", "build", "--product", product]
    )
    #elseif os(Windows)
    let (status, _) = runProcessAndCapture(
        "cmd.exe",
        ["/C", "swift", "build", "--product", product]
    )
    #else
    let status: Int32 = 1
    #endif
    return status == 0
}

private func findSwiftProductBinary(_ product: String) -> String? {
    guard ensureSwiftProductBuilt(product) else { return nil }
    #if os(macOS)
    let (status, output) = runProcessAndCapture(
        "/usr/bin/env",
        ["swift", "build", "--product", product, "--show-bin-path"]
    )
    #elseif os(Windows)
    let (status, output) = runProcessAndCapture(
        "cmd.exe",
        ["/C", "swift", "build", "--product", product, "--show-bin-path"]
    )
    #else
    let status: Int32 = 1
    let output = ""
    #endif

    guard status == 0 else { return nil }
    let binPath = output
        .split(whereSeparator: \.isNewline)
        .last
        .map(String.init)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let binPath, !binPath.isEmpty else { return nil }
    return "\(binPath)/\(product)"
}

@discardableResult
private func runManagedProcess(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    childProcess = process

    do {
        try process.run()
        process.waitUntilExit()
        childProcess = nil
        return process.terminationStatus
    } catch {
        childProcess = nil
        fputs("启动失败: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

#if os(macOS)
private func stopChildProcess(signal: Int32) {
    guard let process = childProcess, process.isRunning else { return }
    let pid = pid_t(process.processIdentifier)
    _ = kill(pid, signal)
    usleep(300_000)
    if process.isRunning {
        _ = kill(pid, SIGTERM)
        usleep(300_000)
    }
    if process.isRunning {
        _ = kill(pid, SIGKILL)
    }
}

private func installSignalForwarding() {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    for sig in [SIGINT, SIGTERM] {
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler {
            stopChildProcess(signal: sig)
            exit(130)
        }
        source.resume()
        signalSources.append(source)
    }
}
#endif

#if os(macOS)
installSignalForwarding()
let status: Int32
if let binary = findSwiftProductBinary("SubtitleCover") {
    status = runManagedProcess(binary, [])
} else {
    status = runManagedProcess("/usr/bin/env", ["swift", "run", "SubtitleCover"])
}
#elseif os(Windows)
let status: Int32
if let binary = findSwiftProductBinary("SubtitleCoverWindows") {
    status = runManagedProcess(binary, [])
} else {
    status = runManagedProcess("cmd.exe", ["/C", "swift", "run", "SubtitleCoverWindows"])
}
#else
fputs("当前系统暂不支持自动启动。\n", stderr)
let status: Int32 = 1
#endif

exit(status)
