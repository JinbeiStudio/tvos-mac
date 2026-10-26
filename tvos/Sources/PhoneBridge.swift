import AppKit
import Network

/// Lets the iPhone type for the Mac: a small page on the home network, opened from a push, whose text is typed into the app in front.
final class PhoneBridge {
    static let shared = PhoneBridge()
    private let port: NWEndpoint.Port = 41231
    private var listener: NWListener?
    private let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/tvOS")

    /// A secret in the page's link, so only the phone that got the push can type.
    private lazy var token: String = {
        let file = folder.appendingPathComponent("phone-token")
        if let saved = try? String(contentsOf: file).trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty { return saved }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? fresh.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return fresh
    }()

    func start() {
        guard listener == nil, let listener = try? NWListener(using: .tcp, on: port) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.read(connection, buffer: Data())
        }
        listener.start(queue: .global())
    }

    /// Pushes a notification whose tap opens the page; the topic is kept in phone.json beside the session.
    func notify() {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("phone.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let topic = json["topic"], let url = URL(string: "https://ntfy.sh/\(topic)"), let address = Self.address() else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Mac keyboard", forHTTPHeaderField: "Title")
        request.setValue("http://\(address):\(port.rawValue)/?k=\(token)", forHTTPHeaderField: "Click")
        request.setValue("keyboard", forHTTPHeaderField: "Tags")
        request.httpBody = "Tap to type on the Mac".data(using: .utf8)
        URLSession.shared.dataTask(with: request).resume()
    }

    private static func address() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = pointer.pointee
            guard item.ifa_addr.pointee.sa_family == UInt8(AF_INET), String(cString: item.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(item.ifa_addr, socklen_t(item.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            return String(cString: host)
        }
        return nil
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self = self else { return }
            var buffer = buffer
            if let data = data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                self.respond(to: request, on: connection)
            } else if done || error != nil || buffer.count > 200_000 {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        func send(_ status: String, _ type: String = "text/plain", _ body: String = "") {
            let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: (head + body).data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
        guard request.query["k"] == token else { return send("403 Forbidden") }
        switch (request.method, request.path) {
        case ("GET", "/"): send("200 OK", "text/html", Self.page)
        case ("POST", "/type"):
            let text = String(data: request.body, encoding: .utf8) ?? ""
            DispatchQueue.main.async { RemoteReceiver.shared.typeText(text) }
            send("204 No Content")
        case ("POST", "/key"):
            let name = String(data: request.body, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                let code: CGKeyCode = name == "back" ? 51 : 36
                RemoteReceiver.shared.press(code, down: true)
                RemoteReceiver.shared.press(code, down: false)
            }
            send("204 No Content")
        default: send("404 Not Found")
        }
    }

    private static let page = """
    <!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
    <title>Mac keyboard</title>
    <style>
    body{font:17px -apple-system,sans-serif;margin:0;padding:16px;background:#111;color:#fff}
    textarea{width:100%;box-sizing:border-box;height:130px;font:20px -apple-system,sans-serif;border-radius:12px;border:0;padding:12px;background:#222;color:#fff}
    .row{display:flex;gap:10px;margin-top:12px}
    button{flex:1;padding:16px;font-size:18px;border:0;border-radius:12px;background:#2a2a2a;color:#fff}
    #send{flex:3;background:#0a84ff}
    </style>
    <textarea id=t autofocus placeholder="Type or dictate"></textarea>
    <div class=row><button id=back>⌫</button><button id=enter>↵</button><button id=send>Send</button></div>
    <script>
    const k=new URLSearchParams(location.search).get('k'),t=document.getElementById('t');
    const post=(p,b)=>fetch(p+'?k='+k,{method:'POST',body:b});
    document.getElementById('send').onclick=async()=>{if(t.value){await post('/type',t.value);t.value=''}t.focus()};
    document.getElementById('back').onclick=()=>post('/key','back');
    document.getElementById('enter').onclick=()=>post('/key','enter');
    </script>
    """
}

/// Just enough HTTP to read one request from the phone.
struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let length = lines.dropFirst().compactMap { line -> Int? in
            let pair = line.split(separator: ":", maxSplits: 1)
            return pair.count == 2 && pair[0].lowercased() == "content-length" ? Int(pair[1].trimmingCharacters(in: .whitespaces)) : nil
        }.first ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        let components = URLComponents(string: "http://x" + parts[1])
        method = String(parts[0])
        path = components?.path ?? "/"
        query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        self.body = Data(body.prefix(length))
    }
}
