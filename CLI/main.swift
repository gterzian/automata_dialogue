import AppKit
import Agent
import Core
import CoreGraphics
import Foundation
import ImageIO
import Metal
import QuartzCore

// rater-cli — see CLI/README.md.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "catalog"

// MARK: - Flag parsing

/// Flag names that never take a value; every other `--name` consumes the next
/// token when that token is not itself a flag. Without this, a boolean flag at
/// the end of the arguments would swallow the following path. `show` is
/// accepted for compatibility; showing the automaton is the default now.
let booleanFlags: Set<String> = ["all", "quiet", "show", "show-prompt"]

/// Parses `--key value` pairs from the arguments after `command`.
func flags(from args: [String]) -> [String: String] {
    var result: [String: String] = [:]
    var index = 1
    while index < args.count {
        let token = args[index]
        if token.hasPrefix("--") {
            let key = String(token.dropFirst(2))
            if !booleanFlags.contains(key), index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                result[key] = args[index + 1]
                index += 2
                continue
            }
            result[key] = "true"
        }
        index += 1
    }
    return result
}

func positional(from args: [String]) -> [String] {
    var result: [String] = []
    var index = 1
    while index < args.count {
        let token = args[index]
        if !token.hasPrefix("--") {
            result.append(token)
            index += 1
        } else {
            let key = String(token.dropFirst(2))
            if !booleanFlags.contains(key), index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                index += 2
            } else {
                index += 1
            }
        }
    }
    return result
}

// MARK: - Commands

func printCatalog() {
    print("Automata Rater catalog — \(Catalog.all.count) entries")
    for behavior in Behavior.allCases {
        print("\n[\(behavior.rawValue)] \(Catalog.count(of: behavior))")
        for spec in Catalog.all where spec.behavior == behavior {
            print("  \(spec.id)  \(spec.title)")
        }
    }
    print("\n--- index ---")
    for line in Catalog.promptIndexLines { print(line) }
}

func printHashes() {
    for spec in Catalog.all {
        let steps = max(32, min(spec.board.height, spec.display.stepLimit))
        print("\(spec.id) steps=\(steps) hash=\(RowHash.hash(of: spec, steps: steps))")
    }
}

func printCells(_ id: String, steps: Int) {
    guard let spec = Catalog.spec(id: id) else {
        FileHandle.standardError.write(Data("unknown id \(id)\n".utf8))
        exit(1)
    }
    var program = spec.makeProgram()
    for _ in 0..<steps { program.step() }
    let row = program.row()
    let nonZero = row.enumerated().filter { $0.element != 0 }.map { "\($0.offset):\($0.element)" }
    print("\(id) steps=\(steps) width=\(row.count) hash=\(RowHash.fnv1a(row)) nonZero={\(nonZero.prefix(40).joined(separator: " "))}")
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw ImageImportError.encodeFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ImageImportError.encodeFailed
    }
}

func renderOne(_ spec: ProgramSpec, flags: [String: String], directory: URL? = nil, path: String? = nil) throws -> URL {
    let cols = Int(flags["cols"] ?? "") ?? min(spec.board.width, 1200)
    let rows = Int(flags["rows"] ?? "") ?? min(spec.board.height, 900)
    let steps = Int(flags["steps"] ?? "")
    let renderer = CPUAutomatonRenderer()
    guard let image = renderer.image(spec: spec, cols: cols, rows: rows, steps: steps) else {
        throw ImageImportError.encodeFailed
    }
    let output: URL
    if let path {
        output = URL(fileURLWithPath: path)
    } else if let directory {
        output = directory.appendingPathComponent("\(spec.id).png")
    } else {
        output = URL(fileURLWithPath: "\(spec.id).png")
    }
    try writePNG(image, to: output)
    print("\(spec.id) -> \(output.path) [\(cols)×\(rows)]")
    return output
}

