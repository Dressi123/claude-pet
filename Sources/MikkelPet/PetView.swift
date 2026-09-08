// Draws Mikkel and runs his animation clock.
//
// The atlas uses uneven per-frame durations, so frames are advanced against a
// wall clock rather than by a fixed-interval tick.

import PetCore
import AppKit

protocol PetViewDelegate: AnyObject {
    func petViewWasClicked(_ view: PetView)
    func petViewOneShotFinished(_ view: PetView, state: PetState)
    /// The menu to show on a right-click, so the pet stays reachable when the
    /// menu bar icon is hidden behind a notch or a crowded bar.
    func petViewMenu(_ view: PetView) -> NSMenu
}

final class PetView: NSView {
    weak var delegate: PetViewDelegate?

    private let atlas: Atlas
    private let spriteLayer = CALayer()
    private let bubbleLayer = CATextLayer()
    private let timerLayer = CATextLayer()
    private let bubbleBackground = CAShapeLayer()

    /// Text without the trailing dots, so the dots can animate on their own.
    private var bubbleText = ""
    /// When the current line started, for the elapsed timer.
    private var lineStartedAt = CACurrentMediaTime()
    /// Whether this line is something in progress rather than a finished state.
    private var lineIsBusy = false
    private var dotPhase = 0
    private var lastBubbleTick: CFTimeInterval = 0

    /// A quick job needs no clock; the timer is for the ones that drag.
    private static let timerAppearsAfter: CFTimeInterval = 4

    /// The looping state the pet returns to.
    private var restingState: PetState = .idle
    /// A one-shot (wave, jump, sad) that plays once, then hands back.
    private var oneShotState: PetState?
    private var currentFrame = 0
    private var frameStartedAt = CACurrentMediaTime()
    private var timer: Timer?

    /// A burst of tool events would otherwise restart the animation several
    /// times a second, which reads as strobing rather than as activity. A new
    /// resting state waits out the rest of this window before it is shown.
    private static let minimumDwell: CFTimeInterval = 0.6
    private var restingStartedAt = CACurrentMediaTime()
    private var pendingResting: PetState?

    /// How long the current pose is held, in pose playback. Re-rolled on every
    /// change so the pet does not settle into a visible rhythm.
    private var holdFor: CFTimeInterval = 0
    /// Mostly he settles. Now and then he shifts quickly, the way a real animal
    /// glances up mid-rest, which keeps the pacing from feeling metronomic.
    private static let settledHold: ClosedRange<Double> = 1.8...3.0
    private static let quickHold: ClosedRange<Double> = 0.5...1.1
    private static let quickChance = 0.35

    /// While idle, Mikkel watches the pointer using the 16 look directions.
    var pointerTrackingEnabled = true

    /// How long everything has to stay quiet before he settles down to sleep.
    /// Nought disables it.
    var sleepAfter: TimeInterval = 240
    private var quietSince = CACurrentMediaTime()
    private(set) var isAsleep = false

    /// Multiplies every frame duration. The atlas's own timings are tuned for
    /// a lively pet; a companion that animates all day reads better slower.
    var speed: Double = 1.7
    private var lookIndex: Int?

    private var dragOrigin: NSPoint?
    private var dragState: PetState?
    private var didDrag = false
    /// While the pet is being carried, Claude's status must not overwrite the
    /// run animation. The status is remembered and applied on release.
    private var isDragging = false

    var scale: CGFloat = 0.75 { didSet { needsLayout = true } }
    var petSize: CGSize {
        CGSize(width: CGFloat(AtlasGeometry.cellWidth) * scale,
               height: CGFloat(AtlasGeometry.cellHeight) * scale)
    }

    static let bubbleBoxHeight: CGFloat = 29
    static let tailHeight: CGFloat = 7
    static let tailWidth: CGFloat = 14
    /// Vertical room the window must leave above the pet.
    static let bubbleHeight: CGFloat = bubbleBoxHeight + tailHeight + 2
    static let bubbleWidth: CGFloat = 280

    init(atlas: Atlas) {
        self.atlas = atlas
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        spriteLayer.magnificationFilter = .trilinear
        spriteLayer.minificationFilter = .trilinear
        spriteLayer.contentsGravity = .resizeAspect
        // Core Animation cross-fades `contents` by default, which renders two
        // sprites at once and turns every frame change into a dissolve.
        spriteLayer.actions = ["contents": NSNull()]
        layer?.addSublayer(spriteLayer)

        bubbleBackground.fillColor = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.18, alpha: 0.92).cgColor
        bubbleBackground.strokeColor = Self.accent(for: .idle).cgColor
        bubbleBackground.lineWidth = 1
        bubbleBackground.opacity = 0
        // The bubble grows and shrinks with the text, so let those changes ease
        // rather than snap between widths.
        bubbleBackground.actions = ["path": CABasicAnimation(keyPath: "path")]
        layer?.addSublayer(bubbleBackground)

