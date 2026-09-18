import Foundation
import MultipeerConnectivity
import ReplayKit
import CoreMedia
import CoreImage
import UIKit
import Observation

/// Normalized tap / drag event sent from controller → broadcaster.
struct RemoteTouchEvent: Codable {
    enum Kind: String, Codable { case tap, touchBegan, touchMoved, touchEnded }
    let kind: Kind
    let normalizedX: Double
    let normalizedY: Double
}

/// Central state machine for the peer-to-peer broadcast/control session.
/// Lives at the root level so it persists across navigation — the broadcaster
/// can navigate the app freely while the session keeps running in the background.
@Observable
final class RemoteControlSession: NSObject {

    enum Role: Hashable { case broadcaster, controller }

    private(set) var role: Role?
    private(set) var connectedPeers: [MCPeerID] = []
    private(set) var availablePeers: [MCPeerID] = []
    private(set) var isCaptureActive = false
    private(set) var captureError: String?
    private(set) var latestFrame: UIImage?
    private(set) var touchEventID: Int = 0
    private(set) var lastRemoteTouch: RemoteTouchEvent?
    // Set when a text-input event is received — controller observes this to dismiss its keyboard sheet.
    private(set) var isConnecting = false

    private static let serviceType = "scanart-remote"
    private let myPeerID: MCPeerID
    private var mcSession: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let encodeLock = NSLock()
    private var lastFrameTime: Double = 0
    private var previousTouchPoint: CGPoint?
    private weak var trackedSlider: UISlider?
    private let capturePeersLock = NSLock()
    private var capturePeers: [MCPeerID] = []
    // Tracks peers for which an invitation has been sent but not yet resolved —
    // prevents duplicate invitations when the user taps a peer more than once.
    private var pendingInvitePeers: Set<String> = []

    private static let frameMarker     = UInt8(0x01)
    private static let touchMarker     = UInt8(0x02)
    private static let textInputMarker = UInt8(0x03)

    override init() {
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    // MARK: - Broadcaster API

    func startBroadcasting() {
        guard role == nil else { return }
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
        capturePeersLock.lock(); capturePeers = []; capturePeersLock.unlock()
        pendingInvitePeers = []
        role = nil
        captureError = nil
    }

    // MARK: - Controller API

    func startBrowsing() {
        guard role == nil else { return }
        role = .controller
        mcSession = buildSession()
        let brw = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        brw.delegate = self
        brw.startBrowsingForPeers()
        browser = brw
    }

    func connect(to peer: MCPeerID) {
        guard let s = mcSession,
              !connectedPeers.contains(peer),
              !pendingInvitePeers.contains(peer.displayName) else { return }
        pendingInvitePeers.insert(peer.displayName)
        isConnecting = true
        // 15-second timeout gives more headroom on congested networks.
        browser?.invitePeer(peer, to: s, withContext: nil, timeout: 15)
    }

    func sendTouch(_ event: RemoteTouchEvent) {
        guard let s = mcSession, !connectedPeers.isEmpty,
              let payload = try? JSONEncoder().encode(event) else { return }
        var data = Data([Self.touchMarker])
        data.append(payload)
        try? s.send(data, toPeers: connectedPeers, with: .reliable)
    }

    /// Sends a UTF-8 string to the broadcaster to be typed into the focused text field.
    func sendTextInput(_ text: String) {
        guard let s = mcSession, !connectedPeers.isEmpty,
              let payload = text.data(using: .utf8) else { return }
        var data = Data([Self.textInputMarker])
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
        capturePeersLock.lock(); capturePeers = []; capturePeersLock.unlock()
        pendingInvitePeers = []
        isCaptureActive = false
        captureError = nil
        isConnecting = false
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
        recorder.stopCapture { [weak self] _ in
            guard let self else { return }
            recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
                guard let self, bufferType == .video, error == nil,
                      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

                let now = CACurrentMediaTime()
                guard now - self.lastFrameTime >= 0.067 else { return }

                guard self.encodeLock.try() else { return }
                self.lastFrameTime = now

                let ci = CIImage(cvPixelBuffer: pixelBuffer)
                let scale = min(1.0, 320.0 / ci.extent.width)
                let scaledCI = scale < 1.0
                    ? ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    : ci
                guard let cg = self.ciContext.createCGImage(scaledCI, from: scaledCI.extent),
                      let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.25) else {
                    self.encodeLock.unlock()
                    return
                }
                self.encodeLock.unlock()

                var packet = Data([Self.frameMarker])
                packet.append(jpeg)
                self.capturePeersLock.lock()
                let peers = self.capturePeers
                self.capturePeersLock.unlock()
                guard !peers.isEmpty else { return }
                try? self.mcSession?.send(packet, toPeers: peers, with: .unreliable)
            } completionHandler: { [weak self] error in
                DispatchQueue.main.async {
                    self?.captureError = error?.localizedDescription
                    self?.isCaptureActive = error == nil
                }
            }
        }
    }

}

// MARK: - Remote touch + text execution (broadcaster side)