func runRender() throws {
    let flags = flags(from: arguments)
    let positional = positional(from: arguments)
    if flags["all"] != nil {
        let outputDirectory = URL(fileURLWithPath: flags["out"] ?? "renders")
        for spec in Catalog.all {
            _ = try renderOne(spec, flags: flags, directory: outputDirectory)
        }
        return
    }

    guard let id = positional.first, let spec = Catalog.spec(id: id) else {
        FileHandle.standardError.write(Data("render: provide a catalog id or --all\n".utf8))
        exit(2)
    }
    _ = try renderOne(spec, flags: flags, path: flags["out"])
}

@available(macOS 26.0, *)
func gpuDebug() throws {
    let flags = flags(from: arguments)
    let positional = positional(from: arguments)
    guard let id = positional.first, let spec = Catalog.spec(id: id) else { printUsage() }
    let cols = Int(flags["cols"] ?? "") ?? 32
    let rows = Int(flags["rows"] ?? "") ?? 4
    let steps = Int(flags["steps"] ?? "") ?? rows
    guard GPUContext.isAvailable else {
        print("no Metal 4 device")
        return
    }
    let context = try GPUContext()
    let gpu = try MetalAutomaton.colorGrid(spec: spec, cols: cols, rows: rows, steps: steps, context: context)
    let cpu = CPUAutomatonRenderer().grid(spec: spec, cols: cols, rows: rows, steps: steps)
    print("\(id) cols=\(cols) rows=\(rows) steps=\(steps)")
    for row in 0..<rows {
        let g = (0..<cols).map { gpu[$0, row] }
        let c = (0..<cols).map { cpu[$0, row] }
        let match = g == c ? "ok" : "DIFF"
        print("row \(row) [\(match)] gpu nonZero=\(g.filter { $0 != 0 }.count) cpu nonZero=\(c.filter { $0 != 0 }.count)")
    }
    if gpu != cpu, let first = gpu.cells.indices.first(where: { gpu.cells[$0] != cpu.cells[$0] }) {
        print("first mismatch at index \(first) gpu=\(gpu.cells[first]) cpu=\(cpu.cells[first])")
    } else {
        print("GPU matches CPU")
    }
}

