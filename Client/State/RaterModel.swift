import AppKit
import Combine
import Core
import CoreGraphics

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
    @Published private(set) var latestRating: Rating?
    @Published private(set) var latestChoice: Choice?
    @Published var attachmentError: String?

    private let store = TranscriptStore()
    private let agent: any AgentRunning = HeuristicAgent()
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
        latestRating = nil
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
        status = "rating input…"
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
        case .rating(let rating):
            latestRating = rating
            status = "choosing automaton…"
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
        let renderer = IncrementalRenderer(spec: spec, cols: cols, rows: rows)
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

    /// Runs a `@MainActor` async closure from a synchronous call site.
    private func launch(_ body: @escaping @MainActor () async -> Void) {
        Task { await body() }
    }
}
