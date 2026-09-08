// Mikkel: a desktop pet that reacts to what Claude Code is doing.

import PetCore
import AppKit

// The hook wiring is available without launching the UI.
let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first {
    switch command {
    case "--install-hooks", "--uninstall-hooks":
        do {
            let message = command == "--install-hooks"
                ? try HookInstaller.install()
                : try HookInstaller.uninstall()
            print(message)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    case "--help", "-h":
        print("""
        mikkel-pet - a Claude Code desktop pet

          mikkel-pet                    run the pet
          mikkel-pet --install-hooks    add the pet's hooks to ~/.claude/settings.json
          mikkel-pet --uninstall-hooks  remove them again
        """)
        exit(0)
    default:
        FileHandle.standardError.write(Data("Unknown option \(command). Try --help.\n".utf8))
        exit(1)
    }
}

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, PetViewDelegate {
    private var atlas: Atlas!
    private var window: PetWindow!
    private var petView: PetView!
    private var statusItem: NSStatusItem!
    private let server = EventServer()
    private let tracker = SessionTracker()
    private var pruneTimer: Timer?

    private let positionKey = "PetWindowOrigin"
    private let scaleKey = "PetScale"
    private let backgroundKey = "FollowBackgroundSessions"
    private let speedKey = "PetSpeed"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no main menu: the pet lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        do {
            atlas = try Atlas()
        } catch {
            presentFatal(error.localizedDescription)
            return
        }

        buildWindow()
        buildStatusItem()

        tracker.followsBackgroundSessions = UserDefaults.standard.bool(forKey: backgroundKey)
        tracker.onChange = { [weak self] resting, oneShot, label in
            if ProcessInfo.processInfo.environment["MIKKEL_PET_DEBUG"] == "1" {
                FileHandle.standardError.write(Data(
                    "state \(resting.rawValue) oneShot=\(oneShot?.rawValue ?? "-") label=\(label)\n".utf8))
            }
            self?.petView.apply(resting: resting, oneShot: oneShot, label: label)
            self?.refreshStatusTitle()
        }
        // MIKKEL_PET_DEBUG=1 traces the hook stream while wiring things up.
        let debug = ProcessInfo.processInfo.environment["MIKKEL_PET_DEBUG"] == "1"
        server.onEvent = { [weak self] event in
            if debug {
                FileHandle.standardError.write(Data(
                    "event \(event.event) tool=\(event.toolName ?? "-") session=\(event.sessionID?.prefix(8) ?? "-")\n".utf8))
            }
            self?.tracker.handle(event)
        }

        do {
            try server.start()
        } catch EventServer.ServerError.alreadyRunning {
            // A duplicate copy that kept running would be a pet that never
            // reacts, so quit rather than sit there looking broken.
            presentInfo("Mikkel is already running.")
            NSApp.terminate(nil)
            return
        } catch {
            presentWarning(error.localizedDescription)
        }

        // Sessions whose process died without a SessionEnd would otherwise pin
        // the pet to a stale state forever.
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tracker.refresh()
        }

        petView.apply(resting: .idle, oneShot: .waving, label: "")
    }

    // MARK: - Window

    private func buildWindow() {
        let scale = UserDefaults.standard.object(forKey: scaleKey) as? Double ?? 0.75
        let view = PetView(atlas: atlas)
        view.scale = CGFloat(scale)
        view.speed = UserDefaults.standard.object(forKey: speedKey) as? Double ?? 1.7
        view.delegate = self
        petView = view

        let size = windowSize(for: view)
        let window = PetWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        self.window = window

        restorePosition(size: size)
        window.orderFrontRegardless()
    }

    private func windowSize(for view: PetView) -> CGSize {
        CGSize(width: max(PetView.bubbleWidth, view.petSize.width),
               height: view.petSize.height + PetView.bubbleHeight + 4)
    }

    private func restorePosition(size: CGSize) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
        if let saved = UserDefaults.standard.string(forKey: positionKey) {
            let point = NSPointFromString(saved)
            // Only reuse a saved spot that is still on a connected display.
            if NSScreen.screens.contains(where: { $0.frame.contains(point) }) {
                origin = point
            }
        }
        window.setFrameOrigin(origin)
    }

    private func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: positionKey)
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let cell = atlas.neutralCell {
            let image = NSImage(cgImage: cell, size: NSSize(width: 20, height: 21))
            image.isTemplate = false
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageLeading
        }
        rebuildMenu()
    }

    private func refreshStatusTitle() {
        let count = tracker.activeSessionCount
        statusItem.button?.title = count > 1 ? " \(count)" : ""
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(header(atlas.manifest.displayName))

        if tracker.sessions.isEmpty {
            menu.addItem(header("No Claude Code sessions"))
        } else {
            menu.addItem(header("Follow"))
            let all = NSMenuItem(title: "All sessions", action: #selector(pinSession(_:)), keyEquivalent: "")
            all.target = self
            all.state = tracker.pinnedSessionID == nil ? .on : .off
            menu.addItem(all)

            // Newest first, so the session just used is easy to find.
            for (id, snapshot) in tracker.sessions.sorted(by: { $0.value.updatedAt > $1.value.updatedAt }) {
                let project = snapshot.projectName.isEmpty ? "session" : snapshot.projectName
                let item = NSMenuItem(
                    title: "\(project) - \(snapshot.state.rawValue)",
                    action: #selector(pinSession(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                item.state = tracker.pinnedSessionID == id ? .on : .off
                item.toolTip = snapshot.label
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let tracking = NSMenuItem(
            title: "Watch the pointer", action: #selector(toggleTracking), keyEquivalent: "")
        tracking.target = self
        tracking.state = petView.pointerTrackingEnabled ? .on : .off
        menu.addItem(tracking)

        let background = NSMenuItem(
            title: "Follow background sessions", action: #selector(toggleBackground), keyEquivalent: "")
        background.target = self
        background.state = tracker.followsBackgroundSessions ? .on : .off
        background.toolTip = "Headless claude -p runs, including sessions your own hooks start."
        menu.addItem(background)

        let sizes = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (label, value) in [("Small", 0.5), ("Medium", 0.75), ("Large", 1.0)] {
            let item = NSMenuItem(title: label, action: #selector(setScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(Double(petView.scale) - value) < 0.01 ? .on : .off
            sizeMenu.addItem(item)
        }
        sizes.submenu = sizeMenu
        menu.addItem(sizes)

        let speeds = NSMenuItem(title: "Pace", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        // Larger multipliers stretch every frame, so bigger is slower.
        for (label, value) in [("Calm", 2.6), ("Relaxed", 2.1), ("Steady", 1.7), ("Lively", 1.0)] {
            let item = NSMenuItem(title: label, action: #selector(setSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(petView.speed - value) < 0.01 ? .on : .off
            speedMenu.addItem(item)
        }
        speeds.submenu = speedMenu
        menu.addItem(speeds)

        menu.addItem(.separator())

        let hooks = NSMenuItem(
            title: HookInstaller.isInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks",
            action: #selector(toggleHooks), keyEquivalent: "")
        hooks.target = self
        menu.addItem(hooks)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    /// Pins the pet to one session, or back to all when the item carries no id.
    @objc private func pinSession(_ sender: NSMenuItem) {
        tracker.pinnedSessionID = sender.representedObject as? String
        rebuildMenu()
    }

    @objc private func setSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        petView.speed = value
        UserDefaults.standard.set(value, forKey: speedKey)
        rebuildMenu()
    }

    @objc private func toggleBackground() {
        tracker.followsBackgroundSessions.toggle()
        UserDefaults.standard.set(tracker.followsBackgroundSessions, forKey: backgroundKey)
        rebuildMenu()
    }

    @objc private func toggleTracking() {
        petView.pointerTrackingEnabled.toggle()
        rebuildMenu()
    }

    @objc private func setScale(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        petView.scale = CGFloat(value)
        UserDefaults.standard.set(value, forKey: scaleKey)
        let size = windowSize(for: petView)
        var frame = window.frame
        frame.size = size
        window.setFrame(frame, display: true)
        petView.frame = NSRect(origin: .zero, size: size)
        rebuildMenu()
    }

    @objc private func toggleHooks() {
        do {
            let message = HookInstaller.isInstalled
                ? try HookInstaller.uninstall()
                : try HookInstaller.install()
            presentInfo(message)
        } catch {
            presentWarning(error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func quit() {
        server.stop()
        savePosition()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
        savePosition()
    }

    // MARK: - PetViewDelegate

    func petViewWasClicked(_ view: PetView) {
        petView.apply(resting: .idle, oneShot: .waving, label: atlas.manifest.description)
        savePosition()
    }

    func petViewMenu(_ view: PetView) -> NSMenu {
        rebuildMenu()
        return statusItem.menu ?? NSMenu()
    }

    func petViewOneShotFinished(_ view: PetView, state: PetState) {
        // The tracker consumes one-shots when it publishes them, so the pet
        // simply falls back to its resting animation here.
    }

    // MARK: - Alerts

    private func presentInfo(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func presentWarning(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Mikkel"
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentFatal(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Mikkel could not start"
        alert.informativeText = text
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
