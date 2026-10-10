import Core
import CoreGraphics
import Foundation
import ImageIO

#if canImport(Agent)
import Agent
#endif

// rater-cli — see CLI/README.md.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "catalog"

// MARK: - Flag parsing

/// Flag names that never take a value; every other `--name` consumes the next
/// token when that token is not itself a flag. Without this, a boolean flag at
/// the end of the arguments would swallow the following path.
let booleanFlags: Set<String> = ["all", "quiet", "show-prompt"]

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
        options: --model <dir> [--quiet] [--show-prompt]
        (--model default: RATER_MODEL_PATH, else download)
    """
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

#if canImport(Agent)
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

/// Runs the real agent over each image and prints `name<TAB>id<TAB>seconds`.
/// Debug output is on by default (the resolved model, the prompt size, the
/// model's raw answer, and the parsed class per image); `--quiet` keeps only
/// the summary lines. `--show-prompt` adds the full system prompt.
func runRate() async throws {
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
    let verbose = flags["quiet"] == nil
    var configuration = AgentEngine.Configuration.fromEnvironment()
    if let model = flags["model"] {
        configuration.modelDirectory = URL(
            fileURLWithPath: NSString(string: model).expandingTildeInPath, isDirectory: true)
    }
    if verbose {
        if let directory = configuration.modelDirectory {
            print("[debug] model: directory \(directory.path)")
        } else {
            print("[debug] model: hub \(configuration.modelID) @ \(configuration.revision)")
        }
        let prompt = SystemPrompt.build()
        print("[debug] system prompt: \(prompt.count) chars, ~\(SystemPrompt.estimatedTokenCount(of: prompt)) tokens")
        if flags["show-prompt"] != nil {
            print("[debug] --- system prompt ---")
            print(prompt)
            print("[debug] --- end system prompt ---")
        }
    }
    let engine = AgentEngine(configuration: configuration)
    // Normalize each input to the model's 512×512 size, as the app does, so an
    // oversized or malformed image never reaches the preprocessor's far larger
    // edge limits. The session folder is removed when the run ends.
    let sessionID = UUID()
    let directory = ImageImport.sessionDirectory(for: sessionID)
    defer { ImageImport.removeSessionDirectory(for: sessionID) }
    var chosen = 0
    for path in paths {
        let url = URL(fileURLWithPath: path)
        let start = Date()
        var response = ""
        var choice: Choice?
        var failure: String?
        do {
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
        if let failure {
            print("\(url.lastPathComponent)\tFAILED\t\(failure)\t\(seconds)s")
        } else if let choice {
            chosen += 1
            print("\(url.lastPathComponent)\t\(choice.id)\t\(seconds)s")
        } else {
            print("\(url.lastPathComponent)\tFAILED\tno catalog id\t\(seconds)s")
        }
    }
    print("\n\(chosen)/\(paths.count) chosen")
}
#endif

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
#if canImport(Agent)
    try await runRate()
#else
    FileHandle.standardError.write(Data(
        "rate: built without the Agent target; set RATER_AGENT=1 for SwiftPM or use the Xcode build\n".utf8
    ))
    exit(1)
#endif
default:
    printUsage()
}