        bubbleLayer.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        bubbleLayer.fontSize = 11
        bubbleLayer.foregroundColor = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1).cgColor
        bubbleLayer.alignmentMode = .center
        bubbleLayer.truncationMode = .end
        bubbleLayer.isWrapped = false
        bubbleLayer.opacity = 0
        layer?.addSublayer(bubbleLayer)

        timerLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timerLayer.fontSize = 10
        timerLayer.foregroundColor = NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.25, alpha: 0.85).cgColor
        timerLayer.alignmentMode = .right
        timerLayer.opacity = 0
        layer?.addSublayer(timerLayer)

        startClock()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - State

    func apply(resting: PetState, oneShot: PetState?, label: String) {
        // Anything other than a silent idle counts as activity.
        if resting != .idle || oneShot != nil || !label.isEmpty {
            quietSince = CACurrentMediaTime()
            wake()
        }

        // One-shots are the reactions worth interrupting for, so they skip the
        // dwell window.
        if let oneShot, oneShot != oneShotState {
            oneShotState = oneShot
            resetFrame()
        }
        if isDragging {
            // Hold the carry animation; take up the new status on release.
            pendingResting = resting
        } else if resting == restingState {
            pendingResting = nil
        } else if CACurrentMediaTime() - restingStartedAt < Self.minimumDwell {
            pendingResting = resting
        } else {
            commitResting(resting)
        }
        setBubble(label)
    }

    private func commitResting(_ state: PetState) {
        debugTrace("pose \(state.rawValue)", dedupe: false)
        restingState = state
        restingStartedAt = CACurrentMediaTime()
        if oneShotState == nil { resetFrame() }
    }

    private var displayState: PetState { oneShotState ?? restingState }

    private func resetFrame() {
        currentFrame = 0
        frameStartedAt = CACurrentMediaTime()
        holdFor = 0
        lookIndex = nil
    }

    private func setBubble(_ text: String) {
        guard text != bubbleText else { return }
        bubbleText = text
        lineStartedAt = CACurrentMediaTime()
        dotPhase = 0
        let visible = !text.isEmpty
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        bubbleLayer.opacity = visible ? 1 : 0
        bubbleBackground.opacity = visible ? 1 : 0
        timerLayer.opacity = 0
        CATransaction.commit()
        layoutBubble()
    }

    /// The accent ties the bubble to what he is doing: gold when he needs you,
    /// warm red when something broke, quiet blue the rest of the time.
    private static func accent(for state: PetState) -> NSColor {
        switch state {
        case .waiting:
            return NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 0.95)
        case .failed:
            return NSColor(calibratedRed: 0.90, green: 0.42, blue: 0.36, alpha: 0.90)
        default:
            return NSColor(calibratedRed: 0.55, green: 0.68, blue: 0.92, alpha: 0.45)
        }
    }

    /// Busy lines get animated dots and, once they drag on, a clock.
    private var isBusyLine: Bool {
        guard oneShotState == nil else { return false }
        switch restingState {
        case .running, .review, .runningRight, .runningLeft: return true
        default: return false
        }
    }

    private func elapsedText() -> String? {
        let elapsed = CACurrentMediaTime() - lineStartedAt
        guard isBusyLine, elapsed >= Self.timerAppearsAfter else { return nil }
        let seconds = Int(elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Rebuilds the bubble each frame: dots cycle, the clock ticks, and the
    /// shape follows the text width so short lines get a small bubble.
    private func updateBubble() {
        guard !bubbleText.isEmpty else { return }
        let now = CACurrentMediaTime()
        guard now - lastBubbleTick >= 0.4 else { return }
        lastBubbleTick = now
        if isBusyLine { dotPhase = (dotPhase + 1) % 4 }
        layoutBubble()
    }

    private func layoutBubble() {
        guard !bubbleText.isEmpty else { return }
        let dots = isBusyLine ? String(repeating: "\u{00B7}", count: dotPhase) : ""
        let line = dots.isEmpty ? bubbleText : "\(bubbleText) \(dots)"
        bubbleLayer.string = line

        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        // Measure the widest form so cycling dots never resize the bubble.
        let widest = isBusyLine ? "\(bubbleText) \u{00B7}\u{00B7}\u{00B7}" : bubbleText
        var textWidth = (widest as NSString)
            .size(withAttributes: [.font: font]).width.rounded(.up)

        let elapsed = elapsedText()
        // Room for "10:05" plus the gap that separates it from the text.
        let timerWidth: CGFloat = elapsed == nil ? 0 : 42
        let sidePadding: CGFloat = 12
        let maxWidth = bounds.width - 8
        textWidth = min(textWidth, maxWidth - sidePadding * 2 - timerWidth)

        let bubbleWidth = min(maxWidth, textWidth + sidePadding * 2 + timerWidth)
        let x = ((bounds.width - bubbleWidth) / 2).rounded()
        let y = petSize.height + Self.tailHeight + 2
        let box = CGRect(x: x, y: y, width: bubbleWidth, height: Self.bubbleBoxHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubbleBackground.frame = bounds
        bubbleBackground.path = Self.bubblePath(box: box, pointingAtX: bounds.width / 2)
        bubbleBackground.strokeColor = Self.accent(for: oneShotState ?? restingState).cgColor
        bubbleLayer.frame = CGRect(x: box.minX + sidePadding, y: box.minY + 7,
                                   width: textWidth, height: 15)
        bubbleLayer.alignmentMode = .left
        bubbleLayer.contentsScale = window?.backingScaleFactor ?? 2
        if let elapsed {
            timerLayer.string = elapsed
            timerLayer.frame = CGRect(x: box.maxX - sidePadding - timerWidth,
                                      y: box.minY + 7, width: timerWidth, height: 15)
            timerLayer.contentsScale = window?.backingScaleFactor ?? 2
            timerLayer.opacity = 1
        } else {
            timerLayer.opacity = 0
        }
        CATransaction.commit()
    }

    /// A rounded rectangle with a small tail underneath, so the bubble reads as
    /// Mikkel speaking rather than a label floating above him.
    private static func bubblePath(box: CGRect, pointingAtX tipX: CGFloat) -> CGPath {
        let radius: CGFloat = 10
        let path = CGMutablePath()
        path.addRoundedRect(in: box, cornerWidth: radius, cornerHeight: radius)
        // Keep the tail within the straight part of the bottom edge.
        let half = tailWidth / 2
        let centre = min(max(tipX, box.minX + radius + half), box.maxX - radius - half)
        path.move(to: CGPoint(x: centre - half, y: box.minY + 1))
        path.addLine(to: CGPoint(x: centre, y: box.minY - tailHeight))
        path.addLine(to: CGPoint(x: centre + half, y: box.minY + 1))
        path.closeSubpath()
        return path
    }

    // MARK: - Animation clock

    private func startClock() {
        // .common keeps the animation running while the window is being dragged.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var lastTrace = ""
    private func debugTrace(_ message: String, dedupe: Bool = true) {
        guard ProcessInfo.processInfo.environment["MIKKEL_PET_DEBUG"] == "1" else { return }
        if dedupe {
            guard message != lastTrace else { return }
            lastTrace = message
        }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func tick() {
        if updateSleep() { return }
        updateBubble()
        if !isDragging, let pending = pendingResting,
           CACurrentMediaTime() - restingStartedAt >= Self.minimumDwell {
            pendingResting = nil
            if pending != restingState { commitResting(pending) }
        }

        // Idle plus a pointer far enough away means "watch the cursor" instead
        // of playing the idle loop.
        if oneShotState == nil, restingState == .idle, pointerTrackingEnabled,
           let index = pointerLookIndex() {
            if lookIndex != index {
                lookIndex = index
                spriteLayer.contents = atlas.lookCell(index: index)
                debugTrace("look index=\(index)")
            }
            return
        }
        debugTrace("noLook oneShot=\(oneShotState?.rawValue ?? "-") resting=\(restingState.rawValue) track=\(pointerTrackingEnabled) idx=\(pointerLookIndex().map(String.init) ?? "nil")")
        if lookIndex != nil {
            lookIndex = nil
            resetFrame()
        }

        let state = displayState

        if state.playback == .pose {
            holdPose(state)
            return
        }

        let elapsed = (CACurrentMediaTime() - frameStartedAt) * 1000
        let duration = Double(state.durations[min(currentFrame, state.frameCount - 1)]) * speed
        if elapsed >= duration {
            frameStartedAt = CACurrentMediaTime()
            let next = currentFrame + 1
            if next >= state.frameCount {
                if state.isOneShot {
                    oneShotState = nil
                    currentFrame = 0
                    delegate?.petViewOneShotFinished(self, state: state)
                } else {
                    currentFrame = 0
                }
            } else {
                currentFrame = next
            }
        }
        let frame = min(currentFrame, displayState.frameCount - 1)
        spriteLayer.contents = atlas.cell(state: displayState, frame: frame)
    }

    /// Settles him down once nothing has happened for a while, and keeps him
    /// there. Returns true when the rest of the frame should be skipped, since
    /// a sleeping pet neither animates nor follows the pointer.
    private func updateSleep() -> Bool {
        guard sleepAfter > 0 else { return false }
        if !isAsleep {
            guard oneShotState == nil, restingState == .idle, bubbleText.isEmpty,
                  dragOrigin == nil,
                  CACurrentMediaTime() - quietSince >= sleepAfter
            else { return false }
            isAsleep = true
            lookIndex = nil
            spriteLayer.contents = atlas.sleepingCell
            debugTrace("asleep", dedupe: false)
        }
        return true
    }

    /// Brings him back the moment anything happens, including a click.
    func wake() {
        quietSince = CACurrentMediaTime()
        guard isAsleep else { return }
        isAsleep = false
        resetFrame()
        debugTrace("awake", dedupe: false)
    }

    /// Holds one pose for a few seconds, then cuts to a different one. Used for
    /// the states the pet sits in while Claude works, where a flipbook reads as
    /// frantic. The hold scales with Pace like every other duration.
    private func holdPose(_ state: PetState) {
        let now = CACurrentMediaTime()
        if holdFor == 0 || now - frameStartedAt >= holdFor {
            frameStartedAt = now
            let range = Double.random(in: 0..<1) < Self.quickChance ? Self.quickHold : Self.settledHold
            holdFor = Double.random(in: range) * speed
            debugTrace("hold \(state.rawValue) frame=\(currentFrame) for=\(String(format: "%.1f", holdFor))s", dedupe: false)
            if state.frameCount > 1 {
                // Never repeat the current pose, or the hold looks twice as long.
                var next = Int.random(in: 0..<(state.frameCount - 1))
                if next >= currentFrame { next += 1 }
                currentFrame = next
            }
        }
        spriteLayer.contents = atlas.cell(state: state, frame: min(currentFrame, state.frameCount - 1))
    }

    /// Maps the pointer to one of the 16 look cells. `000` is up / 12 o'clock
    /// and the sequence runs clockwise, measured in AppKit's bottom-left origin
    /// screen space. Returns nil inside the deadzone, where the contract says
    /// to fall back to idle.
    private func pointerLookIndex() -> Int? {
        guard let window, window.screen != nil else { return nil }
        let petRect = window.convertToScreen(convert(petFrame, to: nil))
        let center = NSPoint(x: petRect.midX, y: petRect.midY)
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        // Hysteresis: a pointer resting exactly on the boundary would other-
        // wise flip between the idle loop and a look pose every frame.
        let base = max(petRect.width, petRect.height) * 0.75
        let threshold = lookIndex == nil ? base : base * 0.85
        guard (dx * dx + dy * dy) > (threshold * threshold) else { return nil }

        // atan2(dx, dy) is 0 straight up and grows clockwise, matching the atlas.
        var degrees = atan2(dx, dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let step = 360.0 / Double(AtlasGeometry.lookDirectionCount)
        return Int((degrees / step).rounded()) % AtlasGeometry.lookDirectionCount
    }

    // MARK: - Layout

    private var petFrame: CGRect {
        CGRect(x: (bounds.width - petSize.width) / 2, y: 0,
               width: petSize.width, height: petSize.height)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.frame = petFrame
        CATransaction.commit()
        layoutBubble()
    }

    // MARK: - Mouse

    /// Only the pet itself is clickable. The transparent area around the bubble
    /// stays click-through so it never blocks what is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return petFrame.contains(local) ? self : nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        delegate?.petViewMenu(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = delegate?.petViewMenu(self) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseDown(with event: NSEvent) {
        // Control-click is the other way to reach the context menu, and must
        // not also count as a plain click or start a drag.
        if event.modifierFlags.contains(.control) {
            if let menu = delegate?.petViewMenu(self) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
            return
        }
        wake()
        dragOrigin = NSEvent.mouseLocation
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - origin.x
        let dy = mouse.y - origin.y
        if !didDrag, abs(dx) < 3, abs(dy) < 3 { return }
        didDrag = true
        if !isDragging { debugTrace("dragStart", dedupe: false) }
        isDragging = true

        var frame = window.frame
        frame.origin.x += dx
        frame.origin.y += dy
        window.setFrameOrigin(frame.origin)
        dragOrigin = mouse

        // Mikkel runs in whichever direction he is being carried.
        let facing: PetState = dx >= 0 ? .runningRight : .runningLeft
        if dragState != facing {
            dragState = facing
            oneShotState = nil
            commitResting(facing)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        isDragging = false
        if dragState != nil {
            dragState = nil
            // Pick up whatever Claude moved on to while he was being carried.
            commitResting(pendingResting ?? .idle)
            pendingResting = nil
        }
        if !didDrag { delegate?.petViewWasClicked(self) }
        didDrag = false
    }

    deinit { timer?.invalidate() }
}
