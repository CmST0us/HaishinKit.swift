#if os(iOS) || os(tvOS) || os(macOS)
import AVFoundation

protocol IOCaptureSessionDelegate: AnyObject {
    @available(tvOS 17.0, *)
    func session(_ session: IOCaptureSession, sessionRuntimeError session: AVCaptureSession, error: AVError)
    #if os(iOS) || os(tvOS)
    @available(tvOS 17.0, *)
    func session(_ session: IOCaptureSession, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason?)
    @available(tvOS 17.0, *)
    func session(_ session: IOCaptureSession, sessionInterruptionEnded session: AVCaptureSession)
    #endif
}

final class IOCaptureSession {
    #if os(iOS) || os(tvOS)
    static var isMultiCamSupported: Bool {
        if #available(iOS 13.0, tvOS 17.0, *) {
            return AVCaptureMultiCamSession.isMultiCamSupported
        } else {
            return false
        }
    }
    #else
    static let isMultiCamSupported = true
    #endif

    #if os(tvOS)
    private var _session: Any?
    /// The capture session instance.
    @available(tvOS 17.0, *)
    var session: AVCaptureSession {
        if _session == nil {
            _session = makeSession()
        }
        return _session as! AVCaptureSession
    }
    #elseif os(iOS) || os(macOS)
    /// The capture session instance.
    private(set) lazy var session: AVCaptureSession = makeSession()
    #endif

    #if os(iOS) || os(tvOS)
    var isMultiCamSessionEnabled = false
    @available(tvOS 17.0, *)
    var isMultitaskingCameraAccessEnabled: Bool {
        return session.isMultitaskingCameraAccessEnabled
    }
    #else
    let isMultiCamSessionEnabled = true
    let isMultitaskingCameraAccessEnabled = true
    #endif

    weak var delegate: (any IOCaptureSessionDelegate)?
    private(set) var isRunning: Atomic<Bool> = .init(false)

    #if os(tvOS)
    private var _sessionPreset: Any?
    @available(tvOS 17.0, *)
    var sessionPreset: AVCaptureSession.Preset {
        get {
            if _sessionPreset == nil {
                _sessionPreset = AVCaptureSession.Preset.default
            }
            return _sessionPreset as! AVCaptureSession.Preset
        }
        set {
            guard sessionPreset != newValue, session.canSetSessionPreset(newValue) else {
                return
            }
            session.beginConfiguration()
            session.sessionPreset = newValue
            session.commitConfiguration()
        }
    }
    #elseif os(iOS) || os(macOS)
    var sessionPreset: AVCaptureSession.Preset = .default {
        didSet {
            guard sessionPreset != oldValue, session.canSetSessionPreset(sessionPreset) else {
                return
            }
            session.beginConfiguration()
            session.sessionPreset = sessionPreset
            session.commitConfiguration()
        }
    }
    #endif

    @available(tvOS 17.0, *)
    private var isMultiCamSession: Bool {
        #if os(iOS) || os(tvOS)
        if #available(iOS 13.0, *) {
            return session is AVCaptureMultiCamSession
        } else {
            return false
        }
        #else
        return false
        #endif
    }

    deinit {
        if #available(tvOS 17.0, *) {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    @available(tvOS 17.0, *)
    func configuration(_ lambda: (_ session: AVCaptureSession) throws -> Void ) rethrows {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        try lambda(session)
    }

    @available(tvOS 17.0, *)
    func attachCapture(_ capture: any IOCaptureUnit) {
        if let connection = capture.connection {
            if let input = capture.input, session.canAddInput(input) {
                session.addInputWithNoConnections(input)
            }
            if let output = capture.output, session.canAddOutput(output) {
                session.addOutputWithNoConnections(output)
            }
            if session.canAddConnection(connection) {
                session.addConnection(connection)
            }
        } else {
            if let input = capture.input, session.canAddInput(input) {
                session.addInput(input)
            }
            if let output = capture.output, session.canAddOutput(output) {
                session.addOutput(output)
            }
        }
    }

    @available(tvOS 17.0, *)
    func detachCapture(_ capture: any IOCaptureUnit) {
        if let connection = capture.connection {
            if capture.output?.connections.contains(connection) == true {
                session.removeConnection(connection)
            }
        }
        if let input = capture.input, session.inputs.contains(input) {
            session.removeInput(input)
        }
        if let output = capture.output, session.outputs.contains(output) {
            session.removeOutput(output)
        }
    }

    @available(tvOS 17.0, *)
    func startRunningIfNeeded() {
        guard isRunning.value && !session.isRunning else {
            return
        }
        session.startRunning()
        isRunning.mutate { $0 = session.isRunning }
    }

    #if os(iOS) || os(tvOS)
    @available(tvOS 17.0, *)
    private func makeSession() -> AVCaptureSession {
        let session: AVCaptureSession
        if isMultiCamSessionEnabled, #available(iOS 13.0, *) {
            session = AVCaptureMultiCamSession()
        } else {
            session = AVCaptureSession()
        }
        if session.canSetSessionPreset(sessionPreset) {
            session.sessionPreset = sessionPreset
        }
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
        return session
    }
    #elseif os(macOS)
    private func makeSession() -> AVCaptureSession {
        let session = AVCaptureSession()
        if session.canSetSessionPreset(sessionPreset) {
            session.sessionPreset = sessionPreset
        }
        return session
    }
    #endif

    @available(tvOS 17.0, *)
    private func addSessionObservers(_ session: AVCaptureSession) {
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError(_:)), name: .AVCaptureSessionRuntimeError, object: session)
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: .AVCaptureSessionInterruptionEnded, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: .AVCaptureSessionWasInterrupted, object: session)
        #endif
    }

    @available(tvOS 17.0, *)
    private func removeSessionObservers(_ session: AVCaptureSession) {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
        #endif
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
    }

    @available(tvOS 17.0, *)
    @objc
    private func sessionRuntimeError(_ notification: NSNotification) {
        guard
            let session = notification.object as? AVCaptureSession,
            let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        let error = AVError(_nsError: errorValue)
        switch error.code {
        #if os(iOS) || os(tvOS)
        case .mediaServicesWereReset:
            startRunningIfNeeded()
        #endif
        default:
            break
        }
        delegate?.session(self, sessionRuntimeError: session, error: error)
    }

    #if os(iOS) || os(tvOS)
    @available(tvOS 17.0, *)
    @objc
    private func sessionWasInterrupted(_ notification: Notification) {
        guard let session = notification.object as? AVCaptureSession else {
            return
        }
        guard let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
              let reasonIntegerValue = userInfoValue.integerValue,
              let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) else {
            delegate?.session(self, sessionWasInterrupted: session, reason: nil)
            return
        }
        delegate?.session(self, sessionWasInterrupted: session, reason: reason)
    }

    @available(tvOS 17.0, *)
    @objc
    private func sessionInterruptionEnded(_ notification: Notification) {
        delegate?.session(self, sessionInterruptionEnded: session)
    }
    #endif
}

extension IOCaptureSession: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        if #available(tvOS 17.0, *) {
            addSessionObservers(session)
            session.startRunning()
            isRunning.mutate { $0 = session.isRunning }
        } else {
            isRunning.mutate { $0 = true }
        }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        if #available(tvOS 17.0, *) {
            removeSessionObservers(session)
            session.stopRunning()
            isRunning.mutate { $0 = session.isRunning }
        } else {
            isRunning.mutate { $0 = false }
        }
    }
}

#endif