func printUsage() -> Never {
    let usage = """
    usage: rater-cli <command> [options]

      catalog                         print the catalog and prompt index
      hashes                          print CPU golden row hashes
      cells <id> <steps>              print one row's non-zero cells
      render <id> [--out p.png]       render one entry to PNG
      render --all [--out dir]        render every entry to PNG
        options: --cols N --rows N --steps N
      gpu <id>                        compare the Metal 4 kernels with the CPU
        options: --cols N --rows N --steps N
      rate <path|dir> ...               run the MLX agent over reference images
        a directory contributes its top-level images; the batch cycles
        options: --model <dir> [--quiet] [--show-prompt]
        Enter shows each image, submits it on the next Enter, then scrolls the
        chosen automaton until Enter advances to the next image. Closing the
        window stops the run.
        (--model default: RATER_MODEL_PATH; downloads are disabled)
    """
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

// MARK: - Metal window

/// A view backed by a `CAMetalLayer`, so an `AutomatonWindow` can present the
/// render core's on-screen path into it. AppKit calls `makeBackingLayer` when
/// the view first wants a layer.
final class MetalHostView: NSView {
    // Read by the render actor through `makeLayerSink(layer:)`; see the
    // `CAMetalLayer` Sendable note in `Core/Render/LayerSink.swift`.
    nonisolated let metalLayer = CAMetalLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MetalHostView is created in code") }

    override func makeBackingLayer() -> CALayer { metalLayer }
}

/// Presents one image, then one automaton, in a single screen-sized window
/// using `Core/Render`'s on-screen path: a `RenderActor` owns a `LayerSink`
/// over `MetalHostView.metalLayer` and drives its `DisplayLinkClock` with
/// `.timed` pacing. `showInput` returns immediately so the image stays visible
/// while the model runs; `present` swaps the scrolling automaton into the same
/// window and suspends until Return or close. The app's key monitor calls
/// `submit()`; `NSApplication.run()` keeps delivering events while suspended.
@MainActor
final class AutomatonWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var host: MetalHostView?
    private var actor: RenderActor?
    private var sink: LayerSink?
    private var enterContinuation: CheckedContinuation<Void, Never>?
    private(set) var isClosed = false

    /// Shows `image` at the screen's size and returns; the caller runs the model
    /// next, and `present` reuses the window for the automaton.
    func showInput(_ image: NSImage, title: String) {
        let window = ensureWindow()
        let view = NSImageView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = view
        window.title = title
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Swaps the scrolling automaton for `spec` into the window and suspends
    /// until Return or the window closes.
    func present(_ spec: ProgramSpec) async {
        guard !isClosed else { return }
        guard GPUContext.isAvailable else {
            print("rate: no Metal 4 device; skipped \(spec.id)")
            return
        }
        let window = ensureWindow()
        let scale = window.backingScaleFactor
        let contentSize = window.contentLayoutRect.size
        let (cols, rows) = displayGrid(contentSize: contentSize, scale: scale)
        let host = MetalHostView(frame: NSRect(origin: .zero, size: contentSize))
        host.metalLayer.pixelFormat = .bgra8Unorm
        host.metalLayer.framebufferOnly = true
        host.metalLayer.contentsScale = scale
        // One drawable pixel per display cell; the layer scales it to the view.
        host.metalLayer.drawableSize = CGSize(width: cols, height: rows)

        // A `.rand` entry draws a fresh row each time it is shown, matching the
        // app (inventory §1.4); `makeProgram()` stays deterministic for the
        // golden hashes.
        let runSpec = spec.withRandomSeed(UInt64.random(in: .min ... .max))
        let actor = RenderActor()
        var made: LayerSink?
        do {
            try await actor.start()
            let sink = try await actor.makeLayerSink(layer: host.metalLayer)
            made = sink
            _ = try await actor.configure(spec: runSpec, cols: cols, rows: rows, scrolling: true, sink: sink)
            await actor.drive(clock: sink.clock, pacing: .timed(stepsPerSecond: scrollSpeed(for: spec)))
        } catch {
            print("rate: \(spec.id) failed to render: \(error.localizedDescription)")
            await actor.shutdown()
            return
        }

        window.contentView = host
        window.title = "\(spec.id) — \(spec.title)"
        self.actor = actor
        self.sink = made
        self.host = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        await waitForEnter()
        await stopRun()
    }

    /// Stops the running automaton, if any.
    func stopRun() async {
        if let actor, let sink { await actor.stopDriving(clock: sink.clock) }
        await actor?.shutdown()
        actor = nil
        sink = nil
        host = nil
    }

    /// Resumes a `waitForEnter`; the key monitor calls this on Return. A Return
    /// outside a wait (while the model runs, say) is ignored.
    func submit() {
        guard !isClosed else { return }
        enterContinuation?.resume()
        enterContinuation = nil
    }

    /// Suspends until Return or close.
    func waitForEnter() async {
        if isClosed { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.enterContinuation = continuation
        }
    }

    /// The drawable's pixel size, capped so a wide board on a large panel does
    /// not allocate a span buffer for every pixel.
    private func displayGrid(contentSize: CGSize, scale: CGFloat) -> (Int, Int) {
        let pixelWidth = max(1, Int(contentSize.width * scale))
        let pixelHeight = max(1, Int(contentSize.height * scale))
        let maxPixels = 4_000_000
        var cols = pixelWidth
        var rows = pixelHeight
        if cols * rows > maxPixels {
            let factor = (Double(maxPixels) / Double(cols * rows)).squareRoot()
            cols = max(1, Int(Double(cols) * factor))
            rows = max(1, Int(Double(rows) * factor))
        }
        return (cols, rows)
    }

    /// Rows per second of scroll. The catalog tunes `stepsPerSecond` for a
    /// stretched three-second run, which is too fast for a full-screen scroll;
    /// cap it so the downward motion stays readable.
    private func scrollSpeed(for spec: ProgramSpec) -> Double {
        min(spec.display.stepsPerSecond, 120)
    }

    /// Opens the screen-sized window, or returns the open one.
    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Automata Rater"
        window.delegate = self
        // This type holds the window; let ARC release it, not AppKit.
        window.isReleasedWhenClosed = false
        window.setFrame(frame, display: true)
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        enterContinuation?.resume()
        enterContinuation = nil
    }
}

