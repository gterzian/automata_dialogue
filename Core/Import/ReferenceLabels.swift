import Foundation

/// The class each reference drawing illustrates, read from the `examples.json`
/// manifest in the drawing's directory. A label is display metadata: the
/// window shows it over the drawing, while the pixels the model reads carry no
/// text. A directory without a manifest contributes no labels, so an arbitrary
/// image stays unlabeled; a manifest that is present but unreadable is thrown,
/// never ignored.
public enum ReferenceLabels {
    public static let manifestName = "examples.json"

    /// Maps the input paths that the manifest names to their class. Each
    /// distinct directory is read once.
    public static func load(
        forPaths paths: [String],
        fileManager: FileManager = .default
    ) throws -> [String: Behavior] {
        var labels: [String: Behavior] = [:]
        var manifests: [String: [String: Behavior]] = [:]
        for path in paths {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            let key = directory.path
            let manifest: [String: Behavior]
            if let cached = manifests[key] {
                manifest = cached
            } else {
                manifest = try loadManifest(in: directory, fileManager: fileManager)
                manifests[key] = manifest
            }
            if let behavior = manifest[URL(fileURLWithPath: path).lastPathComponent] {
                labels[path] = behavior
            }
        }
        return labels
    }

    private static func loadManifest(
        in directory: URL,
        fileManager: FileManager
    ) throws -> [String: Behavior] {
        let url = directory.appendingPathComponent(manifestName)
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: Behavior].self, from: data)
    }
}
