import AppKit
import PetCore

/// The den he runs into when he is sent away, and the way back.
///
/// It is its own window rather than part of the pet's. The pet's window is
/// sized to hold his speech bubble, which is 256 points wide, and the whole
/// point of sending him away is to get that off the screen. A door drawn
/// inside that window would take the window's space with it.
final class Den {
    /// Two cells side by side in one PNG: the den empty, and the den with him
    /// inside looking out. The empty one is what he runs into and out of; the
    /// occupied one is what stands there while he is gone.
    enum Cell: Int {
        case empty = 0
        case occupied = 1
    }

    /// Cells are the same height as a pose cell and a third of the width, so a
    /// den and a pet standing side by side match, and one scale setting drives
    /// both.
    static let cellWidth = 64
    static let cellHeight = AtlasGeometry.cellHeight

    private let window: NSWindow
    private let view: DenView
    private(set) var isShowing = false
    /// Which edge he left by. The art is drawn with its cut side on the left,
    /// so it is mirrored to sit against the right-hand edge of a screen.
    private(set) var isOnRightEdge = true

    var onClick: (() -> Void)?

    init?(scale: CGFloat) {
        guard let url = Bundle.main.url(forResource: "den", withExtension: "png")
                ?? Bundle.module.url(forResource: "den", withExtension: "png", subdirectory: "Resources"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let strip = CGImageSourceCreateImageAtIndex(source, 0, nil),
              strip.width == Self.cellWidth * 2, strip.height == Self.cellHeight,
              let empty = strip.cropping(to: CGRect(x: 0, y: 0,
                                                    width: Self.cellWidth, height: Self.cellHeight)),
              let occupied = strip.cropping(to: CGRect(x: Self.cellWidth, y: 0,
                                                       width: Self.cellWidth, height: Self.cellHeight))
        else { return nil }

        view = DenView(empty: empty, occupied: occupied)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size(scale: scale)),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // One above the pet, so he passes behind the den on his way in rather
        // than sliding across the front of it.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = view
        view.onClick = { [weak self] in self?.onClick?() }
    }

    /// Where it is standing, which the pet has to aim at.
    var frame: NSRect { window.frame }

    static func size(scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(cellWidth) * scale, height: CGFloat(cellHeight) * scale)
    }

    /// Puts the den against whichever edge is nearer to `petFrame`, standing on
    /// the same baseline as the pet so the two look like they are on one floor.
    func show(scale: CGFloat, near petFrame: CGRect, on screen: NSScreen) {
        let size = Self.size(scale: scale)
        isOnRightEdge = petFrame.midX >= screen.frame.midX
        let x = isOnRightEdge ? screen.frame.maxX - size.width : screen.frame.minX
        window.setFrame(NSRect(x: x, y: petFrame.minY, width: size.width, height: size.height),
                        display: false)
        view.frame = NSRect(origin: .zero, size: size)
        view.mirrored = isOnRightEdge
        view.cell = .empty
        window.orderFrontRegardless()
        isShowing = true
    }

    func set(_ cell: Cell) { view.cell = cell }

    func hide() {
        window.orderOut(nil)
        isShowing = false
    }

    /// Where the pet's window has to end up for him to be out of sight behind
    /// the den and past the edge.
    ///
    /// Not the den's own centre, which is the obvious answer and the wrong one.
    /// He is 144 points wide and the den is 48, so the den cannot hide him:
    /// stopping him on the doorway leaves most of him standing beside it when
    /// his window goes, which reads as a pop rather than an entrance. Walking
    /// him right off the edge, behind a den whose mouth he is heading into,
    /// lets the eye tell itself the rest.
    func petWindowOriginPastEdge(petWindowWidth: CGFloat, on screen: NSScreen) -> CGFloat {
        isOnRightEdge ? screen.frame.maxX : screen.frame.minX - petWindowWidth
    }
}

/// Draws whichever cell is current and lets clicks through everywhere the den
/// is not, the same way the pet does.
private final class DenView: NSView {
    private let empty: CGImage
    private let occupied: CGImage
    private let layerView = CALayer()

    var onClick: (() -> Void)?

    var cell: Den.Cell = .empty {
        didSet { if cell != oldValue { refresh() } }
    }

    /// The art is drawn cut off on its left, to stand against the left edge of
    /// a screen. Mirroring puts the cut on the right for the other edge.
    var mirrored = false {
        didSet { if mirrored != oldValue { refresh() } }
    }

    init(empty: CGImage, occupied: CGImage) {
        self.empty = empty
        self.occupied = occupied
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(layerView)
        layerView.contentsGravity = .resizeAspect
        layerView.magnificationFilter = .trilinear
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var image: CGImage { cell == .empty ? empty : occupied }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerView.contents = image
        layerView.transform = mirrored
            ? CATransform3DMakeScale(-1, 1, 1)
            : CATransform3DIdentity
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerView.frame = bounds
        CATransaction.commit()
    }

    /// Only the den itself is clickable, so the transparent corners never block
    /// what is underneath. The mask is in the art's own coordinates, so a
    /// mirrored den has to have the point mirrored with it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        var local = convert(point, from: superview)
        if mirrored { local.x = bounds.maxX - (local.x - bounds.minX) }
        return AlphaMask.hits(image, point: local, in: bounds) ? self : nil
    }

    override func mouseUp(with event: NSEvent) { onClick?() }
}
