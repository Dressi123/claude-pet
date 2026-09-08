// Renders one frame of the pet to a PNG.
//
// The pet cannot be screenshotted the usual way: screen recording permission
// is denied for the terminal, so there is no way to look at the bubble while
// working on it. This draws the same view tree offscreen and writes it to a
// file instead, which is enough to check geometry — widths, wrapping, where
// the header sits. It is a development aid; nothing in the running app calls
// it, and it is reachable only through `--snapshot`.

import AppKit
import PetCore

enum Snapshot {
    /// Trims the transparent margin, so the artwork carries no dead space with
    /// it. The window reserves room for the tallest balloon it could draw, and
    /// most frames use nowhere near it.
    private static func crop(_ rep: NSBitmapImageRep, scale: CGFloat) -> NSBitmapImageRep {
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return rep }
        let width = rep.pixelsWide, height = rep.pixelsHigh, row = rep.bytesPerRow
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[y * row + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return rep }
        let pad = Int(4 * scale)
        minX = max(0, minX - pad); minY = max(0, minY - pad)
        maxX = min(width - 1, maxX + pad); maxY = min(height - 1, maxY + pad)
        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let image = rep.cgImage?.cropping(to: box) else { return rep }
        let out = NSBitmapImageRep(cgImage: image)
        out.size = NSSize(width: box.width / scale, height: box.height / scale)
        return out
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    /// Records a scripted session as numbered frames, so the balloon can be
    /// watched inflating and changing shape rather than only inspected at rest.
    /// Frames come off the presentation layer, which is the one carrying the
    /// in-flight animation; the model layer would only ever show the end state.
    static func film(into directory: String, script name: String) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let atlas = try Atlas()
        let view = PetView(atlas: atlas)
        let size = CGSize(width: max(PetView.bubbleWidth, view.petSize.width),
                          height: view.petSize.height + PetView.bubbleHeight + 4)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)

        try FileManager.default.createDirectory(atPath: directory,
                                                withIntermediateDirectories: true)

        // A plausible minute of work: he greets, thinks about a couple of jobs,
        // one drags long enough to earn a clock, one fails, then he is done.
        let session: [(TimeInterval, PetState, PetState?, String, String)] = [
            (0.0, .idle, .waving, "Hello", "claude-pet"),
            (1.6, .review, nil, "Let me look at PetView.swift", "claude-pet"),
            (3.2, .running, nil, "Tidying up the balloon paths", "claude-pet"),
            (7.4, .failed, nil, "Hm, that didn't work", "claude-pet"),
            (9.2, .running, nil, "Let me run the test suite", "claude-pet"),
            (11.0, .idle, nil, "All done", "claude-pet"),
        ]

        // Long enough to watch the failure settle through several poses and
        // then hand back to whatever he was doing.
        let failure: [(TimeInterval, PetState, PetState?, String, String)] = [
            (0.0, .running, nil, "Running the test suite", "claude-pet"),
            (1.5, .running, .failed, "Hm, that didn't work", "claude-pet"),
        ]

        // Any state name is accepted too, which gives a plain demo of that one
        // reaction over a resting pet: `--film <dir> jumping`.
        let single = PetState(rawValue: name).map { state -> [(TimeInterval, PetState, PetState?, String, String)] in
            [(0.0, .idle, nil, "", ""),
             (0.9, .idle, state.isOneShot ? state : nil, "", "")]
        }

        // A hover runs the pet's own loop; the view is only told to believe the
        // pointer is on it, since an offscreen window can never really be under
        // the cursor.
        let hover: [(TimeInterval, PetState, PetState?, String, String)] =
            [(0.0, .idle, nil, "", "")]
        if name == "hover" { view.simulatesHover = true }

        let script: [(TimeInterval, PetState, PetState?, String, String)]
        let total: TimeInterval
        switch name {
        case "hover": script = hover; total = 7.0
        case "failure": script = failure; total = 14.0
        case "session": script = session; total = 13.0
        default:
            guard let single else {
                throw Failure("unknown script \(name); try session, failure, or a state name")
            }
            script = single
            total = 5.0
        }

        // Frames are captured as fast as they render, which is slower than the
        // target. The achieved rate is printed so the GIF can be timed to it.
        let fps = 30.0
        var cue = 0
        var frame = 0
        let started = Date()

        while true {
            let now = Date().timeIntervalSince(started)
            if now >= total { break }
            while cue < script.count, script[cue].0 <= now {
                let (_, resting, oneShot, label, session) = script[cue]
                view.apply(resting: resting, oneShot: oneShot, label: label, session: session)
                cue += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1.0 / fps))

            let path = String(format: "%@/frame-%04d.png", directory, frame)
            // Film frames are captured at 1x: the render is the bottleneck, and
            // at 2x the capture rate drops low enough to make motion stutter.
            try render(view: view, size: size, to: path, usePresentation: true, pixelScale: 1)
            frame += 1
        }
        let elapsed = Date().timeIntervalSince(started)
        let achieved = Double(frame) / elapsed
        FileHandle.standardOutput.write(Data(
            String(format: "wrote %d frames at %.1f fps\n", frame, achieved).utf8))
    }

    private static func render(view: NSView, size: CGSize, to path: String,
                               usePresentation: Bool, pixelScale: CGFloat = 2) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * pixelScale),
            pixelsHigh: Int(size.height * pixelScale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw Failure("could not allocate the bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: pixelScale, y: pixelScale)
        NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let source = usePresentation ? (view.layer?.presentation() ?? view.layer) : view.layer
        source?.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Failure("could not encode the PNG")
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func write(to path: String, label: String, session: String, state: PetState) throws {
        // Fonts and layers need the shared application to exist first.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let atlas = try Atlas()
        let view = PetView(atlas: atlas)
        let size = CGSize(width: max(PetView.bubbleWidth, view.petSize.width),
                          height: view.petSize.height + PetView.bubbleHeight + 4)
        view.frame = NSRect(origin: .zero, size: size)

        // An offscreen window gives the view a backing scale and lets the
        // animation clock settle on a real sprite frame.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)

        view.apply(resting: state, oneShot: nil, label: label, session: session)
        // Long enough for the animation clock to land on a real sprite frame.
        // Raise it with MIKKEL_PET_SNAPSHOT_SETTLE to catch a later moment,
        // such as the elapsed clock, which only appears once a job drags on.
        let settle = ProcessInfo.processInfo.environment["MIKKEL_PET_SNAPSHOT_SETTLE"]
            .flatMap(Double.init) ?? 0.5
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        view.layoutSubtreeIfNeeded()

        let pixelScale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * pixelScale),
            pixelsHigh: Int(size.height * pixelScale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw Failure("could not allocate the bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: pixelScale, y: pixelScale)
        // A dark ground by default: the balloon is drawn for a desktop, and on
        // white paper its own dark fill would be impossible to judge. The
        // README art wants no ground at all, so it can sit on any page.
        let environment = ProcessInfo.processInfo.environment
        if environment["MIKKEL_PET_SNAPSHOT_BG"] != "none" {
            NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        view.layer?.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        let cropped = environment["MIKKEL_PET_SNAPSHOT_CROP"] == "1"
            ? crop(rep, scale: pixelScale) : rep
        guard let data = cropped.representation(using: .png, properties: [:]) else {
            throw Failure("could not encode the PNG")
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
