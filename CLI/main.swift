import AppKit
import Agent
import Core
import Foundation
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
let booleanFlags: Set<String> = ["quiet", "show", "show-prompt"]

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

func printUsage() -> Never {
    let usage = """
    usage: rater-cli <command> [options]

      catalog                         print the catalog and prompt index
      rate <path|dir> ...               run the MLX agent over reference images
        a directory contributes its top-level images; the batch cycles
        options: --model <dir> [--quiet] [--show-prompt] [--image-size <px>]
        Enter shows each image, submits it on the next Enter, then shows the
        chosen automaton's reveal until Enter advances to the next image.
        Closing the window stops the run.
        (--model default: RATER_MODEL_PATH; downloads are disabled)
      bench <path|dir> ...              time the agent on the images, headless
        options: --model <dir> [--quiet] [--show-prompt] [--image-size <px>]
        Runs each image once with no window or automaton and prints the prompt
        and generation cost, so a prompt or model change can be measured from
        a terminal script.
      classify <path|dir> ...           print each image's chosen class, headless
        options: --model <dir> [--quiet] [--show-prompt] [--image-size <px>]
        Runs each image once with no window and prints `name<TAB>class<TAB>id`
        plus a class tally, so a labeled reference set can be scored.
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

    /// The drawable's texture size. The layer stretches it over the view, so a
    /// small size (the automaton's cell grid) gives blocky cells and a full-res
    /// size (the collapse intro) stays smooth. AppKit sets `contentsScale`
    /// when the view enters the window, so the size is re-applied after layout
    /// instead of set once. The reveal's automaton drawable is fixed at the
    /// floor grid so a zoom never resizes it.
    private var targetDrawableSize: CGSize

    init(frame frameRect: NSRect, drawableSize: CGSize) {
        self.targetDrawableSize = drawableSize
        super.init(frame: frameRect)
        wantsLayer = true
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MetalHostView is created in code") }

    override func makeBackingLayer() -> CALayer { metalLayer }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyDrawableSize()
    }

    override func layout() {
        super.layout()
        applyDrawableSize()
    }

    private func applyDrawableSize() {
        if let scale = window?.backingScaleFactor { metalLayer.contentsScale = scale }
        metalLayer.drawableSize = targetDrawableSize
    }
}

/// Presents one image, the collapse intro, then one automaton, in a single
/// screen-sized window using `Core/Render`'s on-screen path: a `RenderActor`
/// owns a `LayerSink`, or an `IndicatorActor` a `WorkingIndicator`, over a
/// `MetalHostView.metalLayer`. `showInput` holds the image until Return;
/// `showThinking` runs the collapse intro while the model works;
/// `present` swaps the reveal's two mirrored automaton branches into the same
/// window and suspends until Return or close. The key monitor calls `submit()`;
/// `NSApplication.run()` keeps delivering events while suspended.
@MainActor
final class AutomatonWindow: NSObject, NSWindowDelegate {
    /// Source rows per second each branch grows. A branch fills half the
    /// window, so twice the single-run rate keeps the window-relative growth
    /// speed the same; this is the knob for how long the pull-back takes.
    private static let revealRowsPerSecond = 40.0

    private var zoomFloor = 1.0
    private var window: NSWindow?
    private var host: MetalHostView?
    private var actor: RenderActor?
    private var sink: LayerSink?
    private var indicator: IndicatorActor?
    private var indicatorHost: MetalHostView?
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

    /// Swaps the reveal for `spec` into the window and suspends until Return or
    /// the window closes.
    func present(_ spec: ProgramSpec) async {
        guard !isClosed else { return }
        guard GPUContext.isAvailable else {
            print("rate: no Metal 4 device; skipped \(spec.id)")
            return
        }
        await collapseIntro(onto: spec)
        await stopThinking()
        let window = ensureWindow()
        let contentSize = window.contentLayoutRect.size
        // The drawable holds one texel per display cell; the layer stretches that
        // small grid over the whole window. The run simulates a board much wider
        // than the window so a drifting pattern keeps going after it leaves the
        // first view.
        let cols = ViewportGeometry.columns(size: contentSize)
        // Both branches share one horizon row, so the twin grid needs an odd
        // row count.
        let rows = ViewportGeometry.twinRows(
            baseRows: ViewportGeometry.rows(size: contentSize, cols: cols), zoom: 1)
        // One display cell per element of the surface; a Retina display reports
        // its pixels and an LED surface its addressable elements.
        zoomFloor = ViewportGeometry.zoomFloor(
            baseCols: cols,
            baseRows: rows,
            limits: .pixels(points: contentSize.width, scale: window.backingScaleFactor))
        // The drawable is allocated once at the widest zoom-out: the camera
        // only changes the grid, and the layer stretches that grid over this
        // fixed target. At the floor each cell is one drawable pixel; earlier
        // the grid is smaller and each cell covers more than one.
        let floorCols = ViewportGeometry.zoomedColumns(baseCols: cols, zoom: zoomFloor)
        let floorRows = ViewportGeometry.twinRows(baseRows: rows, zoom: zoomFloor)
        let host = MetalHostView(
            frame: NSRect(origin: .zero, size: contentSize),
            drawableSize: CGSize(width: floorCols, height: floorRows))
        host.metalLayer.magnificationFilter = .nearest

        // A `.rand` entry draws a fresh row each time it is shown
        // (inventory §1.4).
        let runSpec = spec.withRandomSeed(UInt64.random(in: .min ... .max))
        let board = Board(
            width: ViewportGeometry.boardWidth(specWidth: runSpec.board.width, cols: cols),
            height: runSpec.board.height,
            start: runSpec.board.start,
            injection: runSpec.board.injection)
        let actor = RenderActor()
        var made: LayerSink?
        do {
            try await actor.start()
            let sink = try await actor.makeLayerSink(layer: host.metalLayer)
            made = sink
            _ = try await actor.configure(
                spec: runSpec, cols: cols, rows: rows, board: board,
                layout: .twin,
                minimumZoom: zoomFloor,
                reveal: RevealSetup(
                    branchRows: ViewportGeometry.twinHalfRows(rows: rows),
                    floor: zoomFloor),
                sink: sink)
            await actor.drive(
                clock: sink.clock,
                pacing: .timed(stepsPerSecond: Self.revealRowsPerSecond))
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

    /// Shows the collapse intro in the window while the model's turn is
    /// prepared. A one-cell dot ignites, bursts to cover the window, and
    /// collapses into the horizon line the reveal starts from. The intro settles
    /// and stops drawing before inference begins; `present` or `stopThinking`
    /// ends it.
    func showThinking() async {
        guard !isClosed, GPUContext.isAvailable else { return }
        let window = ensureWindow()
        let contentSize = window.contentLayoutRect.size
        let host = indicatorHost ?? MetalHostView(
            frame: NSRect(origin: .zero, size: contentSize),
            drawableSize: indicatorDrawableSize(
                contentSize: contentSize, scale: window.backingScaleFactor))
        host.metalLayer.magnificationFilter = .linear
        indicatorHost = host
        window.contentView = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        let actor = indicator ?? IndicatorActor()
        indicator = actor
        // The intro's ending line is measured in horizon-row heights, so it
        // thins to the same 3% hairline the reveal grows back from.
        let cols = ViewportGeometry.columns(size: contentSize)
        let rows = ViewportGeometry.twinRows(
            baseRows: ViewportGeometry.rows(size: contentSize, cols: cols), zoom: 1)
        let lineHalfThickness = 0.5 / Float(max(1, rows))
        do {
            try await actor.start(
                layer: host.metalLayer, lineHalfThickness: lineHalfThickness)
        } catch {
            indicator = nil
            print("rate: indicator failed: \(error.localizedDescription)")
        }
    }

    /// Waits for the intro to rest on the frame the reveal continues from, and
    /// for its clock to stop. The window stays responsive while it sleeps. The
    /// wait is bounded because the intro now gates inference: a display link
    /// that stopped delivering updates must not hold the turn up, and the
    /// caller stops the intro either way.
    func waitForThinkingToSettle() async {
        var waited: TimeInterval = 0
        while !isClosed, waited < ReviewIntro.duration + ReviewIntro.finaleDuration + 2 {
            guard let indicator else { return }
            if await indicator.isSettled { return }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            waited += 0.05
        }
    }

    /// One last beat of the intro before the reveal replaces it: an entry that
    /// seeds from a single centred cell retracts the settled horizon line onto
    /// that cell, so the automaton appears to start from the intro's last image.
    /// Every other entry keeps the line, which is its first row.
    private func collapseIntro(onto spec: ProgramSpec) async {
        guard spec.board.start.startsFromSingleCentreCell else { return }
        // The seed row's one cell holds palette index 1, so the dot the line
        // retracts into is drawn in that cell's colour.
        await indicator?.collapseOntoSeedCell(seedInk: spec.display.palette[1])
        await waitForThinkingToSettle()
    }

    /// Pauses the "working" indicator; the actor is kept for the next run.
    func stopThinking() async {
        await indicator?.stop()
    }

    /// Stops the running automaton, if any. The indicator actor and its GPU
    /// context stay alive for the next run.
    func stopRun() async {
        if let actor, let sink { await actor.stopDriving(clock: sink.clock) }
        await actor?.shutdown()
        actor = nil
        sink = nil
        host = nil
        await stopThinking()
    }

    /// Tears down the indicator's render thread; call once the review ends.
    func shutdownIndicator() async {
        await indicator?.shutdown()
        indicator = nil
        indicatorHost = nil
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

    /// The indicator's drawable: full device pixels so the sphere and the
    /// ending line stay smooth, capped so a large display does not run the
    /// fragment shader over tens of millions of pixels.
    private func indicatorDrawableSize(contentSize: CGSize, scale: CGFloat) -> CGSize {
        let pixelWidth = max(1, Int(contentSize.width * scale))
        let pixelHeight = max(1, Int(contentSize.height * scale))
        let maxPixels = 4_000_000
        var width = pixelWidth
        var height = pixelHeight
        if width * height > maxPixels {
            let factor = (Double(maxPixels) / Double(width * height)).squareRoot()
            width = max(1, Int(Double(width) * factor))
            height = max(1, Int(Double(height) * factor))
        }
        return CGSize(width: width, height: height)
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
    if let raw = flags["image-size"] {
        guard let size = Int(raw), size > 0 else {
            FileHandle.standardError.write(
                Data("rate: --image-size must be a positive integer\n".utf8))
            exit(2)
        }
        configuration.imageDimension = size
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
    /// One entry per generation pass; a repair turn adds a second entry.
    let metrics: [GenerationMetrics]
}

/// Runs the agent over one image. The engine carries the recent-choice window
/// across the batch, so each image is asked to pick an unused automaton.
func rateOne(
    engine: AgentEngine,
    path: String,
    directory: URL,
    dimension: Int,
    verbose: Bool
) async -> RateOutcome {
    let url = URL(fileURLWithPath: path)
    let start = Date()
    var response = ""
    var choice: Choice?
    var failure: String?
    var metrics: [GenerationMetrics] = []
    do {
        // Normalize to the model's input size so an oversized or malformed
        // image never reaches the preprocessor's far larger edge limits.
        let normalized = try ImageImport.normalize(url, into: directory, dimension: dimension)
        if verbose { print("[debug] \(url.lastPathComponent) -> \(normalized.path)") }
        for try await event in engine.run(AgentInput(text: "", imageURL: normalized)) {
            switch event {
            case .text(let text): response = text
            case .metrics(let pass): metrics.append(pass)
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
        for (index, pass) in metrics.enumerated() {
            let turn = index == 0 ? "turn 1" : "turn \(index + 1) (repair)"
            let promptSeconds = String(format: "%.2f", pass.promptTime)
            let generateSeconds = String(format: "%.2f", pass.generationTime)
            print(
                "[debug] \(turn): prompt \(pass.promptTokenCount) tokens / \(promptSeconds)s, generation \(pass.generationTokenCount) tokens / \(generateSeconds)s")
        }
        print("[debug] \(url.lastPathComponent) answer after \(seconds)s:")
        print(response.isEmpty ? "[debug]   (empty response)" : response)
        if let choice, let spec = Catalog.spec(id: choice.id) {
            print("[debug]   parsed \(choice.id) [\(spec.behavior.rawValue)] \(spec.title)")
        }
    }
    return RateOutcome(
        name: url.lastPathComponent, seconds: seconds, choice: choice, failure: failure,
        metrics: metrics)
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
/// and showing the automaton's reveal until the next Return. Closing the window
/// stops the loop.
@MainActor
func review(_ setup: RateSetup, presenter: AutomatonWindow) async {
    printRateDebugHeader(setup)
    let engine = AgentEngine(configuration: setup.configuration)
    // Load the weights while the first image is on screen. The first run then
    // pays only prefill and generation, not the snapshot load. A failure is
    // logged but not fatal: the run retries and reports it again.
    Task {
        do {
            try await engine.prepare()
        } catch {
            FileHandle.standardError.write(
                Data("rate: model preload failed: \(error.localizedDescription)\n".utf8))
        }
    }
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
            await presenter.showThinking()
            // The intro rests before the turn is prepared, so nothing is drawing
            // while the model works (see `AGENTS.md`); the line stays up until
            // the choice lands.
            await presenter.waitForThinkingToSettle()
            await presenter.stopThinking()
            let outcome = await rateOne(
                engine: engine, path: path, directory: directory,
                dimension: setup.configuration.imageDimension, verbose: setup.verbose)
            shown += 1
            if let spec = printRateOutcome(outcome) {
                chosen += 1
                await presenter.present(spec)
            } else {
                // Put the failed image back up so it is still reviewable.
                if let image = NSImage(contentsOfFile: path) {
                    presenter.showInput(image, title: name)
                }
                await presenter.waitForEnter()
            }
        }
    }
    await presenter.stopRun()
    await presenter.shutdownIndicator()
    ImageImport.removeSessionDirectory(for: sessionID)
    print("\n\(chosen)/\(shown) chosen")
}

/// Headless inference timing: run the agent once per image with no window and
/// no automaton, then print the prompt and generation cost plus a total.
/// `rate` is the product flow; this is the measurement path for a prompt or
/// model change, where the interactive Returns of `rate` would block a script.
func runBench(_ setup: RateSetup) async {
    printRateDebugHeader(setup)
    let engine = AgentEngine(configuration: setup.configuration)
    let sessionID = UUID()
    let directory = ImageImport.sessionDirectory(for: sessionID)
    var chosen = 0
    var repairs = 0
    var promptTokens = 0
    var promptSeconds = 0.0
    var generationTokens = 0
    var generationSeconds = 0.0
    for path in setup.paths {
        let outcome = await rateOne(
            engine: engine, path: path, directory: directory,
            dimension: setup.configuration.imageDimension, verbose: setup.verbose)
        if printRateOutcome(outcome) != nil { chosen += 1 }
        for (index, pass) in outcome.metrics.enumerated() {
            promptTokens += pass.promptTokenCount
            promptSeconds += pass.promptTime
            generationTokens += pass.generationTokenCount
            generationSeconds += pass.generationTime
            if index > 0 { repairs += 1 }
        }
    }
    ImageImport.removeSessionDirectory(for: sessionID)
    print("\n\(chosen)/\(setup.paths.count) chosen, \(repairs) repair turn(s)")
    print(String(
        format: "prompt: %d tokens / %.2fs (%.1f tok/s)",
        promptTokens, promptSeconds, Double(promptTokens) / max(promptSeconds, 0.001)))
    print(String(
        format: "generation: %d tokens / %.2fs (%.1f tok/s)",
        generationTokens, generationSeconds,
        Double(generationTokens) / max(generationSeconds, 0.001)))
}

/// Headless classification: run the agent once per image with no window and
/// print the chosen behavior class, so a labeled reference set can be scored.
/// Each image is classified independently (the choice history is cleared), so
/// the score measures the model, not the order of the batch; `bench` is the
/// same path with timing and the product's no-repeat window.
func runClassify(_ setup: RateSetup) async {
    printRateDebugHeader(setup)
    let engine = AgentEngine(configuration: setup.configuration)
    let sessionID = UUID()
    let directory = ImageImport.sessionDirectory(for: sessionID)
    var classified = 0
    var tally: [Behavior: Int] = [:]
    for path in setup.paths {
        await engine.resetHistory()
        let outcome = await rateOne(
            engine: engine, path: path, directory: directory,
            dimension: setup.configuration.imageDimension, verbose: false)
        guard let choice = outcome.choice, let spec = Catalog.spec(id: choice.id) else {
            print("\(outcome.name)\tFAILED\t\(outcome.failure ?? "no catalog id")")
            continue
        }
        classified += 1
        tally[spec.behavior, default: 0] += 1
        print("\(outcome.name)\t\(spec.behavior.rawValue)\t\(choice.id)")
    }
    ImageImport.removeSessionDirectory(for: sessionID)
    let summary = Behavior.allCases
        .map { "\($0.rawValue) \(tally[$0, default: 0])" }
        .joined(separator: ", ")
    print("\n\(classified)/\(setup.paths.count) classified: \(summary)")
}

/// The windowed review: one screen-sized window, driven by Return. The review
/// loop is a main-actor task started before `NSApplication.run()`, so it can
/// suspend and still receive the key and close events.
@MainActor
func runRateWindowed(_ setup: RateSetup) async {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let presenter = AutomatonWindow()
    installMainMenu(app)
    app.finishLaunching()
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

/// The app menu: Quit (Cmd-Q). The reveal runs on its own; the window has no
/// zoom or speed controls.
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
case "rate":
    await runRateWindowed(rateSetup())
case "bench":
    await runBench(rateSetup())
case "classify":
    await runClassify(rateSetup())
default:
    printUsage()
}