/// The image files a set of CLI arguments names. A file is taken as-is; a
/// directory contributes its top-level image files, sorted naturally, so
/// `rate artifacts/` rates every drawing in the folder.
func imagePaths(from inputs: [String]) -> [String] {
    let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp",
    ]
    var paths: [String] = []
    for input in inputs {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory) else {
            FileHandle.standardError.write(Data("rate: no such file or directory: \(input)\n".utf8))
            exit(2)
        }
        guard isDirectory.boolValue else {
            paths.append(input)
            continue
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: input)) ?? []
        let images = names
            .filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if images.isEmpty {
            FileHandle.standardError.write(Data("rate: no images in \(input)\n".utf8))
        }
        paths.append(contentsOf: images.map { (input as NSString).appendingPathComponent($0) })
    }
    return paths
}

/// Parsed `rate` inputs: the images, the model, and the debug flags.
struct RateSetup: Sendable {
    let paths: [String]
    let configuration: AgentEngine.Configuration
    let verbose: Bool
    let showPrompt: Bool
}

/// Validates the `rate` arguments and resolves the model. Exits with usage on
/// bad input, like the other commands.
func rateSetup() -> RateSetup {
    let inputs = positional(from: arguments)
    guard !inputs.isEmpty else {
        FileHandle.standardError.write(Data("rate: provide one or more image paths or directories\n".utf8))
        exit(2)
    }
    let paths = imagePaths(from: inputs)
    guard !paths.isEmpty else {
        FileHandle.standardError.write(Data("rate: no images found\n".utf8))
        exit(2)
    }
    let flags = flags(from: arguments)
    var configuration = AgentEngine.Configuration.fromEnvironment()
    if let model = flags["model"] {
        configuration.modelDirectory = URL(
            fileURLWithPath: NSString(string: model).expandingTildeInPath, isDirectory: true)
    }
    guard let directory = configuration.modelDirectory else {
        FileHandle.standardError.write(Data(
            "rate: no local model; pass --model <dir> or set RATER_MODEL_PATH (network downloads are disabled)\n".utf8))
        exit(2)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        FileHandle.standardError.write(Data("rate: model directory not found: \(directory.path)\n".utf8))
        exit(2)
    }
    return RateSetup(
        paths: paths,
        configuration: configuration,
        verbose: flags["quiet"] == nil,
        showPrompt: flags["show-prompt"] != nil
    )
}

/// The resolved model and prompt size; `--show-prompt` adds the full prompt.
/// Debug output is on unless `--quiet`.
func printRateDebugHeader(_ setup: RateSetup) {
    guard setup.verbose else { return }
    if let directory = setup.configuration.modelDirectory {
        print("[debug] model: directory \(directory.path)")
    } else {
        print("[debug] model: none configured (downloads are disabled)")
    }
    let prompt = SystemPrompt.build()
    print("[debug] system prompt: \(prompt.count) chars, ~\(SystemPrompt.estimatedTokenCount(of: prompt)) tokens")
    if setup.showPrompt {
        print("[debug] --- system prompt ---")
        print(prompt)
        print("[debug] --- end system prompt ---")
    }
}

/// One image's agent result.
struct RateOutcome: Sendable {
    let name: String
    let seconds: String
    let choice: Choice?
    let failure: String?
}

