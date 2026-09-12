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
    private let headerLayer = CATextLayer()
    private let dividerLayer = CALayer()
    /// The balloon is four layers, not one: a shadow to lift it off the
    /// desktop, a gradient fill masked to the outline, the outline itself, and
    /// a highlight along the top so it reads as inflated rather than printed.
    private let bubbleShadow = CAShapeLayer()
    private let bubbleFill = CAGradientLayer()
    private let bubbleFillMask = CAShapeLayer()
    private let bubbleStroke = CAShapeLayer()
    private let bubbleGloss = CAShapeLayer()
    /// Everything the balloon is made of, so it can inflate from its tail as
    /// one piece instead of each layer fading in on its own.
    private let bubbleGroup = CALayer()

    /// Text without the trailing dots, so the dots can animate on their own.
    private var bubbleText = ""
    /// Which session is speaking. Shown as the bubble's header so two Claude
    /// Code windows are told apart at a glance. Empty means no header.
    private var bubbleSession = ""
    /// When the current line started, for the elapsed timer.
    private var lineStartedAt = CACurrentMediaTime()
    /// Whether this line is something in progress rather than a finished state.
    private var lineIsBusy = false
    private var dotPhase = 0
    private var lastBubbleTick: CFTimeInterval = 0

    /// A quick job needs no clock; the timer is for the ones that drag.
    private static let timerAppearsAfter: CFTimeInterval = 4

    /// How long a line that has stopped changing stays up before it fades.
    /// Busy lines are exempt, since their dots and clock are still moving.
    private static let bubbleLingers: CFTimeInterval = 10
    private var bubbleFaded = false

    /// The looping state the pet returns to.
    private var restingState: PetState = .idle
    /// A one-shot (wave, jump, sad) that plays once, then hands back.
    private var oneShotState: PetState?
    /// When the current one-shot began. A posed one-shot has no frame count to
    /// run out, so this is what ends it.
    private var oneShotStartedAt = CACurrentMediaTime()
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
    /// Whether he reacts to the pointer arriving over him.
    var jumpsOnHover = true
    /// Pretends the pointer is on him. Only `--film hover` sets this: it draws
    /// into an offscreen window that the real pointer can never be over, and a
    /// preview that took a different path through the code would be worth
    /// nothing as a preview.
    var simulatesHover = false

    /// A hover jump is his own doing rather than a report about Claude, so it
    /// must not change how the line already on screen reads.
    private var oneShotIsSpontaneous = false
    /// Whether the pointer was over him this frame, so a bounce in progress can
    /// tell whether to come round again.
    private var pointerIsOver = false

    /// How long everything has to stay quiet before he settles down to sleep.
    /// Nought disables it.
    var sleepAfter: TimeInterval = 240
    private var quietSince = CACurrentMediaTime()
    private(set) var isAsleep = false
    /// Where we are in the sleep row: the settle plays once, then breathing
    /// loops. Indices are into SleepRow.settle and SleepRow.breathe.
    private var sleepStep = 0
    private var sleepIsSettling = true
    private var sleepFrameStartedAt = CACurrentMediaTime()

    /// Multiplies every frame duration. The atlas's own timings are tuned for
    /// a lively pet; a companion that animates all day reads better slower.
    var speed: Double = 1.7
    private var lookIndex: Int?
    /// What is actually on screen. Assigning `contents` marks the layer for
    /// display and commits a transaction, which keeps the window compositing
    /// even though the picture is the same one as last frame. Almost every tick
    /// changes nothing: a held pose is a single image for seconds at a time.
    private var displayedCell: CGImage?
    /// Read once per tick. The pointer and his rect on screen were each being
    /// worked out twice a frame, once to decide whether to hop and once to pick
    /// a look direction.
    private var pointerNow = NSPoint.zero
    private var petRectNow: CGRect?
    /// Alpha copies of the cells he has actually been drawn as, so a click can
    /// be tested against his outline instead of the box around it.
    private var hitMasks: [ObjectIdentifier: [UInt8]] = [:]
    /// Whether the cell currently on screen is the blinking twin, so the sprite
    /// is only reassigned when one of the two actually changes.
    private var lookIsBlinking = false
    /// One schedule covers both ways he can be resting. They are mutually
    /// exclusive, and sharing it means crossing between them does not restart
    /// the clock or fire a blink the instant he turns to look at you.
    private var blinkEndsAt: CFTimeInterval = 0
    private var nextBlinkAt: CFTimeInterval = 0

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

    static let tailHeight: CGFloat = 22
    static let tailWidth: CGFloat = 27
    /// A thought balloon trails little bubbles instead of a tail, and they need
    /// more room than the tail does. The box sits at the larger of the two
    /// heights either way, so switching shape never makes it hop.
    static let thoughtTrail: CGFloat = 17
    static var stemHeight: CGFloat { max(tailHeight, thoughtTrail) }

    /// The bubble is kept close to Mikkel's own width so it reads as him
    /// speaking rather than as a banner hung over him. A long line therefore
    /// wraps downward instead of stretching sideways.
    static let bubbleSidePadding: CGFloat = 10
    static let bubbleTopPadding: CGFloat = 6
    static let bubbleBottomPadding: CGFloat = 7
    static let bodyFontSize: CGFloat = 12
    static let bodyLineHeight: CGFloat = 15
    static let headerFontSize: CGFloat = 9
    static let headerHeight: CGFloat = 11
    static let headerGap: CGFloat = 6

    /// Charter for what he says and Menlo for where he is saying it from.
    /// A book serif against a terminal mono: the pairing is the whole idea,
    /// one voice for the sentence and another for the machine's own labels.
    /// Both ship with macOS, so nothing has to be bundled or licensed.
    static func bodyFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "Charter-Roman", size: size)
            ?? NSFont(name: "Charter", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .medium)
    }

    static func labelFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "Menlo-Regular", size: size)
            ?? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    /// Ink, not black: the balloon picks up the deep navy Mikkel is drawn in,
    /// and the text is the cream of his muzzle rather than a flat white.
    static let inkTop = NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.27, alpha: 0.97)
    static let inkBottom = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.13, alpha: 0.97)
    static let cream = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.89, alpha: 1)
    /// Wrapping stops here; a longer line truncates rather than growing a
    /// bubble tall enough to cover the screen.
    static let bubbleMaxLines = 4
    /// The window has to reserve the tallest bubble it could ever draw: it is
    /// borderless, so anything outside the frame is clipped away.
    static let bubbleMaxBoxHeight: CGFloat =
        bubbleTopPadding + headerHeight + headerGap
        + bodyLineHeight * CGFloat(bubbleMaxLines) + bubbleBottomPadding
    /// Vertical room the window must leave above the pet.
    static let bubbleHeight: CGFloat = bubbleMaxBoxHeight + stemHeight + 2
    /// Minimum window width. The bubble drawn inside it is capped separately,
    /// near the pet's own width, by `maxBubbleWidth`.
    static let bubbleWidth: CGFloat = 280

    /// No wider than Mikkel himself. The sprite cell has transparent margins,
    /// so his drawn body is about 0.88 of the cell — matching that, rather than
    /// the cell, is what makes the bubble look like it belongs to him. There is
    /// a floor so the text stays readable when he is scaled right down.
    private var maxBubbleWidth: CGFloat {
        min(bounds.width - 8, max((petSize.width * 0.88).rounded(), 120))
    }

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

        bubbleGroup.opacity = 0
        layer?.addSublayer(bubbleGroup)

        // Cast from just under the balloon, so it floats rather than sits.
        bubbleShadow.fillColor = Self.inkBottom.cgColor
        bubbleShadow.shadowColor = NSColor.black.cgColor
        bubbleShadow.shadowOpacity = 0.5
        bubbleShadow.shadowRadius = 9
        bubbleShadow.shadowOffset = CGSize(width: 0, height: -3)
        bubbleGroup.addSublayer(bubbleShadow)

        // A top-lit gradient. Flat fill reads as a label; a lit one reads as a
        // balloon with air in it.
        bubbleFill.colors = [Self.inkTop.cgColor, Self.inkBottom.cgColor]
        bubbleFill.startPoint = CGPoint(x: 0.5, y: 1)
        bubbleFill.endPoint = CGPoint(x: 0.5, y: 0)
        bubbleFill.mask = bubbleFillMask
        bubbleGroup.addSublayer(bubbleFill)

        bubbleStroke.fillColor = NSColor.clear.cgColor
        bubbleStroke.strokeColor = Self.accent(for: .idle).cgColor
        bubbleStroke.lineWidth = 1.4
        bubbleStroke.lineJoin = .round
        bubbleGroup.addSublayer(bubbleStroke)

        // The catchlight across the top curve. Barely there on purpose: enough
        // to suggest a lit surface, not enough to notice as a stripe.
        bubbleGloss.fillColor = NSColor.clear.cgColor
        bubbleGloss.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.22).cgColor
        bubbleGloss.lineWidth = 1
        bubbleGloss.lineCap = .round
        bubbleGroup.addSublayer(bubbleGloss)

        // The balloon grows and shrinks with the text, so let those changes
        // ease rather than snap between widths.
        for shape in [bubbleShadow, bubbleFillMask, bubbleStroke, bubbleGloss] {
            shape.actions = ["path": CABasicAnimation(keyPath: "path")]
        }

        bubbleLayer.font = Self.bodyFont(Self.bodyFontSize)
        bubbleLayer.fontSize = Self.bodyFontSize
        bubbleLayer.foregroundColor = Self.cream.cgColor
        bubbleLayer.alignmentMode = .left
        // Wrapped, but still truncating: the line cap is enforced by the frame
        // height, and .end puts an ellipsis on whatever does not fit.
        bubbleLayer.truncationMode = .end
        bubbleLayer.isWrapped = true
        bubbleGroup.addSublayer(bubbleLayer)

        headerLayer.font = Self.labelFont(Self.headerFontSize)
        headerLayer.fontSize = Self.headerFontSize
        headerLayer.foregroundColor = NSColor(
            calibratedRed: 0.66, green: 0.74, blue: 0.88, alpha: 0.90).cgColor
        headerLayer.alignmentMode = .left
        // A long project name loses its middle, not its end: the tail of a
        // path is what tells two checkouts of the same repo apart.
        headerLayer.truncationMode = .middle
        headerLayer.isWrapped = false
        headerLayer.opacity = 0
        bubbleGroup.addSublayer(headerLayer)

        dividerLayer.backgroundColor = NSColor(
            calibratedRed: 0.70, green: 0.77, blue: 0.90, alpha: 0.18).cgColor
        dividerLayer.opacity = 0
        bubbleGroup.addSublayer(dividerLayer)

        timerLayer.font = Self.labelFont(Self.headerFontSize)
        timerLayer.fontSize = Self.headerFontSize
        timerLayer.foregroundColor = NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.25, alpha: 0.90).cgColor
        timerLayer.alignmentMode = .right
        timerLayer.opacity = 0
        bubbleGroup.addSublayer(timerLayer)

        startClock()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - State

    func apply(resting: PetState, oneShot: PetState?, label: String, session: String) {
        // Anything other than a silent idle counts as activity.
        if resting != .idle || oneShot != nil || (!label.isEmpty && label != bubbleText) {
            quietSince = CACurrentMediaTime()
            wake()
        }

        // One-shots are the reactions worth interrupting for, so they skip the
        // dwell window.
        if let oneShot, oneShot != oneShotState {
            oneShotState = oneShot
            oneShotIsSpontaneous = false
            oneShotStartedAt = CACurrentMediaTime()
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
        setBubble(label, session: session)
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

    private func setBubble(_ text: String, session: String) {
        guard text != bubbleText || session != bubbleSession else { return }
        // The same line attributed to a newly-pinned session is not a new line,
        // so the clock and the fade timer must not restart under it.
        let isNewLine = text != bubbleText
        bubbleText = text
        bubbleSession = session
        if isNewLine {
            lineStartedAt = CACurrentMediaTime()
            dotPhase = 0
            bubbleFaded = false
        }
        headerLayer.string = session
        let visible = !text.isEmpty && !bubbleFaded
        let wasHidden = bubbleGroup.opacity < 0.5
        // Lay the balloon out before showing it, or the inflate would start
        // from the previous line's shape and anchor.
        layoutBubble()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        bubbleLayer.opacity = visible ? 1 : 0
        bubbleGroup.opacity = visible ? 1 : 0
        let showsHeader = visible && !session.isEmpty
        headerLayer.opacity = showsHeader ? 1 : 0
        dividerLayer.opacity = showsHeader ? 1 : 0
        timerLayer.opacity = 0
        CATransaction.commit()

        if visible, wasHidden { inflate() }
    }

    /// The balloon puffs out of his tail rather than fading in on the spot.
    /// A spring, not a curve: the small overshoot is what sells it as a breath
    /// of air going in.
    private func inflate() {
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.82
        pop.toValue = 1
        pop.damping = 13
        pop.stiffness = 260
        pop.mass = 0.6
        pop.initialVelocity = 7
        pop.duration = pop.settlingDuration
        bubbleGroup.add(pop, forKey: "inflate")
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

    /// Busy lines get animated dots and, once they drag on, a clock. A jump he
    /// did because you waved the pointer at him says nothing about the job, so
    /// it is not allowed to interrupt any of that.
    private var isBusyLine: Bool {
        guard oneShotState == nil || oneShotIsSpontaneous else { return false }
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
        guard !bubbleText.isEmpty, !bubbleFaded else { return }
        let now = CACurrentMediaTime()
        guard now - lastBubbleTick >= 0.4 else { return }
        lastBubbleTick = now

        // Something finished a while ago and nothing has replaced it. Leaving
        // "All done" up forever reads as stuck, so retire it.
        if !isBusyLine, now - lineStartedAt >= Self.bubbleLingers {
            fadeBubble()
            return
        }

        if isBusyLine { dotPhase = (dotPhase + 1) % 4 }
        layoutBubble()
    }

    private func fadeBubble() {
        bubbleFaded = true
        headerLayer.opacity = 0
        dividerLayer.opacity = 0
        // Deflating back towards the tail, which is where it came from.
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.94
        shrink.duration = 0.45
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        bubbleGroup.add(shrink, forKey: "deflate")
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        bubbleLayer.opacity = 0
        bubbleGroup.opacity = 0
        timerLayer.opacity = 0
        CATransaction.commit()
    }

    /// Wrapping has to be specified rather than left to the layer: a bare
    /// string in a `CATextLayer` breaks mid-word, which would also disagree
    /// with the word-wrapped measurement below and mis-size the bubble.
    private static let bodyAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        return [
            .font: bodyFont(bodyFontSize),
            .paragraphStyle: style,
            .foregroundColor: cream,
        ]
    }()

    private func layoutBubble() {
        guard !bubbleText.isEmpty else { return }
        let dots = isBusyLine ? String(repeating: "\u{00B7}", count: dotPhase) : ""
        let line = dots.isEmpty ? bubbleText : "\(bubbleText) \(dots)"
        bubbleLayer.string = NSAttributedString(string: line, attributes: Self.bodyAttributes)

        let headerFont = Self.labelFont(Self.headerFontSize)
        let side = Self.bubbleSidePadding
        let cap = maxBubbleWidth
        let textCap = cap - side * 2

        // Measure the widest form so cycling dots never resize the bubble.
        let widest = isBusyLine ? "\(bubbleText) \u{00B7}\u{00B7}\u{00B7}" : bubbleText
        let measured = (widest as NSString).boundingRect(
            with: CGSize(width: textCap, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: Self.bodyAttributes)
        let lineCount = min(Self.bubbleMaxLines,
                            max(1, Int((measured.height / Self.bodyLineHeight).rounded(.up))))
        let textHeight = CGFloat(lineCount) * Self.bodyLineHeight
        // One line hugs its own text. A wrapped one always fills the cap: a
        // ragged right edge on a bubble this narrow just looks like a bug.
        let textWidth = lineCount == 1 ? min(measured.width.rounded(.up), textCap) : textCap

        let elapsed = elapsedText()
        // Room for "10:05". It sits in the header row now, beside the session
        // name, which keeps the body free for the sentence itself.
        let timerWidth: CGFloat = elapsed == nil ? 0 : 32
        let hasHeader = !bubbleSession.isEmpty
        let nameWidth = hasHeader
            ? (bubbleSession as NSString)
                .size(withAttributes: [.font: headerFont]).width.rounded(.up)
            : 0
        let headerWidth = hasHeader ? nameWidth + (timerWidth > 0 ? timerWidth + 6 : 0) : 0

        let boxWidth = min(cap, (max(textWidth, headerWidth) + side * 2).rounded())
        var boxHeight = Self.bubbleTopPadding + textHeight + Self.bubbleBottomPadding
        if hasHeader { boxHeight += Self.headerHeight + Self.headerGap }

        // Anchored just above his head and grown upward, so a short line sits
        // close to him instead of floating with dead air underneath.
        let x = ((bounds.width - boxWidth) / 2).rounded()
        let y = petSize.height + Self.stemHeight + 2
        let box = CGRect(x: x, y: y, width: boxWidth, height: boxHeight)
        let scale = window?.backingScaleFactor ?? 2

        let tip = bounds.width / 2
        let shape = wantsThoughtBalloon
            ? Self.thoughtPath(box: box, pointingAtX: tip)
            : Self.speechPath(box: box, pointingAtX: tip)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The group is anchored at the tail so the balloon inflates out of him
        // rather than swelling from its own middle.
        bubbleGroup.bounds = CGRect(origin: .zero, size: bounds.size)
        let anchor = CGPoint(x: tip / max(bounds.width, 1),
                             y: (box.minY - Self.tailHeight) / max(bounds.height, 1))
        bubbleGroup.anchorPoint = anchor
        bubbleGroup.position = CGPoint(x: bounds.width * anchor.x, y: bounds.height * anchor.y)

        for shape in [bubbleShadow, bubbleFillMask, bubbleStroke] { shape.frame = bounds }
        bubbleShadow.path = shape
        bubbleShadow.shadowPath = shape
        bubbleFillMask.path = shape
        bubbleFill.frame = bounds
        bubbleStroke.path = shape
        bubbleStroke.strokeColor = Self.accent(for: oneShotState ?? restingState).cgColor
        bubbleGloss.frame = bounds
        bubbleGloss.path = Self.glossPath(box: box)
        // A drawn cloud has no straight top to catch the light.
        bubbleGloss.opacity = wantsThoughtBalloon ? 0 : 1

        bubbleLayer.frame = CGRect(x: box.minX + side, y: box.minY + Self.bubbleBottomPadding,
                                   width: boxWidth - side * 2, height: textHeight)
        bubbleLayer.contentsScale = scale

        if hasHeader {
            let headerY = box.maxY - Self.bubbleTopPadding - Self.headerHeight
            headerLayer.frame = CGRect(x: box.minX + side, y: headerY,
                                       width: boxWidth - side * 2 - timerWidth,
                                       height: Self.headerHeight)
            headerLayer.contentsScale = scale
            dividerLayer.frame = CGRect(x: box.minX + side,
                                        y: (headerY - Self.headerGap / 2).rounded(),
                                        width: boxWidth - side * 2, height: 1)
        }

        if let elapsed {
            timerLayer.string = elapsed
            // Beside the name when there is a header, otherwise where the old
            // single-row bubble put it.
            let timerY = hasHeader
                ? box.maxY - Self.bubbleTopPadding - Self.headerHeight
                : box.minY + Self.bubbleBottomPadding
            timerLayer.frame = CGRect(x: box.maxX - side - timerWidth, y: timerY,
                                      width: timerWidth,
                                      height: hasHeader ? Self.headerHeight : Self.bodyLineHeight)
            timerLayer.contentsScale = scale
            timerLayer.opacity = 1
        } else {
            timerLayer.opacity = 0
        }
        CATransaction.commit()
    }

    /// Which balloon he gets. He thinks while he is working and speaks when he
    /// is addressing you, so the shape says which is happening before a single
    /// word has been read.
    private var wantsThoughtBalloon: Bool { isBusyLine }

    /// A speech balloon: generous corners and a tail that hooks, the way a
    /// drawn one does. A straight triangle is a tooltip; the curve is what
    /// makes it read as speech.
    ///
    /// It is walked as one continuous outline, tail included, rather than a
    /// rounded rect with a tail dropped behind it. Two subpaths would stroke
    /// the balloon's own bottom edge straight across the top of the tail.
    private static func speechPath(box: CGRect, pointingAtX tipX: CGFloat) -> CGPath {
        let radius: CGFloat = 13
        let half = tailWidth / 2
        let centre = min(max(tipX, box.minX + radius + half), box.maxX - radius - half)
        let height = tailHeight
        // The tip leans well off centre. A tail on a plumb line is a tooltip
        // arrow; the lean is most of what makes this one look drawn.
        let tip = CGPoint(x: centre - tailWidth * 0.44, y: box.minY - height)

        let bottomLeft = CGPoint(x: box.minX, y: box.minY)
        let bottomRight = CGPoint(x: box.maxX, y: box.minY)
        let topRight = CGPoint(x: box.maxX, y: box.maxY)
        let topLeft = CGPoint(x: box.minX, y: box.maxY)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: box.minX + radius, y: box.minY))
        path.addLine(to: CGPoint(x: centre - half, y: box.minY))
        // Cubics on both edges, curving the same way, which is what gives a
        // drawn tail its comma sweep. A quad on each side stays too close to
        // straight to read as anything but an arrow.
        path.addCurve(to: tip,
                      control1: CGPoint(x: centre - half * 0.95, y: box.minY - height * 0.42),
                      control2: CGPoint(x: tip.x - 2.5, y: tip.y + height * 0.34))
        path.addCurve(to: CGPoint(x: centre + half * 0.42, y: box.minY),
                      control1: CGPoint(x: tip.x + 6, y: tip.y + height * 0.26),
                      control2: CGPoint(x: centre + half * 0.30, y: box.minY - height * 0.52))
        // Each tangent arc draws the rest of its edge and then rounds the
        // corner, so the four of them close the balloon.
        path.addArc(tangent1End: bottomRight, tangent2End: topRight, radius: radius)
        path.addArc(tangent1End: topRight, tangent2End: topLeft, radius: radius)
        path.addArc(tangent1End: topLeft, tangent2End: bottomLeft, radius: radius)
        path.addArc(tangent1End: bottomLeft, tangent2End: bottomRight, radius: radius)
        path.closeSubpath()
        return path
    }

    /// A thought balloon: the box's outline replaced by a run of arcs, with two
    /// little bubbles trailing down to him. The scallops are walked as arcs
    /// rather than stamped as overlapping circles, because a stamped cloud
    /// strokes all of its own internal seams.
    private static func thoughtPath(box: CGRect, pointingAtX tipX: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let inset = box.insetBy(dx: 3, dy: 3)

        // Corners are walked clockwise, and every bump bulges outward, which is
        // always the decreasing-angle sweep from its start point to its end.
        let corners = [
            CGPoint(x: inset.minX, y: inset.maxY), CGPoint(x: inset.maxX, y: inset.maxY),
            CGPoint(x: inset.maxX, y: inset.minY), CGPoint(x: inset.minX, y: inset.minY),
        ]
        let target: CGFloat = 11
        var started = false

        for index in corners.indices {
            let from = corners[index], to = corners[(index + 1) % corners.count]
            let span = hypot(to.x - from.x, to.y - from.y)
            let count = max(2, Int((span / target).rounded()))
            for step in 0..<count {
                let t0 = CGFloat(step) / CGFloat(count), t1 = CGFloat(step + 1) / CGFloat(count)
                let a = CGPoint(x: from.x + (to.x - from.x) * t0, y: from.y + (to.y - from.y) * t0)
                let b = CGPoint(x: from.x + (to.x - from.x) * t1, y: from.y + (to.y - from.y) * t1)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let radius = hypot(b.x - a.x, b.y - a.y) / 2
                if !started { path.move(to: a); started = true }
                path.addArc(center: mid, radius: radius,
                            startAngle: atan2(a.y - mid.y, a.x - mid.x),
                            endAngle: atan2(b.y - mid.y, b.x - mid.x),
                            clockwise: true)
            }
        }
        path.closeSubpath()

        // The trail. Offset a little, because two dots on a plumb line look
        // mechanical and a thought does not.
        let trail: [(CGFloat, CGFloat, CGFloat)] = [(1.5, 5.5, 3.6), (-1.5, 14.0, 2.1)]
        for (dx, drop, radius) in trail {
            path.addEllipse(in: CGRect(x: tipX + dx - radius, y: box.minY - drop - radius,
                                       width: radius * 2, height: radius * 2))
        }
        return path
    }

    /// The catchlight: the top edge alone, drawn just inside the outline.
    private static func glossPath(box: CGRect) -> CGPath {
        let radius: CGFloat = 13
        let path = CGMutablePath()
        let y = box.maxY - 2.5
        path.move(to: CGPoint(x: box.minX + radius, y: y))
        path.addLine(to: CGPoint(x: box.maxX - radius - 2, y: y))
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
        pointerNow = NSEvent.mouseLocation
        petRectNow = (window?.screen != nil)
            ? window.map { $0.convertToScreen(convert(petFrame, to: nil)) }
            : nil

        if updateSleep() { return }
        updateBubble()
        if !isDragging, let pending = pendingResting,
           CACurrentMediaTime() - restingStartedAt >= Self.minimumDwell {
            pendingResting = nil
            if pending != restingState { commitResting(pending) }
        }

        updateHover()

        // Idle plus a pointer far enough away means "watch the cursor" instead
        // of playing the idle loop.
        if oneShotState == nil, restingState == .idle, pointerTrackingEnabled,
           let index = pointerLookIndex() {
            let blinking = updateBlink(hasArt: atlas.lookBlinkCell(index: index) != nil)
            if lookIndex != index || lookIsBlinking != blinking {
                lookIndex = index
                lookIsBlinking = blinking
                // Falls back to the open-eyed cell rather than assigning nil,
                // which would leave nothing on screen at all.
                show((blinking ? atlas.lookBlinkCell(index: index) : nil)
                    ?? atlas.lookCell(index: index))
                debugTrace("look index=\(index) blink=\(blinking)", dedupe: false)
            }
            return
        }
        lookIsBlinking = false
        debugTrace("noLook oneShot=\(oneShotState?.rawValue ?? "-") resting=\(restingState.rawValue) track=\(pointerTrackingEnabled) idx=\(pointerLookIndex().map(String.init) ?? "nil")")
        if lookIndex != nil {
            lookIndex = nil
            resetFrame()
        }

        // A posed one-shot ends on a clock, since it has no frames to run out.
        if let posed = oneShotState, posed.playback == .pose,
           let budget = posed.poseOneShotDuration,
           // Not scaled by Pace either: the budget is set against how long the
           // bubble stays up, so stretching it would outlive the line it goes
           // with.
           CACurrentMediaTime() - oneShotStartedAt >= budget {
            oneShotState = nil
            oneShotIsSpontaneous = false
            resetFrame()
            delegate?.petViewOneShotFinished(self, state: posed)
        }

        let state = displayState

        if state.playback == .pose {
            holdPose(state)
            return
        }

        let elapsed = (CACurrentMediaTime() - frameStartedAt) * 1000
        // Pace governs how long he sits still, not how fast a movement plays.
        // Stretching a jump by 1.7 does not make it calmer, it makes it slow
        // motion, and the arc stops reading as a jump at all. Within a single
        // row that line runs per frame: the idle loop's long open-eyed holds
        // stretch with Pace, the blink in the middle of them does not.
        let authored = state.durations[min(currentFrame, state.frameCount - 1)]
        let duration = authored >= PetState.holdFrameMilliseconds
            ? Double(authored) * speed
            : Double(authored)
        if elapsed >= duration {
            frameStartedAt = CACurrentMediaTime()
            let next = currentFrame + 1
            if next >= state.frameCount {
                if state.isOneShot, shouldKeepBouncing {
                    // Come round in place instead of ending the one-shot and
                    // starting another. Ending it would draw a single frame of
                    // the resting pose between hops, which reads as a flicker.
                    //
                    // Frame 0 is skipped on the way round: it is the same
                    // upright sit as the recover frame that has just played, so
                    // running both holds that pose for a third of a second and
                    // makes him look like he is hesitating. Landing straight in
                    // the crouch keeps the bounce continuous.
                    currentFrame = state.frameCount > 1 ? 1 : 0
                } else if state.isOneShot {
                    oneShotState = nil
                    oneShotIsSpontaneous = false
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
        show(atlas.cell(state: displayState, frame: frame))
    }

    /// Settles him down once nothing has happened for a while, and keeps him
    /// there. Returns true when the rest of the frame should be skipped, since
    /// a sleeping pet neither animates nor follows the pointer.
    private func updateSleep() -> Bool {
        guard sleepAfter > 0 else { return false }
        if !isAsleep {
            guard oneShotState == nil, restingState == .idle,
                  bubbleText.isEmpty || bubbleFaded,
                  dragOrigin == nil,
                  CACurrentMediaTime() - quietSince >= sleepAfter
            else { return false }
            isAsleep = true
            lookIndex = nil
            sleepStep = 0
            sleepIsSettling = true
            sleepFrameStartedAt = CACurrentMediaTime()
            show(atlas.sleepCell(column: SleepRow.settle[0]))
            debugTrace("asleep", dedupe: false)
            return true
        }
        advanceSleepFrame()
        return true
    }

    /// Plays the settle once, then loops the breathing. Same wall-clock timing
    /// as the other rows, and the Pace setting stretches it alike.
    private func advanceSleepFrame() {
        let frames = sleepIsSettling ? SleepRow.settle : SleepRow.breathe
        let durations = sleepIsSettling ? SleepRow.settleDurations : SleepRow.breatheDurations
        let step = min(sleepStep, frames.count - 1)
        let elapsed = (CACurrentMediaTime() - sleepFrameStartedAt) * 1000
        if elapsed >= Double(durations[step]) * speed {
            sleepFrameStartedAt = CACurrentMediaTime()
            sleepStep = step + 1
            if sleepStep >= frames.count {
                sleepStep = 0
                // The settle ends on the breathing loop's opening pose, so this
                // hands over without a jump.
                sleepIsSettling = false
            }
        }
        let current = sleepIsSettling ? SleepRow.settle : SleepRow.breathe
        show(atlas.sleepCell(column: current[min(sleepStep, current.count - 1)]))
    }

    /// Settles him immediately rather than waiting out the idle timer. Used
    /// when the last Claude Code session closes, where there is plainly nothing
    /// left to watch. Respects the sleep setting being turned off.
    func sleepNow() {
        guard sleepAfter > 0, !isAsleep, dragOrigin == nil else { return }
        setBubble("", session: "")
        oneShotState = nil
        restingState = .idle
        pendingResting = nil
        // Backdating the quiet clock lets the normal path start the settle on
        // the next frame, so there is one way in and out of sleep.
        quietSince = CACurrentMediaTime() - sleepAfter
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
        let frame = min(currentFrame, state.frameCount - 1)
        let blinking = updateBlink(hasArt: atlas.blinkCell(state: state, frame: frame) != nil)
        show((blinking ? atlas.blinkCell(state: state, frame: frame) : nil)
            ?? atlas.cell(state: state, frame: frame))
    }

    /// He bounces for as long as the pointer is over him. Each jump is the
    /// ordinary one-shot, restarted the moment the last one hands back, so the
    /// loop is just the animation played again rather than a second code path.
    /// The pointer is polled rather than tracked with an `NSTrackingArea`,
    /// because the app is an accessory and spends its life inactive, where
    /// enter and exit events are a fight.
    /// Whether a bounce already under way should come round again rather than
    /// hand back to the resting pose.
    private var shouldKeepBouncing: Bool {
        oneShotIsSpontaneous && pointerIsOver && jumpsOnHover && !isDragging && !isAsleep
    }

    private func updateHover() {
        pointerIsOver = simulatesHover || pointerIsOnPet()
        guard pointerIsOver else { return }
        // Being hovered counts as activity, or he could drop off to sleep in
        // the one-frame gap between two jumps.
        quietSince = CACurrentMediaTime()
        guard jumpsOnHover, !isDragging, !isAsleep, oneShotState == nil else { return }
        oneShotState = .jumping
        oneShotIsSpontaneous = true
        oneShotStartedAt = CACurrentMediaTime()
        resetFrame()
        debugTrace("hover jump", dedupe: false)
    }

    private func petScreenRect() -> CGRect? { petRectNow }

    /// Whether the pointer is on the pet himself. The bounding box would also
    /// cover the transparent corners of his cell, where a hop reads as him
    /// reacting to nothing. Goes through the same test a click does, rather
    /// than a second mapping that could disagree with it.
    private func pointerIsOnPet() -> Bool {
        guard petRectNow != nil, let window else { return false }
        return pointIsOnPet(convert(window.convertPoint(fromScreen: pointerNow), from: nil))
    }

    /// Shows a cell, and does nothing at all when it is already the one on
    /// screen. This is the difference between compositing sixty times a second
    /// and compositing when something actually changes.
    private func show(_ image: CGImage?) {
        guard image !== displayedCell else { return }
        displayedCell = image
        spriteLayer.contents = image
    }

    /// Watching the pointer is a single still cell held for as long as you keep
    /// the mouse still, which is where he spends most of his idle life. Without
    /// this he would blink only in the brief moments he is not watching you.
    ///
    /// The cadence is taken from the idle row rather than invented, so the two
    /// ways he can be resting blink at the same rate, and changing the idle
    /// timing changes this with it. It is jittered because a blink on a fixed
    /// interval reads as a metronome.
    private static let blinkDuration: CFTimeInterval = 0.13

    /// Whether he should be showing a closed-eye frame right now. `hasArt` says
    /// whether the cell he is on has a twin; a pose or direction without one
    /// simply does not blink, and moving onto one part-way through a blink
    /// opens his eyes rather than drawing nothing.
    private func updateBlink(hasArt: @autoclosure () -> Bool) -> Bool {
        let now = CACurrentMediaTime()
        if now < blinkEndsAt { return hasArt() }

        if nextBlinkAt == 0 || now >= nextBlinkAt {
            let base = Double(PetState.idle.blinkIntervalMilliseconds) / 1000 * speed
            let scheduled = base * Double.random(in: 0.75...1.25)
            // A cell with no twin still gets a new appointment, so he does not
            // blink the instant he moves onto one that has art.
            if nextBlinkAt != 0, hasArt() {
                blinkEndsAt = now + Self.blinkDuration
                nextBlinkAt = now + Self.blinkDuration + scheduled
                return true
            }
            nextBlinkAt = now + scheduled
        }
        return false
    }

    /// Maps the pointer to one of the 16 look cells. `000` is up / 12 o'clock
    /// and the sequence runs clockwise, measured in AppKit's bottom-left origin
    /// screen space. Returns nil inside the deadzone, where the contract says
    /// to fall back to idle.
    private func pointerLookIndex() -> Int? {
        guard let petRect = petScreenRect() else { return nil }
        let center = NSPoint(x: petRect.midX, y: petRect.midY)
        let mouse = pointerNow
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

    /// Only the pet itself is clickable. The transparent area around the
    /// bubble, and the empty corners of his own cell, stay click-through so
    /// neither blocks what is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        pointIsOnPet(convert(point, from: superview)) ? self : nil
    }

    /// Deliberately not the checker's 40. That script measures how far a
    /// silhouette moved, where a generous cut suppresses anti-aliasing noise.
    /// Here the anti-aliased rim is exactly what you reach for when grabbing
    /// an ear or the tip of his tail, so it has to count as him.
    private static let hitAlphaThreshold: UInt8 = 10

    /// Whether a point in this view's own coordinates lands on the pet rather
    /// than on the transparent margin inside his cell.
    private func pointIsOnPet(_ local: CGPoint) -> Bool {
        let frame = petFrame
        guard frame.contains(local), let cell = displayedCell else { return false }
        // The cell is drawn with `resizeAspect` into a box of its own
        // proportions, so this is a straight scale with no letterboxing to
        // allow for. The y axis flips: the view's grows up, the mask's down.
        let across = (local.x - frame.minX) / frame.width
        let down = 1 - (local.y - frame.minY) / frame.height
        let x = min(cell.width - 1, max(0, Int(across * CGFloat(cell.width))))
        let y = min(cell.height - 1, max(0, Int(down * CGFloat(cell.height))))
        return hitMask(for: cell)[y * cell.width + x] > Self.hitAlphaThreshold
    }

    /// The alpha channel of a cell, one byte per pixel, built on first use and
    /// kept. Cells come from the atlas's own cache, so a pose is always the
    /// same object and its mask is built once rather than once per click.
    ///
    /// Reading `dataProvider` would be cheaper and wrong: a cell is a crop of
    /// the sheet, and a crop can hand back the whole sheet's bytes with the
    /// crop carried as metadata.
    private func hitMask(for cell: CGImage) -> [UInt8] {
        let key = ObjectIdentifier(cell)
        if let cached = hitMasks[key] { return cached }
        let width = cell.width, height = cell.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(cell, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var mask = [UInt8](repeating: 0, count: width * height)
        for i in mask.indices { mask[i] = pixels[i * 4 + 3] }
        hitMasks[key] = mask
        return mask
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
