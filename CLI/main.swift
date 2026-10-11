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
/// the end of the arguments would swallow the following path.
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
        a directory contributes its top-level images
        options: --model <dir> [--quiet] [--show-prompt] [--show]
        --show opens each chosen automaton in a Metal window and waits for close
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

/// Presents one automaton in a window using `Core/Render`'s on-screen path: a
/// `RenderActor` owns a `LayerSink` over `MetalHostView.metalLayer` and drives
/// its `DisplayLinkClock` with `.timed` pacing. `present` suspends until the
/// user closes the window, so a caller can step through a batch one at a time;
/// `NSApplication.run()` keeps delivering the close event while it is suspended.
@MainActor
final class AutomatonWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var host: MetalHostView?
    private var closeContinuation: CheckedContinuation<Void, Never>?

    func present(_ spec: ProgramSpec) async {
        guard GPUContext.isAvailable else {
            print("--show: no Metal 4 device; skipped \(spec.id)")
            return
        }
        let cols = min(spec.board.width, 1000)
        let rows = min(spec.board.height, 700)
        // A `.rand` entry draws a fresh row each time it is shown, matching the
        // app (inventory §1.4); `makeProgram()` stays deterministic for the
        // golden hashes.
        let runSpec = spec.withRandomSeed(UInt64.random(in: .min ... .max))
        let content = NSRect(x: 0, y: 0, width: CGFloat(cols), height: CGFloat(rows))
        let host = MetalHostView(frame: content)
        host.metalLayer.pixelFormat = .bgra8Unorm
        host.metalLayer.framebufferOnly = true
        // One drawable pixel per display cell; the layer scales it to the view.
        host.metalLayer.drawableSize = CGSize(width: cols, height: rows)

        let window = NSWindow(
            contentRect: content,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(spec.id) — \(spec.title)"
        window.contentView = host
        window.delegate = self
        // This type holds the window; let ARC release it, not AppKit.
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        self.host = host

        let actor = RenderActor()
        var sink: LayerSink?
        do {
            try await actor.start()
            let made = try await actor.makeLayerSink(layer: host.metalLayer)
            sink = made
            _ = try await actor.configure(spec: runSpec, cols: cols, rows: rows, sink: made)
            await actor.drive(
                clock: made.clock,
                pacing: .timed(stepsPerSecond: runSpec.display.stepsPerSecond)
            )
        } catch {
            print("--show: \(spec.id) failed to render: \(error.localizedDescription)")
            await actor.shutdown()
            self.window = nil
            self.host = nil
            return
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.closeContinuation = continuation
        }

        if let sink { await actor.stopDriving(clock: sink.clock) }
        await actor.shutdown()
        self.window = nil
        self.host = nil
    }

    func windowWillClose(_ notification: Notification) {
        closeContinuation?.resume()
        closeContinuation = nil
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

/// Parsed `rate` inputs shared by the headless and windowed modes.
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

/// One image's agent result, shared by the headless and windowed modes.
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

/// Headless batch: one line per image and a summary, no window.
func runRate(_ setup: RateSetup) async {
    printRateDebugHeader(setup)
    let engine = AgentEngine(configuration: setup.configuration)
    // The session folder is removed when the run ends.
    let sessionID = UUID()
    let directory = ImageImport.sessionDirectory(for: sessionID)
    defer { ImageImport.removeSessionDirectory(for: sessionID) }
    var chosen = 0
    for path in setup.paths {
        let outcome = await rateOne(engine: engine, path: path, directory: directory, verbose: setup.verbose)
        if printRateOutcome(outcome) != nil { chosen += 1 }
    }
    print("\n\(chosen)/\(setup.paths.count) chosen")
}

/// Windowed batch: opens each chosen automaton in an `AutomatonWindow` (the
/// render core's Metal on-screen path) and waits for the window to close before
/// the next image. The review loop is a main-actor task started before
/// `NSApplication.run()`, so `present` can suspend and the window's close event
/// still arrives.
@MainActor
func runRateWindowed(_ setup: RateSetup) async {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    Task { @MainActor in
        let presenter = AutomatonWindow()
        printRateDebugHeader(setup)
        let engine = AgentEngine(configuration: setup.configuration)
        let sessionID = UUID()
        let directory = ImageImport.sessionDirectory(for: sessionID)
        var chosen = 0
        for path in setup.paths {
            let outcome = await rateOne(engine: engine, path: path, directory: directory, verbose: setup.verbose)
            if let spec = printRateOutcome(outcome) {
                chosen += 1
                await presenter.present(spec)
            }
        }
        ImageImport.removeSessionDirectory(for: sessionID)
        print("\n\(chosen)/\(setup.paths.count) chosen")
        app.terminate(nil)
    }
    app.run()
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
    let setup = rateSetup()
    if flags(from: arguments)["show"] != nil {
        await runRateWindowed(setup)
    } else {
        await runRate(setup)
    }
default:
    printUsage()
}