extension RemoteControlSession {

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })
    }

    private func performRemoteTouch(_ event: RemoteTouchEvent) {
        guard let window = keyWindow() else { return }
        let point = CGPoint(
            x: CGFloat(event.normalizedX) * window.bounds.width,
            y: CGFloat(event.normalizedY) * window.bounds.height
        )

        switch event.kind {
        case .touchBegan:
            previousTouchPoint = point
            trackedSlider = nil
            if let hitView = window.hitTest(point, with: nil) {
                var v: UIView? = hitView
                while let view = v {
                    if let sl = view as? UISlider { trackedSlider = sl; break }
                    v = view.superview
                }
            }

        case .touchMoved:
            guard let prev = previousTouchPoint else { previousTouchPoint = point; return }
            let delta = CGPoint(x: point.x - prev.x, y: point.y - prev.y)
            previousTouchPoint = point
            if let slider = trackedSlider {
                let trackInSlider = slider.trackRect(forBounds: slider.bounds)
                let trackInWindow = slider.convert(trackInSlider, to: window)
                guard trackInWindow.width > 0 else { break }
                let rawFraction = (point.x - trackInWindow.minX) / trackInWindow.width
                let fraction = max(0, min(1, rawFraction))
                let newValue = slider.minimumValue + Float(fraction) * (slider.maximumValue - slider.minimumValue)
                slider.setValue(newValue, animated: false)
                slider.sendActions(for: .valueChanged)
            } else {
                scrollIfPossible(at: point, in: window, delta: delta)
            }

        case .touchEnded:
            if let slider = trackedSlider {
                slider.sendActions(for: .touchUpInside)
            }
            previousTouchPoint = nil
            trackedSlider = nil

        case .tap:
            if let hitView = window.hitTest(point, with: nil) {
                var responder: UIResponder? = hitView
                while let r = responder {
                    if let tf = r as? UITextField { tf.becomeFirstResponder(); return }
                    if let tv = r as? UITextView  { tv.becomeFirstResponder(); return }
                    if let control = r as? UIControl {
                        control.sendActions(for: .touchUpInside)
                        return
                    }
                    responder = r.next
                }
            }
            activateElement(at: point, in: window)
        }
    }

    /// Inserts `text` into whichever text field currently holds first-responder focus.
    private func insertTextIntoFirstResponder(_ text: String) {
        guard let window = keyWindow() else { return }
        guard let target = findFirstResponder(in: window) else { return }
        if let keyInput = target as? UIKeyInput {
            keyInput.insertText(text)
        }
    }

    /// Depth-first search for the first-responder view in the hierarchy.
    private func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = findFirstResponder(in: sub) { return found }
        }
        return nil
    }

    private func scrollIfPossible(at point: CGPoint, in window: UIWindow, delta: CGPoint) {
        guard let hitView = window.hitTest(point, with: nil) else { return }
        var current: UIView? = hitView
        while let view = current {
            if let sv = view as? UIScrollView, sv.isScrollEnabled {
                let maxX = max(0, sv.contentSize.width - sv.bounds.width)
                let maxY = max(0, sv.contentSize.height - sv.bounds.height)
                let newX = min(max(0, sv.contentOffset.x - delta.x), maxX)
                let newY = min(max(0, sv.contentOffset.y - delta.y), maxY)
                sv.setContentOffset(CGPoint(x: newX, y: newY), animated: false)
                return
            }
            current = view.superview
        }
    }

    @discardableResult
    private func activateElement(at point: CGPoint, in element: NSObject) -> Bool {
        if !(element is UIWindow) {
            guard element.accessibilityFrame.contains(point) else { return false }
            let activatable: UIAccessibilityTraits = [.button, .link, .adjustable]
            if !element.accessibilityTraits.intersection(activatable).isEmpty,
               element.accessibilityActivate() {
                return true
            }
        }
        for child in (element.accessibilityElements as? [NSObject] ?? []) {
            if activateElement(at: point, in: child) { return true }
        }
        if let view = element as? UIView {
            for subview in view.subviews.reversed() {
                if activateElement(at: point, in: subview) { return true }
            }
        }
        return false
    }
}

// MARK: - MCSessionDelegate

extension RemoteControlSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connecting:
                // Nothing to do — pendingInvitePeers already tracks this.
                break
            case .connected:
                self.pendingInvitePeers.remove(peerID.displayName)
                self.isConnecting = false
                if !self.connectedPeers.contains(peerID) { self.connectedPeers.append(peerID) }
                if self.role == .controller { self.browser?.stopBrowsingForPeers() }
            case .notConnected:
                // Allow retrying the same peer on the next tap.
                self.pendingInvitePeers.remove(peerID.displayName)
                self.isConnecting = self.pendingInvitePeers.isEmpty ? false : self.isConnecting
                self.connectedPeers.removeAll { $0 == peerID }
                if self.role == .controller, let brw = self.browser { brw.startBrowsingForPeers() }
            default:
                break
            }
            self.capturePeersLock.lock()
            self.capturePeers = self.connectedPeers
            self.capturePeersLock.unlock()
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
                if self.role == .broadcaster { self.performRemoteTouch(event) }
            }
        case Self.textInputMarker:
            guard let text = String(data: payload, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                if self.role == .broadcaster { self.insertTextIntoFirstResponder(text) }
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
        // Accept only if we have no connected peer and the session is live.
        let accept = connectedPeers.isEmpty && mcSession != nil
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
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
            // Allow retrying if this peer was in-flight.
            self.pendingInvitePeers.remove(peerID.displayName)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.captureError = "Browse failed: \(error.localizedDescription)" }
    }
}
