#if DEBUG
import Darwin
import Foundation

/// Dev only: records how the process ended (signal, normal exit, uncaught exception) in /private/tmp/stash-crash.txt,
/// because crashes under XCUITest don't always leave a crash report.
private let crashFD: Int32 = open("/private/tmp/stash-crash.txt", O_WRONLY | O_CREAT | O_APPEND, 0o644)

private func note(_ s: String) {
    let line = "\(s)\n"
    _ = line.withCString { write(crashFD, $0, strlen($0)) }
}

func installDebugCrashLog() {
    note("--- launched pid \(getpid())")
    for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGTERM, SIGFPE, SIGPIPE] {
        signal(sig) { s in
            note("signal \(s)")
            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 40)
            let n = backtrace(&frames, 40)
            backtrace_symbols_fd(&frames, n, crashFD)
            signal(s, SIG_DFL)
            raise(s)
        }
    }
    atexit { note("atexit (normal exit)") }
    NSSetUncaughtExceptionHandler { e in
        note("uncaught \(e.name.rawValue): \(e.reason ?? "")\n" + e.callStackSymbols.prefix(25).joined(separator: "\n"))
    }
}
#endif