/// Runs the agent over one image. The engine carries the recent-choice window
/// across the batch, so each image is asked to pick an unused automaton.
func rateOne(
    engine: AgentEngine,
    path: String,
    directory: URL,
    verbose: Bool
) async -> RateOutcome {
    let url = URL(fileURLWithPath: path)
    let start = Date()
    var response = ""
    var choice: Choice?
    var failure: String?
    do {
        // Normalize to the model's 512×512 input, as the app does, so an
        // oversized or malformed image never reaches the preprocessor's far
        // larger edge limits.
        let normalized = try ImageImport.normalize(url, into: directory)
        if verbose { print("[debug] \(url.lastPathComponent) -> \(normalized.path)") }
        for try await event in engine.run(AgentInput(text: "", imageURL: normalized)) {
            switch event {
            case .text(let text): response = text
            case .choice(let picked): choice = picked
            case .failed(let message): failure = message
            case .finished: break
            }
        }
    } catch {
        failure = error.localizedDescription
    }
    let seconds = String(format: "%.2f", Date().timeIntervalSince(start))
    if verbose {
        print("[debug] \(url.lastPathComponent) answer after \(seconds)s:")
        print(response.isEmpty ? "[debug]   (empty response)" : response)
        if let choice, let spec = Catalog.spec(id: choice.id) {
            print("[debug]   parsed \(choice.id) [\(spec.behavior.rawValue)] \(spec.title)")
        }
    }
    return RateOutcome(name: url.lastPathComponent, seconds: seconds, choice: choice, failure: failure)
}

/// Prints the `name<TAB>id<TAB>seconds` result line and returns the chosen
/// spec, if any.
@discardableResult
func printRateOutcome(_ outcome: RateOutcome) -> ProgramSpec? {
    if let failure = outcome.failure {
        print("\(outcome.name)\tFAILED\t\(failure)\t\(outcome.seconds)s")
        return nil
    }
    guard let choice = outcome.choice else {
        print("\(outcome.name)\tFAILED\tno catalog id\t\(outcome.seconds)s")
        return nil
    }
    print("\(outcome.name)\t\(choice.id)\t\(outcome.seconds)s")
    return Catalog.spec(id: choice.id)
}

/// The review loop: cycle the images forever, running the agent after Return
/// and scrolling the automaton until the next Return. Closing the window stops
/// the loop.
@MainActor
func review(_ setup: RateSetup, presenter: AutomatonWindow) async {
    printRateDebugHeader(setup)
    let engine = AgentEngine(configuration: setup.configuration)
    let sessionID = UUID()
    let directory = ImageImport.sessionDirectory(for: sessionID)
    var chosen = 0
    var shown = 0
    while !presenter.isClosed {
        for path in setup.paths {
            if presenter.isClosed { break }
            let name = URL(fileURLWithPath: path).lastPathComponent
            if let image = NSImage(contentsOfFile: path) {
                presenter.showInput(image, title: name)
            }
            await presenter.waitForEnter()
            if presenter.isClosed { break }
            let outcome = await rateOne(engine: engine, path: path, directory: directory, verbose: setup.verbose)
            shown += 1
            if let spec = printRateOutcome(outcome) {
                chosen += 1
                await presenter.present(spec)
            } else {
                await presenter.waitForEnter()
            }
        }
    }
    await presenter.stopRun()
    ImageImport.removeSessionDirectory(for: sessionID)
    print("\n\(chosen)/\(shown) chosen")
}

/// The windowed review: one screen-sized window, driven by Return. The review
/// loop is a main-actor task started before `NSApplication.run()`, so it can
/// suspend and still receive the key and close events.
@MainActor
func runRateWindowed(_ setup: RateSetup) async {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    installMainMenu(app)
    app.finishLaunching()

    let presenter = AutomatonWindow()
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 36 || event.keyCode == 76 {
            MainActor.assumeIsolated { presenter.submit() }
            return nil
        }
        return event
    }
    Task { @MainActor in
        await review(setup, presenter: presenter)
        if let monitor { NSEvent.removeMonitor(monitor) }
        app.terminate(nil)
    }
    app.run()
}

/// The app menu with Quit, so Cmd-Q works while the review window is up.
@MainActor
func installMainMenu(_ app: NSApplication) {
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(
        withTitle: "Quit Automata Rater",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu
    app.mainMenu = mainMenu
}

switch command {
case "catalog":
    printCatalog()
case "hashes":
    printHashes()
case "cells":
    guard arguments.count >= 3, let steps = Int(arguments[2]) else { printUsage() }
    printCells(arguments[1], steps: steps)
case "render":
    try runRender()
case "gpu":
    if #available(macOS 26.0, *) {
        try gpuDebug()
    } else {
        print("Metal 4 requires macOS 26")
    }
case "rate":
    await runRateWindowed(rateSetup())
default:
    printUsage()
}
