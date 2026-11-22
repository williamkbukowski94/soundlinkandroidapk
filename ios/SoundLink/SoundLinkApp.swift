import SwiftUI
import AVFoundation
import Network
import CryptoKit

@main struct SoundLinkApp: App {
    var body: some Scene { WindowGroup { ReceiverView() } }
}
struct ReceiverView: View {
    @StateObject private var receiver = Receiver()
    @State private var host = ""
    @State private var code = ""
    @State private var bluetooth = false
    @State private var correction = 0.0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("soundLInk").font(.largeTitle.bold()).foregroundStyle(.green)
                Text("Join the soundtrack.").font(.title)
                Text("Native iPhone receiver · Android phone hosts the audio")
                Toggle("Bluetooth speaker group", isOn: $bluetooth).disabled(receiver.connected)
                TextField("Host Wi-Fi IPv4 address", text: $host).keyboardType(.decimalPad)
                SecureField("8-digit group code", text: $code).keyboardType(.numberPad)
                Button(receiver.connected ? "Disconnect" : "Join group") {
                    if receiver.connected { receiver.stop() }
                    else { receiver.join(host: host, code: code, bluetooth: bluetooth, correction: correction) }
                }.buttonStyle(.borderedProminent)
                Text(receiver.status).accessibilityLabel("Connection status: \(receiver.status)")
                Text("Speaker timing").font(.headline)
                Text("Correction: \(Int(correction)) ms")
                Slider(value: $correction, in: -1500...1500, step: 1)
                Button("Apply timing correction") { receiver.correction = correction; receiver.resetAudio() }
                Text("Use the Android host’s shared calibration clicks. Earlier is negative; later is positive. Bluetooth timing still needs physical calibration.")
                Text("Choose Bluetooth in Control Center before joining. Phone-speaker groups require the built-in speaker. The source must be an Android soundLInk host. This iPhone version does not capture Spotify or other apps.")
                Text("Development build. Acoustic synchronization has not been verified on iPhones.").font(.footnote)
            }.padding(26)
        }.textFieldStyle(.roundedBorder).preferredColorScheme(.dark)
    }
}

final class TCPStream {
    let connection: NWConnection
    init(_ host: String) { connection = NWConnection(host: NWEndpoint.Host(host), port: 17865, using: .tcp) }
    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            connection.stateUpdateHandler = { state in
                guard !finished else { return }
                switch state {
                case .ready: finished = true; continuation.resume()
                case .failed(let error): finished = true; continuation.resume(throwing: error)
                case .cancelled: finished = true; continuation.resume(throwing: Failure.message("Connection cancelled"))
                default: break
                }
            }
            connection.start(queue: DispatchQueue(label: "soundlink.socket"))
        }
    }
    func read(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, ended, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == count { continuation.resume(returning: data) }
                else { continuation.resume(throwing: Failure.message(ended ? "Host disconnected" : "Incomplete audio packet")) }
            }
        }
    }
    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
    func utf() async throws -> String { let length = Int(try await read(2).uint()); guard length < 4096 else { throw Failure.message("Invalid handshake") }; return String(decoding: try await read(length), as: UTF8.self) }
    func authenticate(code: String, mode: String, kind: String) async throws {
        try await open()
        let nonce = try await utf()
        let proof = HMAC<SHA256>.authenticationCode(for: Data(nonce.utf8), using: SymmetricKey(data: Data(code.utf8))).map { String(format: "%02x", $0) }.joined()
        var request = Data()
        for value in [proof, kind, mode] { let bytes = Data(value.utf8); request.appendBE(UInt64(bytes.count), count: 2); request.append(bytes) }
        try await send(request)
        guard try await read(1).uint() == 1 else { throw Failure.message(try await utf()) }
        guard try await read(4).uint() == 1 else { throw Failure.message("App versions do not match") }
    }
}
enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
extension Data {
    func uint() -> UInt64 { reduce(0) { ($0 << 8) | UInt64($1) } }
    mutating func appendBE(_ value: UInt64, count: Int) { for index in (0..<count).reversed() { append(UInt8(truncatingIfNeeded: value >> (index * 8))) } }
}

