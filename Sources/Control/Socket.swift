import Foundation

// The command line. The app listens on a Unix socket; `control show 3` (the same program, with words)
// connects, sends the words and prints the answer. One request per connection:
//   request: a JSON array of words, then a line break    ["focus", "app", "Safari"]
//   answer:  a JSON object, then a line break            {"output": "..."} or {"error": "..."}
// So any program can talk to Control too: echo '["show", "3"]' | nc -U "$(getconf DARWIN_USER_TEMP_DIR)control.sock"

/// In the user's own temporary folder, which only they can open.
let socketPath: String = {
    var folder = [CChar](repeating: 0, count: Int(PATH_MAX))
    confstr(_CS_DARWIN_USER_TEMP_DIR, &folder, folder.count)
    return URL(fileURLWithPath: String(cString: folder)).appendingPathComponent("control.sock").path
}()

/// `control <words>`: check the words, hand them to the running app, print its answer.
/// Returns the exit status: 0 done, 1 Control said no or is not running, 2 not a command.
func commandLine(_ words: [String]) -> Int32 {
    func fail(_ message: String) { FileHandle.standardError.write(Data("control: \(message)\n".utf8)) }
    if ["help", "-h", "--help"].contains(words.first) {
        print(usage)
        return 0
    }
    // Check here first, so a typo gets the usage without a trip to the app.
    do { _ = try Command(words) } catch {
        fail((error as? CommandError)?.message ?? "\(error)")
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        return 2
    }
    do {
        let output = try ask(words)
        if !output.isEmpty { print(output) }
        return 0
    } catch {
        fail((error as? CommandError)?.message ?? "\(error)")
        return 1
    }
}

/// Send words to the running app and wait for its answer.
func ask(_ words: [String], at path: String = socketPath) throws -> String {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw CommandError("cannot open a socket") }
    defer { close(fd) }
    setOption(fd, SO_NOSIGPIPE, Int32(1))
    // A Control that hangs should not hang the script too.
    setOption(fd, SO_SNDTIMEO, timeval(tv_sec: 5, tv_usec: 0))
    setOption(fd, SO_RCVTIMEO, timeval(tv_sec: 5, tv_usec: 0))
    guard var address = socketAddress(path),
          withUnsafePointer(to: &address, {
              $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
          }) == 0 else { throw CommandError("Control is not running") }

    var request = try JSONSerialization.data(withJSONObject: words)
    request.append(newline)
    guard writeAll(fd, request) else { throw CommandError("cannot reach Control") }

    var answer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = read(fd, &chunk, chunk.count)
        if count <= 0 { break }
        answer.append(contentsOf: chunk[..<count])
    }
    guard let reply = try? JSONSerialization.jsonObject(with: answer) as? [String: String] else {
        throw CommandError("no answer from Control")
    }
    if let error = reply["error"] { throw CommandError(error) }
    return reply["output"] ?? ""
}

/// The app's side: answer each request on `queue`. The main queue, in the app, so a command runs
/// between events, like a key press. Stops listening when released.
final class Listener {
    let path: String
    private let fd: Int32
    private let queue: DispatchQueue
    private let answer: ([String]) throws -> String
    private var server: DispatchSourceRead?
    private var readers: [Int32: DispatchSourceRead] = [:]
    private var received: [Int32: Data] = [:]

    init?(at path: String = socketPath, queue: DispatchQueue = .main, answer: @escaping ([String]) throws -> String) {
        self.path = path
        self.queue = queue
        self.answer = answer
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        // Left over from a Control that crashed.
        unlink(path)
        guard var address = socketAddress(path),
              withUnsafePointer(to: &address, {
                  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
              }) == 0,
              Darwin.listen(fd, 16) == 0 else {
            close(fd)
            return nil
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let server = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        server.setEventHandler { [unowned self] in self.accept() }
        server.setCancelHandler { [fd] in close(fd) }
        server.resume()
        self.server = server
    }

    deinit {
        server?.cancel()
        for reader in readers.values { reader.cancel() }
        unlink(path)
    }

    private func accept() {
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { return }
        setOption(client, SO_NOSIGPIPE, Int32(1))
        // Never wait on a client between events: read what has come, and come back for more.
        _ = fcntl(client, F_SETFL, O_NONBLOCK)
        let reader = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
        reader.setEventHandler { [unowned self] in self.read(from: client) }
        reader.setCancelHandler { close(client) }
        readers[client] = reader
        received[client] = Data()
        reader.resume()
    }

    private func read(from client: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(client, &chunk, chunk.count)
        if count < 0 && errno == EAGAIN { return }
        if count > 0 { received[client, default: Data()].append(contentsOf: chunk[..<count]) }
        let data = received[client] ?? Data()
        // Wait for the whole line, unless the client hung up or sent far too much.
        guard count <= 0 || data.contains(newline) || data.count > 65536 else { return }
        if data.contains(newline) { respond(to: client, data.prefix { $0 != newline }) }
        received[client] = nil
        readers.removeValue(forKey: client)?.cancel()
    }

    private func respond(to client: Int32, _ line: Data) {
        var reply: [String: String]
        do {
            guard let words = try? JSONSerialization.jsonObject(with: line) as? [String] else {
                throw CommandError("expected a JSON array of words")
            }
            reply = ["output": try answer(words)]
        } catch {
            reply = ["error": (error as? CommandError)?.message ?? "\(error)"]
        }
        var data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        data.append(newline)
        // Long lists may not fit the socket's buffer at once: wait for the client to take them, but not forever.
        _ = fcntl(client, F_SETFL, 0)
        setOption(client, SO_SNDTIMEO, timeval(tv_sec: 1, tv_usec: 0))
        _ = writeAll(client, data)
    }
}

private let newline = UInt8(ascii: "\n")

private func socketAddress(_ path: String) -> sockaddr_un? {
    var address = sockaddr_un()
    let bytes = Array(path.utf8)
    // The path must fit, with room for the final zero.
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
}

private func setOption<Value>(_ fd: Int32, _ option: Int32, _ value: Value) {
    withUnsafeBytes(of: value) { _ = setsockopt(fd, SOL_SOCKET, option, $0.baseAddress, socklen_t($0.count)) }
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = write(fd, bytes.baseAddress! + offset, bytes.count - offset)
            if count <= 0 { return false }
            offset += count
        }
        return true
    }
}
