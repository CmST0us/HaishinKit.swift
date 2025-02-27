import AVFoundation
import Foundation
import HaishinKit
import libsrt

/// An object that provides the interface to control a one-way channel over a SRTConnection.
public final class SRTStream: NetStream {
    private var name: String?
    private var action: (() -> Void)?
    private var keyValueObservations: [NSKeyValueObservation] = []
    private weak var connection: SRTConnection?

    private lazy var writer: TSWriter = {
        var writer = TSWriter()
        writer.delegate = self
        return writer
    }()

    private lazy var reader: TSReader = {
        var reader = TSReader()
        reader.delegate = self
        return reader
    }()

    /// Creates a new SRTStream object.
    public init(connection: SRTConnection) {
        super.init()
        self.connection = connection
        self.connection?.streams.append(self)
        let keyValueObservation = connection.observe(\.connected, options: [.new, .old]) { [weak self] _, _ in
            guard let self = self else {
                return
            }
            if connection.connected {
                self.action?()
                self.action = nil
            } else {
                self.readyState = .open
            }
        }
        keyValueObservations.append(keyValueObservation)
    }

    deinit {
        connection = nil
        keyValueObservations.removeAll()
    }

    /// Sends streaming audio, vidoe and data message from client.
    public func publish(_ name: String? = "") {
        lockQueue.async {
            guard let name else {
                switch self.readyState {
                case .publish, .publishing:
                    self.readyState = .open
                default:
                    break
                }
                return
            }
            if self.connection?.connected == true {
                self.readyState = .publish
            } else {
                self.action = { [weak self] in self?.publish(name) }
            }
        }
    }

    /// Playback streaming audio and video message from server.
    public func play(_ name: String? = "") {
        lockQueue.async {
            guard let name else {
                switch self.readyState {
                case .play, .playing:
                    self.readyState = .open
                default:
                    break
                }
                return
            }
            if self.connection?.connected == true {
                self.readyState = .play
            } else {
                self.action = { [weak self] in self?.play(name) }
            }
        }
    }

    /// Stops playing or publishing and makes available other uses.
    public func close() {
        lockQueue.async {
            if self.readyState == .closed || self.readyState == .initialized {
                return
            }
            self.readyState = .closed
        }
    }

    override public func readyStateDidChange(to readyState: NetStream.ReadyState) {
        switch readyState {
        case .play:
            connection?.socket?.doInput()
        case .publish:
            writer.expectedMedias.removeAll()
            if videoInputFormat != nil {
                writer.expectedMedias.insert(.video)
            }
            if audioInputFormat != nil {
                writer.expectedMedias.insert(.audio)
            }
            self.readyState = .publishing(muxer: writer)
        default:
            break
        }
    }

    func doInput(_ data: Data) {
        _ = reader.read(data)
    }
}

extension SRTStream: TSWriterDelegate {
    // MARK: TSWriterDelegate
    public func writer(_ writer: TSWriter, didOutput data: Data) {
        connection?.socket?.doOutput(data: data)
    }

    public func writer(_ writer: TSWriter, didRotateFileHandle timestamp: CMTime) {
    }
}

extension SRTStream: TSReaderDelegate {
    // MARK: TSReaderDelegate
    public func reader(_ reader: TSReader, id: UInt16, didRead formatDescription: CMFormatDescription) {
    }

    public func reader(_ reader: TSReader, id: UInt16, didRead sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer)
    }
}