@MainActor final class Receiver: ObservableObject {
    @Published var status = "Ready. Join the same Wi-Fi as the Android host."
    @Published var connected = false
    var correction: Double = 0
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var speed = AVAudioUnitVarispeed()
    private var stream: TCPStream?
    private var clockStream: TCPStream?
    private var task: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var offset = 0.0
    private var bluetooth = false
    private var generation: UInt64?
    private var nextFrame: UInt64?
    private var firstFrame: UInt64 = 0
    private var firstLocalTime = 0.0
    private var pending = 0
    private var sessionID = UUID()
    private var audioEpoch = UUID()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private var now: Double { Double(DispatchTime.now().uptimeNanoseconds) }
    func resetAudio() { audioEpoch = UUID(); player.stop(); player.play(); generation = nil; nextFrame = nil; pending = 0 }
    func stop() {
        sessionID = UUID(); task?.cancel(); clockTask?.cancel(); timeout?.cancel()
        stream?.connection.cancel(); clockStream?.connection.cancel(); stream = nil; clockStream = nil
        player.stop(); engine.stop(); pending = 0; connected = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = "Disconnected."
    }
    func join(host: String, code: String, bluetooth: Bool, correction: Double) {
        stop()
        guard host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil, code.count == 8, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { status = "Enter the host's IPv4 address and 8-digit code."; return }
        self.bluetooth = bluetooth; self.correction = correction
        let id = sessionID; connected = true; status = "Measuring the host clock…"
        timeout = Task { try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled && id == sessionID && connected { stop(); status = "Connection timed out. Check Wi-Fi and the host address." } }
        task = Task {
            do {
                try prepareAudio()
                try await synchronize(host: host, code: code)
                try Task.checkCancellation()
                let socket = TCPStream(host); stream = socket
                try await socket.authenticate(code: code, mode: bluetooth ? "bluetooth" : "phone", kind: "audio")
                timeout?.cancel(); status = "Connected. Waiting for shared audio…"
                clockTask = Task {
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 10_000_000_000); try Task.checkCancellation(); try await synchronize(host: host, code: code) }
                        catch { if !Task.isCancelled { status = "Clock refresh failed. Rejoin if this continues." } }
                    }
                }
                while !Task.isCancelled {
                    let type = try await socket.read(1).uint()
                    if type == 0 { continue }
                    guard type == 1 else { throw Failure.message("Unknown packet type") }
                    let header = try await socket.read(28)
                    let g = header.subdata(in: 0..<8).uint(), frame = header.subdata(in: 8..<16).uint(), at = header.subdata(in: 16..<24).uint()
                    let size = Int(header.subdata(in: 24..<28).uint())
                    guard size > 0 && size <= 19200 && size % 4 == 0 else { throw Failure.message("Invalid PCM packet") }
                    let pcm = try await socket.read(size)
                    try Task.checkCancellation()
                    try schedule(pcm, generation: g, frame: frame, hostTime: Double(at))
                }
            } catch { if id == sessionID { let text = error.localizedDescription; stop(); status = text } }
        }
    }
    private func synchronize(host: String, code: String) async throws {
        let socket = TCPStream(host); clockStream = socket
        defer { socket.connection.cancel() }
        try await socket.authenticate(code: code, mode: bluetooth ? "bluetooth" : "phone", kind: "clock")
        var samples: [(Double, Double)] = []
        for _ in 0..<8 {
            let sent = now; var request = Data(); request.appendBE(UInt64(sent), count: 8); try await socket.send(request)
            let server = Double(try await socket.read(8).uint()), received = now
            samples.append((received - sent, server - (sent + received) / 2))
        }
        samples.sort { $0.0 < $1.0 }
        let target = samples.prefix(3).map { $0.1 }.reduce(0, +) / 3
        offset = stream == nil ? target : offset + (target - offset) * 0.15
    }
    private func prepareAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        try checkRoute()
        engine = AVAudioEngine(); player = AVAudioPlayerNode(); speed = AVAudioUnitVarispeed()
        engine.attach(player); engine.attach(speed); engine.connect(player, to: speed, format: format); engine.connect(speed, to: engine.mainMixerNode, format: format)
        try engine.start(); player.play()
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.interruptionNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.stop(); self?.status = "Audio route changed or interrupted. Check the speaker and rejoin." } })
        }
    }
    private func checkRoute() throws {
        let ports = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType }
        let valid = bluetooth ? ports.contains(.bluetoothA2DP) || ports.contains(.bluetoothLE) : ports.contains(.builtInSpeaker)
        guard valid else { throw Failure.message(bluetooth ? "Select a Bluetooth media speaker in Control Center first." : "Phone group requires the built-in speaker. Disconnect Bluetooth or headphones.") }
    }
    private func schedule(_ data: Data, generation g: UInt64, frame: UInt64, hostTime: Double) throws {
        try checkRoute()
        let desired = hostTime - offset + correction * 1e6
        let latency = (AVAudioSession.sharedInstance().outputLatency + AVAudioSession.sharedInstance().ioBufferDuration) * 1e9
        let renderTime = desired - latency
        if renderTime < now + 20_000_000 { status = "Late audio dropped. Waiting to rejoin the timeline."; resetAudio(); return }
        guard pending < 50 else { throw Failure.message("Receiver fell behind. Rejoin the group.") }
        let frames = data.count / 4
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for index in 0..<frames { for channel in 0..<2 {
            let start = index * 4 + channel * 2
            let value = Int16(bitPattern: UInt16(data[start]) | UInt16(data[start + 1]) << 8)
            buffer.floatChannelData![channel][index] = Float(value) / 32768
        } }
        let contiguous = generation == g && nextFrame == frame
        if !contiguous { resetAudio(); generation = g; firstFrame = frame; firstLocalTime = desired }
        let predicted = firstLocalTime + Double(frame - firstFrame) / 48000 * 1e9
        speed.rate = Float(1 + max(-0.002, min(0.002, (predicted - desired) / 5e9)))
        pending += 1
        let id = sessionID, epoch = audioEpoch
        player.scheduleBuffer(buffer, at: contiguous ? nil : AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: renderTime / 1e9)), options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in guard let self, self.sessionID == id, self.audioEpoch == epoch else { return }; self.pending = max(0, self.pending - 1) }
        }
        nextFrame = frame + UInt64(frames)
        status = "Shared timeline active · calibrate against your Android speaker."
    }
}
