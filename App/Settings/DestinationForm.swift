import OtterCore
import SwiftUI

/// The selected destination's settings, by kind. T08 adds the Apple Notes form here.
struct DestinationForm: View {
    let model: SettingsModel
    let config: DestinationConfig

    var body: some View {
        Form {
            Section {
                TextField("Name:", text: Binding(
                    get: { config.name },
                    set: { name in model.update(config.id) { $0.name = name } }
                ))
            }
            switch config.options {
            case let .folder(options):
                FolderDestinationForm(model: model, id: config.id, options: options)
            }
            Section {
                DestinationTestRow(model: model, config: config)
            }
        }
        .formStyle(.grouped)
    }
}

/// Folder, mode, append file and template with a live preview, frontmatter.
private struct FolderDestinationForm: View {
    private enum Mode: Hashable {
        case newFile
        case append
    }

    let model: SettingsModel
    let id: DestinationID
    let options: FolderOptions

    /// The append file's name, kept while "A new file per note" is chosen.
    @State private var appendFileName = "Inbox"

    var body: some View {
        Section {
            LabeledContent("Folder:") {
                HStack {
                    Text(options.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(options.displayPath)
                    Button("Choose…") {
                        Task { await model.changeFolder(id) }
                    }
                    .accessibilityLabel("Choose folder")
                }
            }
            if let health = model.health[id], let problem = DestinationProblem(health: health, destinationName: model.config(id)?.name ?? "") {
                ProblemView(model: model, id: id, problem: problem)
            }
            Picker("Save each note:", selection: modeBinding) {
                Text("As a new file").tag(Mode.newFile)
                Text("At the end of one file").tag(Mode.append)
            }
            if case let .appendToFile(name) = options.mode {
                TextField("File:", text: Binding(
                    get: { name },
                    set: { name in model.updateFolder(id) { $0.mode = .appendToFile(name: name) } }
                ), prompt: Text("Inbox.md"))
            }
            Toggle(isOn: Binding(
                get: { options.frontmatter },
                set: { on in model.updateFolder(id) { $0.frontmatter = on } }
            )) {
                Text("Frontmatter")
                Text("`created` and `source` at the top of each new file.")
            }
        }
        if case .appendToFile = options.mode {
            Section("Template") {
                TextEditor(text: Binding(
                    get: { options.appendTemplate },
                    set: { template in model.updateFolder(id) { $0.appendTemplate = template } }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 72)
                .accessibilityLabel("Template")
                HStack {
                    Text("`{{time}}` `{{date}}` `{{text}}` `{{title}}` `{{attachments}}`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Default") {
                        model.updateFolder(id) { $0.appendTemplate = AppendTemplate.default }
                    }
                    .disabled(options.appendTemplate == AppendTemplate.default)
                    .accessibilityLabel("Use the default template")
                }
                LabeledContent("Preview:") {
                    Text(preview)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: {
                if case .appendToFile = options.mode {
                    return .append
                }
                return .newFile
            },
            set: { mode in
                if case let .appendToFile(name) = options.mode {
                    appendFileName = name
                }
                let fileName = appendFileName
                model.updateFolder(id) { options in
                    options.mode = mode == .append ? .appendToFile(name: fileName) : .newFilePerNote
                }
            }
        )
    }

    /// What a one-line note and a longer one would add to the file, now.
    private var preview: String {
        let now = Date()
        return [
            "Pick up oat milk",
            "Call Sam about the Q4 deck\n- ask about the revised budget",
        ]
        .map { MarkdownWriter.appendBlock(template: options.appendTemplate, text: $0, createdAt: now, timeZone: .current) }
        .joined(separator: "\n\n")
    }
}

/// The Test button and its result.
private struct DestinationTestRow: View {
    let model: SettingsModel
    let config: DestinationConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Test") {
                    Task { await model.test(config.id) }
                }
                .disabled(model.tests[config.id] == .running)
                .help("Writes a note saying “\(DestinationTest.text)”")
                if model.tests[config.id] == .running {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
            switch model.tests[config.id] {
            case let .passed(receipt):
                HStack {
                    Label(savedMessage(receipt), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if case let .file(url) = receipt.location {
                        Button("Open") {
                            ObsidianLink.open(url)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            case let .failed(problem):
                ProblemView(model: model, id: config.id, problem: problem)
            case .running, nil:
                EmptyView()
            }
        }
    }

    private func savedMessage(_ receipt: DeliveryReceipt) -> String {
        guard case let .file(url) = receipt.location else {
            return "Test note saved."
        }
        return "Saved “\(url.lastPathComponent)”."
    }
}

/// A problem in words, and its fix as a button.
private struct ProblemView: View {
    let model: SettingsModel
    let id: DestinationID
    let problem: DestinationProblem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            switch problem.fix {
            case .chooseFolder:
                Button("Choose Folder…") {
                    Task { await model.changeFolder(id) }
                }
            case .grantAccess:
                Button("Grant Access…") {
                    Task { await model.changeFolder(id) }
                }
            case nil:
                EmptyView()
            }
        }
    }
}
