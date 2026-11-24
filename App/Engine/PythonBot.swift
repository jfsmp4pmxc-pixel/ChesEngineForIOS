import Foundation

// MARK: - Errors

enum PythonBotError: LocalizedError {
    case unavailable(String)
    case failed(String)
    case timeout
    case illegalMove(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let s): return "Python không khả dụng: \(s)"
        case .failed(let s): return "Lỗi bot:\n\(s)"
        case .timeout: return "Bot trả lời quá lâu."
        case .illegalMove(let m): return "Bot trả về nước đi không hợp lệ: \(m)"
        }
    }
}

/// Resumes a continuation at most once (used to race a result against a timeout).
private final class OnceBox<T> {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Never>?

    init(_ c: CheckedContinuation<T, Never>) { cont = c }

    func resume(_ value: T) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

// MARK: - Runtime

/// Embeds CPython (from beeware/Python-Apple-support) by loading Python.framework at
/// runtime, so the app still builds and runs when Python was not bundled.
///
/// A bot is a `.py` file that defines `get_move(fen)` returning a move in UCI
/// ("e2e4", "e7e8q") or SAN ("Nf3") notation.
final class PythonRuntime {
    static let shared = PythonRuntime()

    private typealias InitFn = @convention(c) (Int32) -> Void
    private typealias RunFn = @convention(c) (UnsafePointer<CChar>) -> Int32
    private typealias EnsureFn = @convention(c) () -> Int32
    private typealias ReleaseFn = @convention(c) (Int32) -> Void
    private typealias SaveFn = @convention(c) () -> UnsafeMutableRawPointer?

    private let queue = DispatchQueue(label: "chess.python", qos: .userInitiated)
    private var ready = false
    private var failure: String?
    private var run: RunFn?
    private var ensure: EnsureFn?
    private var release: ReleaseFn?

    private init() {}

    private var frameworkBinary: String {
        return (Bundle.main.privateFrameworksPath ?? "") + "/Python.framework/Python"
    }

    private var pythonHome: String { Bundle.main.bundlePath + "/python" }

    /// nil when Python looks usable, otherwise the reason it is not.
    var unavailableReason: String? {
        if let f = failure { return f }
        if !FileManager.default.fileExists(atPath: frameworkBinary) {
            return "bản dựng này không kèm môi trường Python."
        }
        if !FileManager.default.fileExists(atPath: pythonHome + "/lib") {
            return "thiếu thư viện chuẩn Python trong ứng dụng."
        }
        return nil
    }

    // MARK: Bootstrap (runs on `queue`)

    private static let helperSource = #"""
import json, os, sys, traceback, importlib.util
_catnip_cache = {}
def _catnip_call(req_path):
    out_path = req_path + ".out"
    try:
        with open(req_path, "r", encoding="utf-8") as f:
            req = json.load(f)
        path = req["path"]
        fen = req["fen"]
        mtime = os.path.getmtime(path)
        entry = _catnip_cache.get(path)
        if entry is None or entry[0] != mtime:
            folder = os.path.dirname(path)
            if folder and folder not in sys.path:
                sys.path.insert(0, folder)
            spec = importlib.util.spec_from_file_location("catnip_bot_%d" % (abs(hash(path)) % 10**8), path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            entry = (mtime, mod)
            _catnip_cache[path] = entry
        mod = entry[1]
        fn = getattr(mod, "get_move", None) or getattr(mod, "choose_move", None)
        if fn is None:
            raise RuntimeError("Bot phải định nghĩa hàm get_move(fen) và trả về nước đi như 'e2e4'.")
        move = fn(fen)
        out = {"move": "" if move is None else str(move).strip()}
    except BaseException:
        out = {"error": traceback.format_exc()[-1500:]}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f)
"""#

    private func bootstrap() -> Bool {
        if ready { return true }
        if failure != nil { return false }
        if let reason = unavailableReason {
            failure = reason
            return false
        }

        let libDir = pythonHome + "/lib"
        guard let version = (try? FileManager.default.contentsOfDirectory(atPath: libDir))?
            .first(where: { $0.hasPrefix("python3") }) else {
            failure = "không có thư mục python3.x trong thư viện đi kèm."
            return false
        }
        let stdlib = libDir + "/" + version
        setenv("PYTHONHOME", pythonHome, 1)
        setenv("PYTHONPATH", stdlib + ":" + stdlib + "/lib-dynload", 1)
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
        setenv("PYTHONUTF8", "1", 1)
        setenv("PYTHONNOUSERSITE", "1", 1)

        guard let handle = dlopen(frameworkBinary, RTLD_NOW | RTLD_GLOBAL) else {
            failure = dlerror().map { String(cString: $0) } ?? "dlopen thất bại."
            return false
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        guard let initEx = symbol("Py_InitializeEx", as: InitFn.self),
              let runSimple = symbol("PyRun_SimpleString", as: RunFn.self),
              let gilEnsure = symbol("PyGILState_Ensure", as: EnsureFn.self),
              let gilRelease = symbol("PyGILState_Release", as: ReleaseFn.self),
              let saveThread = symbol("PyEval_SaveThread", as: SaveFn.self) else {
            failure = "Python.framework thiếu các ký hiệu cần thiết."
            return false
        }

        initEx(0)
        let rc = ConstantString.withCString(PythonRuntime.helperSource) { runSimple($0) }
        // Release the GIL taken by initialisation so any thread can use PyGILState_Ensure.
        _ = saveThread()
        guard rc == 0 else {
            failure = "không nạp được phần hỗ trợ chạy bot."
            return false
        }

        run = runSimple
        ensure = gilEnsure
        release = gilRelease
        ready = true
        return true
    }

    // MARK: Public API

    /// Asks the bot for a move in the given position (UCI or SAN text).
    func move(botPath: String, fen: String, timeout: TimeInterval = 30) async -> Result<String, PythonBotError> {
        return await withCheckedContinuation { (cont: CheckedContinuation<Result<String, PythonBotError>, Never>) in
            let box = OnceBox(cont)
            queue.async {
                box.resume(self.runSync(botPath: botPath, fen: fen))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                box.resume(.failure(.timeout))
            }
        }
    }

    private func runSync(botPath: String, fen: String) -> Result<String, PythonBotError> {
        guard bootstrap(), let run = run, let ensure = ensure, let release = release else {
            return .failure(.unavailable(failure ?? "không rõ lý do."))
        }

        let reqPath = NSTemporaryDirectory() + "catnip-req-\(UUID().uuidString).json"
        let outPath = reqPath + ".out"
        defer {
            try? FileManager.default.removeItem(atPath: reqPath)
            try? FileManager.default.removeItem(atPath: outPath)
        }

        let request: [String: String] = ["path": botPath, "fen": fen]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            return .failure(.failed("Không mã hóa được yêu cầu."))
        }
        do {
            try data.write(to: URL(fileURLWithPath: reqPath))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }

        let state = ensure()
        let code = "_catnip_call('\(reqPath)')"
        _ = code.withCString { run($0) }
        release(state)

        guard let outData = FileManager.default.contents(atPath: outPath),
              let obj = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            return .failure(.failed("Bot không trả lời."))
        }
        if let err = obj["error"] as? String { return .failure(.failed(err)) }
        let move = (obj["move"] as? String) ?? ""
        if move.isEmpty { return .failure(.failed("Bot trả về nước đi rỗng.")) }
        return .success(move)
    }
}

/// Tiny helper so a static string can be passed as a C string.
private enum ConstantString {
    static func withCString<R>(_ s: String, _ body: (UnsafePointer<CChar>) -> R) -> R {
        return s.withCString(body)
    }
}
