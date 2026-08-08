import Foundation
import MultipeerConnectivity
import ReplayKit
import CoreMedia
import CoreImage
import UIKit
import Observation

/// Normalized tap event sent from controller → broadcaster.
struct RemoteTouchEvent: Codable {
    enum Kind: String, Codable { case tap, touchBegan, touchMoved, touchEnded }
    let kind: Kind
    let normalizedX: Double
    let normalizedY: Double
}

/// Central state machine for the peer-to-peer broadcast/control session.
@Observable
final class RemoteControlSession: NSObject {

    enum Role { case broadcaster, controller }

    private(set) var role: Role?
    private(set) var connectedPeers: [MCPeerID] = []
    private(set) var availablePeers: [MCPeerID] = []
    private(set) var isCaptureActive = false
    private(set) var captureError: String?
    private(set) var latestFrame: UIImage?
    private(set) var touchEventID: Int = 0
    private(set) var lastRemoteTouch: RemoteTouchEvent?

    private static let serviceType = "scanart-remote"
    private let myPeerID: MCPeerID
    private var mcSession: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let ciContext = CIContext()

    private static let frameMarker = UInt8(0x01)
    private static let touchMarker = UInt8(0x02)

    override init() {
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    // MARK: - Broadcaster API

    func startBroadcasting() {
        role = .broadcaster
        mcSession = buildSession()
        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        beginScreenCapture()
    }

    func stopBroadcasting() {
        RPScreenRecorder.shared().stopCapture { [weak self] _ in
            DispatchQueue.main.async { self?.isCaptureActive = false }
        }
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        mcSession?.disconnect()
        mcSession = nil
        connectedPeers = []
        role = nil
        captureError = nil
    }

    // MARK: - Controller API

    func startBrowsing() {
        role = .controller
        mcSession = buildSession()
        let brw = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        brw.delegate = self
        brw.startBrowsingForPeers()
        browser = brw
    }

    func connect(to peer: MCPeerID) {
        guard let s = mcSession else { return }
        browser?.invitePeer(peer, to: s, withContext: nil, timeout: 10)
    }

    func sendTouch(_ event: RemoteTouchEvent) {
        guard let s = mcSession, !connectedPeers.isEmpty,
              let payload = try? JSONEncoder().encode(event) else { return }
        var data = Data([Self.touchMarker])
        data.append(payload)
        try? s.send(data, toPeers: connectedPeers, with: .reliable)
    }

    func disconnect() {
        RPScreenRecorder.shared().stopCapture { _ in }
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        mcSession?.disconnect()
        mcSession = nil
        connectedPeers = []
        availablePeers = []
        isCaptureActive = false
        captureError = nil
        role = nil
    }

    // MARK: - Private

    private func buildSession() -> MCSession {
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }

    private func beginScreenCapture() {
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
            guard let self, bufferType == .video, error == nil,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  !self.connectedPeers.isEmpty else { return }
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cg = self.ciContext.createCGImage(ci, from: ci.extent),
                  let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.35) else { return }
            var data = Data([Self.frameMarker])
            data.append(jpeg)
            try? self.mcSession?.send(data, toPeers: self.connectedPeers, with: .unreliable)
        } completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.captureError = error?.localizedDescription
                self?.isCaptureActive = error == nil
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension RemoteControlSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) { self.connectedPeers.append(peerID) }
                if self.role == .controller { self.browser?.stopBrowsingForPeers() }
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                if self.role == .controller, let brw = self.browser { brw.startBrowsingForPeers() }
            default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count > 1 else { return }
        let marker = data[0]
        let payload = data.dropFirst()
        switch marker {
        case Self.frameMarker:
            guard let image = UIImage(data: payload) else { return }
            DispatchQueue.main.async { self.latestFrame = image }
        case Self.touchMarker:
            guard let event = try? JSONDecoder().decode(RemoteTouchEvent.self, from: payload) else { return }
            DispatchQueue.main.async {
                self.lastRemoteTouch = event
                self.touchEventID += 1
            }
        default:
            break
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension RemoteControlSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let accept = connectedPeers.isEmpty
        invitationHandler(accept, accept ? mcSession : nil)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.captureError = "Advertising failed: \(error.localizedDescription)" }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension RemoteControlSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.availablePeers.contains(peerID) { self.availablePeers.append(peerID) }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.availablePeers.removeAll { $0 == peerID } }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.captureError = "Browse failed: \(error.localizedDescription)" }
    }
}
