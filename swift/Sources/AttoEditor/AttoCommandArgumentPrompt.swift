import AppKit
import Foundation

@MainActor
enum AttoCommandArgumentPrompt {
    static func promptArguments(for command: AttoCommandPaletteCommand) -> AttoCommandArguments? {
        guard command.schema.isParameterized else { return [:] }

        var seedArguments = command.initialArguments
        var validationMessage: String?

        while true {
            let form = buildForm(for: command, seedArguments: seedArguments)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = command.title
            alert.informativeText = validationMessage ?? informativeText(for: command)
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            alert.accessoryView = form.view

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return nil }

            do {
                let rawArguments = try form.arguments()
                return try command.schema.normalizedArguments(rawArguments)
            } catch {
                seedArguments = (try? form.arguments()) ?? seedArguments
                validationMessage = String(describing: error)
                NSSound.beep()
            }
        }
    }

    private static func informativeText(for command: AttoCommandPaletteCommand) -> String {
        let required = command.schema.parameters.filter(\.isRequired).map(\.title)
        guard required.isEmpty == false else {
            return "Provide arguments for this command."
        }
        return "Required: \(required.joined(separator: ", "))"
    }

    private static func buildForm(
        for command: AttoCommandPaletteCommand,
        seedArguments: AttoCommandArguments
    ) -> CommandArgumentForm {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        var fields: [CommandArgumentField] = []
        for parameter in command.schema.parameters {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 10

            let label = NSTextField(labelWithString: parameter.title)
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 92).isActive = true

            let input = inputView(for: parameter, value: seedArguments[parameter.name] ?? parameter.defaultValue)
            row.addArrangedSubview(label)
            row.addArrangedSubview(input.view)
            stack.addArrangedSubview(row)

            if let help = parameter.help, help.isEmpty == false {
                let helpLabel = NSTextField(labelWithString: help)
                helpLabel.font = NSFont.systemFont(ofSize: 11)
                helpLabel.textColor = .secondaryLabelColor
                helpLabel.lineBreakMode = .byWordWrapping
                helpLabel.maximumNumberOfLines = 2
                helpLabel.widthAnchor.constraint(equalToConstant: 360).isActive = true
                let helpRow = NSStackView()
                helpRow.orientation = .horizontal
                helpRow.spacing = 10
                let spacer = NSView()
                spacer.widthAnchor.constraint(equalToConstant: 92).isActive = true
                helpRow.addArrangedSubview(spacer)
                helpRow.addArrangedSubview(helpLabel)
                stack.addArrangedSubview(helpRow)
            }

            fields.append(CommandArgumentField(parameter: parameter, input: input))
        }

        let contentHeight = stack.arrangedSubviews.reduce(CGFloat(0)) { total, view in
            total + max(view.fittingSize.height, 24)
        }
        let spacingHeight = CGFloat(max(0, stack.arrangedSubviews.count - 1)) * stack.spacing
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: max(24, contentHeight + spacingHeight)))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return CommandArgumentForm(view: container, fields: fields)
    }

    private static func inputView(
        for parameter: AttoCommandParameterSchema,
        value: AttoCommandArgumentValue?
    ) -> CommandArgumentInput {
        if parameter.choices.isEmpty == false {
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24), pullsDown: false)
            for choice in parameter.choices {
                popup.addItem(withTitle: choice.title)
            }
            if let value,
               let index = parameter.choices.firstIndex(where: { $0.value == value })
            {
                popup.selectItem(at: index)
            }
            return .choice(popup)
        }

        switch parameter.kind {
        case .boolean:
            let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            if case .boolean(let boolValue) = value {
                checkbox.state = boolValue ? .on : .off
            }
            return .checkbox(checkbox)
        case .string, .integer, .number, .json:
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.stringValue = value.map(stringValue(for:)) ?? ""
            field.placeholderString = placeholder(for: parameter)
            field.selectText(nil)
            return .text(field)
        }
    }

    private static func placeholder(for parameter: AttoCommandParameterSchema) -> String {
        switch parameter.kind {
        case .string:
            return parameter.isRequired ? "Required text" : "Optional text"
        case .integer:
            return parameter.isRequired ? "Required integer" : "Optional integer"
        case .number:
            return parameter.isRequired ? "Required number" : "Optional number"
        case .boolean:
            return ""
        case .json:
            return parameter.isRequired ? "Required JSON" : "Optional JSON"
        }
    }

    private static func stringValue(for value: AttoCommandArgumentValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .integer(let integer):
            return String(integer)
        case .number(let number):
            return String(number)
        case .boolean(let boolean):
            return boolean ? "true" : "false"
        case .json(let json):
            return json
        }
    }

    private struct CommandArgumentForm {
        let view: NSView
        let fields: [CommandArgumentField]

        @MainActor
        func arguments() throws -> AttoCommandArguments {
            var arguments: AttoCommandArguments = [:]
            for field in fields {
                if let value = try field.value() {
                    arguments[field.parameter.name] = value
                }
            }
            return arguments
        }
    }

    private struct CommandArgumentField {
        let parameter: AttoCommandParameterSchema
        let input: CommandArgumentInput

        @MainActor
        func value() throws -> AttoCommandArgumentValue? {
            switch input {
            case .text(let field):
                return try textValue(field.stringValue)
            case .checkbox(let checkbox):
                return .boolean(checkbox.state == .on)
            case .choice(let popup):
                let index = popup.indexOfSelectedItem
                guard index >= 0, index < parameter.choices.count else { return nil }
                return parameter.choices[index].value
            }
        }

        private func textValue(_ rawValue: String) throws -> AttoCommandArgumentValue? {
            let text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty,
               parameter.isRequired == false,
               parameter.defaultValue == nil
            {
                return nil
            }

            switch parameter.kind {
            case .string:
                return .string(rawValue)
            case .integer:
                guard let integer = Int(text) else {
                    throw AttoCommandSchemaValidationError.typeMismatch(
                        name: parameter.name,
                        expected: parameter.kind.rawValue,
                        actual: AttoCommandParameterKind.string.rawValue
                    )
                }
                return .integer(integer)
            case .number:
                guard let number = Double(text) else {
                    throw AttoCommandSchemaValidationError.typeMismatch(
                        name: parameter.name,
                        expected: parameter.kind.rawValue,
                        actual: AttoCommandParameterKind.string.rawValue
                    )
                }
                return .number(number)
            case .boolean:
                return .boolean(text == "true" || text == "1")
            case .json:
                return .json(rawValue)
            }
        }
    }

    private enum CommandArgumentInput {
        case text(NSTextField)
        case checkbox(NSButton)
        case choice(NSPopUpButton)

        var view: NSView {
            switch self {
            case .text(let field):
                return field
            case .checkbox(let checkbox):
                return checkbox
            case .choice(let popup):
                return popup
            }
        }
    }
}
