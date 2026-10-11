import AppKit
import Combine
import Core
import CoreGraphics
import Agent

/// App state for the single panel: the transcript, the current automaton
/// animation, and the agent run. A new prompt stops the running automaton
/// before the next run starts.
@MainActor
final class RaterModel: ObservableObject {
    @Published var inputText = ""
    @Published var attachment: ImageAttachment?
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    @Published private(set) var automatonImage: CGImage?
    @Published private(set) var currentSpec: ProgramSpec?
    @Published private(set) var latestChoice: Choice?
    @Published var attachmentError: String?

    private let store = TranscriptStore()
    /// The MLX agent. The app only builds through the Xcode project, which
    /// always includes the `Agent` target.
    private let agent: any AgentRunning = AgentEngine(configuration: RaterModel.agentConfiguration())
    private let sessionID = UUID()
    private var animationTask: Task<Void, Never>?
    private var renderer: IncrementalRenderer?

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
    }

    var isShowingAutomaton: Bool { automatonImage != nil }

    // MARK: - Attachment

    func attach(_ url: URL) {
        let directory = Core.ImageImport.sessionDirectory(for: sessionID)
        launch {
            do {
                let normalized = try await Task.detached(priority: .userInitiated) {
                    try Core.ImageImport.normalize(url, into: directory)
                }.value
                self.attachment = ImageAttachment(url: normalized, displayName: url.lastPathComponent)
                self.attachmentError = nil
            } catch {
                self.attachmentError = error.localizedDescription
            }
        }
    }

    func removeAttachment() {
        attachment = nil
    }

    // MARK: - Sending

    func send() {
        guard canSend else { return }
        stopAutomaton()
        latestChoice = nil
        let text = inputText
        let imageURL = attachment?.url
        store.append(.userInput(text: text, imagePath: imageURL?.path))
        entries = store.entries
        inputText = ""
        attachment = nil
        run(text: text, imageURL: imageURL)
    }

    private func run(text: String, imageURL: URL?) {
        isRunning = true
        status = "choosing automaton…"
        let input = AgentInput(text: text, imageURL: imageURL)
        launch {
            do {
                for try await event in self.agent.run(input) {
                    self.handle(event)
                }
            } catch {
                self.store.apply(.failed(error.localizedDescription))
                self.entries = self.store.entries
            }
            self.isRunning = false
            self.status = ""
        }
    }

    private func handle(_ event: AgentEvent) {
        store.apply(event)
        switch event {
        case .choice(let choice):
            latestChoice = choice
            if let spec = Catalog.spec(id: choice.id) {
                startAutomaton(spec)
            }
            status = ""
        case .finished:
            status = ""
        case .failed(let message):
            status = ""
            _ = message
        case .text:
            status = ""
        }
        entries = store.entries
    }

    // MARK: - Automaton animation

    private func startAutomaton(_ spec: ProgramSpec) {
        stopAutomaton()
        currentSpec = spec
        let cols = min(spec.board.width, 1000)
        let rows = min(spec.board.height, 700)
        // A `.rand` entry draws a fresh row each run, so re-showing one gives a
        // different picture; `makeProgram()` keeps the deterministic seed for
        // the tests and golden hashes (inventory §1.4).
        let runSpec = spec.withRandomSeed(UInt64.random(in: .min ... .max))
        let renderer = IncrementalRenderer(spec: runSpec, cols: cols, rows: rows)
        self.renderer = renderer
        automatonImage = renderer.image()

        let stepsPerTick = max(1, Int((spec.display.stepsPerSecond / 30).rounded()))
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let renderer = self.renderer else { return }
                if renderer.advance(by: stepsPerTick) {
                    self.automatonImage = renderer.image()
                    return
                }
                self.automatonImage = renderer.image()
                do {
                    try await Task.sleep(nanoseconds: 33_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func replay() {
        guard let spec = currentSpec else { return }
        startAutomaton(spec)
    }

    func stopAutomaton() {
        animationTask?.cancel()
        animationTask = nil
        renderer = nil
        currentSpec = nil
        automatonImage = nil
    }

    // MARK: - Helpers

    /// `RATER_MODEL_PATH` first, then the `RATERModelPath` user default
    /// (`defaults write com.rater.app RATERModelPath /path/to/snapshot`), so a
    /// Finder launch can point at the local snapshot the engine loads. The
    /// engine never downloads, so a launch with no path fails.
    private static func agentConfiguration() -> AgentEngine.Configuration {
        var configuration = AgentEngine.Configuration.fromEnvironment()
        if configuration.modelDirectory == nil,
           let path = UserDefaults.standard.string(forKey: "RATERModelPath"),
           !path.isEmpty {
            configuration.modelDirectory = URL(
                fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
        }
        return configuration
    }

    /// Runs a `@MainActor` async closure from a synchronous call site.
    private func launch(_ body: @escaping @MainActor () async -> Void) {
        Task { await body() }
    }
}
