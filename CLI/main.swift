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

/// Parses `--key value` pairs from the arguments after `command`.
func flags(from args: [String]) -> [String: String] {
    var result: [String: String] = [:]
    var index = 1
    while index < args.count {
        let token = args[index]
        if token.hasPrefix("--") {
            let key = String(token.dropFirst(2))
            if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
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
        if !args[index].hasPrefix("--") {
            result.append(args[index])
            index += 1
        } else {
            index += (index + 1 < args.count && !args[index + 1].hasPrefix("--")) ? 2 : 1
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
    print("\n--- prompt index ---")
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
      rate <path> ...                 run the MLX agent over reference images
    """
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

#if canImport(Agent)
/// Runs the real agent over each image and prints `name<TAB>label<TAB>id<TAB>seconds`.
func runRate() async throws {
    let paths = positional(from: arguments)
    guard !paths.isEmpty else {
        FileHandle.standardError.write(Data("rate: provide one or more image paths\n".utf8))
        exit(2)
    }
    let engine = AgentEngine()
    var rated = 0
    for path in paths {
        let url = URL(fileURLWithPath: path)
        let start = Date()
        var label = "?"
        var id = "?"
        var failure: String?
        do {
            for try await event in engine.run(AgentInput(text: "", imageURL: url)) {
                switch event {
                case .rating(let rating): label = rating.label.rawValue
                case .choice(let choice): id = choice.id
                case .failed(let message): failure = message
                case .text, .finished: break
                }
            }
        } catch {
            failure = error.localizedDescription
        }
        let seconds = String(format: "%.2f", Date().timeIntervalSince(start))
        if let failure {
            print("\(url.lastPathComponent)\tFAILED\t\(failure)\t\(seconds)s")
        } else {
            rated += 1
            print("\(url.lastPathComponent)\t\(label)\t\(id)\t\(seconds)s")
        }
    }
    print("\n\(rated)/\(paths.count) rated")
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
