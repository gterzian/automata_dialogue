import Core
import SwiftUI

struct ContentView: View {
    @StateObject private var model = RaterModel()
    @State private var showHistory = false
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.10).ignoresSafeArea()

            if model.isShowingAutomaton {
                AutomatonView(image: model.automatonImage)
                    .ignoresSafeArea()
            } else {
                TranscriptList(entries: model.entries)
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .padding(.bottom, 130)
            }

            VStack(spacing: 0) {
                topBar
                if showHistory, model.isShowingAutomaton {
                    TranscriptList(entries: model.entries)
                        .frame(maxWidth: 560, maxHeight: 360)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 8)
                }
                Spacer()
            }
            .padding(16)

            VStack {
                Spacer()
                inputBar
            }
            .padding(20)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if let spec = model.currentSpec {
                Label("\(spec.id) · \(spec.title)", systemImage: "square.grid.3x3")
                    .font(.system(size: 13, weight: .semibold))
                if let rating = model.latestRating {
                    Text(rating.label.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.replay()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                Button {
                    showHistory.toggle()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
            } else {
                Text("Automata Rater")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            if !model.status.isEmpty {
                ProgressView().controlSize(.small)
                Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment = model.attachment {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text(attachment.displayName).font(.system(size: 12)).lineLimit(1)
                    Button {
                        model.removeAttachment()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
            }
            if let error = model.attachmentError {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Describe the input, or drop an image…", text: $model.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .onSubmit { model.send() }
                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.attach(url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}

struct TranscriptList: View {
    let entries: [TranscriptEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    TranscriptRowView(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}

struct TranscriptRowView: View {
    let entry: TranscriptEntry

    var body: some View {
        switch entry.kind {
        case .userInput(let text, let imagePath):
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if !text.isEmpty { Text(text) }
                    if imagePath != nil {
                        Label("image", systemImage: "photo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 460, alignment: .trailing)
            }
        case .rating(let rating):
            card(
                title: "\(rating.label.rawValue) · \(rating.confidence.rawValue)",
                icon: "tag",
                detail: rating.description
            )
        case .choice(let choice):
            let title = Catalog.spec(id: choice.id)?.title ?? choice.id
            card(title: "\(choice.id) · \(title)", icon: "square.grid.3x3", detail: choice.rationale)
        case .assistantMessage(let text, _):
            Text(text).font(.system(size: 13)).foregroundStyle(.white)
        case .errorMessage(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    private func card(title: String, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 520, alignment: .leading)
    }
}
