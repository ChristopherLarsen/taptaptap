import Foundation

// MARK: - Text wrapping

extension String {
  /// Wraps to `width` columns, prefixing every non-empty line with `indent` spaces. A line breaks at
  /// the last space within the available columns (or, failing that, at the next space); explicit
  /// newlines are kept. This reproduces ArgumentParser's layout byte for byte.
  func wrapped(to width: Int, indent: Int = 0) -> String {
    let columns = width - indent
    guard columns > 0 else {
      return ""
    }
    var lines: [Substring] = []
    var start = startIndex
    while true {
      let chunk = self[start...].prefix(columns)
      if let lastNewline = chunk.lastIndex(of: "\n") {
        lines.append(contentsOf: self[start..<lastNewline].split(separator: "\n", omittingEmptySubsequences: false))
        start = index(after: lastNewline)
      } else if chunk.endIndex == endIndex {
        lines.append(self[start...])
        break
      } else if let lastSpace = chunk.lastIndex(of: " ") {
        lines.append(self[start..<lastSpace])
        start = index(after: lastSpace)
      } else if let nextSpace = self[start...].firstIndex(of: " ") {
        lines.append(self[start..<nextSpace])
        start = index(after: nextSpace)
      } else {
        lines.append(self[start...])
        break
      }
    }
    let padding = String(repeating: " ", count: indent)
    return lines.map { $0.isEmpty ? String($0) : padding + $0 }.joined(separator: "\n")
  }
}

// MARK: - Help

enum HelpText {
  static let width = 80
  static let labelColumn = 26

  static func toolName(_ stack: [any ParsableCommand.Type]) -> String {
    stack.map { $0.commandName }.joined(separator: " ")
  }

  /// "axe tap [-x <x>] ... --udid <udid>", "axe <subcommand>"
  static func usage(_ stack: [any ParsableCommand.Type]) -> String {
    let command = stack.last!
    let name = toolName(stack)
    let arguments = command.declaredArguments()
    var usage: String
    switch arguments.count {
    case 0:
      usage = name
    case 13...:
      let required = arguments.filter { $0.kind == .positional || !$0.isOptional }
      if !required.isEmpty, required.count <= 12 {
        usage = "\(name) [<options>] " + required.map(\.synopsis).joined(separator: " ")
      } else {
        usage = "\(name) <options>"
      }
    default:
      usage = name + " " + arguments.map(\.synopsis).joined(separator: " ")
    }
    if !command.configuration.subcommands.isEmpty {
      usage += " <subcommand>"
    }
    return usage
  }

  static func row(label: String, abstract: String) -> String {
    let paddedLabel = "  " + label
    guard !abstract.isEmpty else {
      return paddedLabel + "\n"
    }
    let wrappedAbstract = abstract.wrapped(to: width, indent: labelColumn)
    if paddedLabel.count < labelColumn {
      return paddedLabel + wrappedAbstract.dropFirst(paddedLabel.count) + "\n"
    }
    return paddedLabel + "\n" + wrappedAbstract + "\n"
  }

  static func description(of argument: ArgumentDeclaration) -> String {
    let values = argument.allValues.filter { !$0.isEmpty }
    let defaultValue = argument.defaultDescription ?? ""
    let suffix: String
    switch (values.isEmpty, defaultValue.isEmpty) {
    case (true, true): suffix = ""
    case (false, true): suffix = "(values: \(values.joined(separator: ", ")))"
    case (true, false): suffix = "(default: \(defaultValue))"
    case (false, false): suffix = "(values: \(values.joined(separator: ", ")); default: \(defaultValue))"
    }
    return [argument.abstract, suffix].filter { !$0.isEmpty }.joined(separator: " ")
  }

  static func render(_ stack: [any ParsableCommand.Type]) -> String {
    let command = stack.last!
    let configuration = command.configuration
    let arguments = command.declaredArguments()

    var abstract = configuration.abstract
    if !configuration.discussion.isEmpty {
      if !abstract.isEmpty {
        abstract += "\n"
      }
      abstract += "\n" + configuration.discussion
    }

    let positionalRows = arguments.filter { $0.kind == .positional }.map { row(label: $0.helpLabel, abstract: description(of: $0)) }
    var optionRows = arguments.filter { $0.kind != .positional }.map { row(label: $0.helpLabel, abstract: description(of: $0)) }
    if stack.contains(where: { !$0.configuration.version.isEmpty }) {
      optionRows.append(row(label: "--version", abstract: "Show the version."))
    }
    if configuration.showsHelpOption {
      optionRows.append(row(label: "-h, --help", abstract: "Show help information."))
    }
    let subcommandRows = configuration.subcommands
      .filter { $0.configuration.shouldDisplay }
      .map { row(label: $0.commandName, abstract: $0.configuration.abstract) }

    let sections = [("ARGUMENTS", positionalRows), ("OPTIONS", optionRows), ("SUBCOMMANDS", subcommandRows)]
      .filter { !$0.1.isEmpty }
      .map { "\($0.0):\n" + $0.1.joined() }
      .joined(separator: "\n")

    var names = stack.map { $0.commandName }
    names.insert("help", at: 1)
    let helpSubcommandMessage = subcommandRows.isEmpty ? "" : "\n  See '\(names.joined(separator: " ")) <subcommand>' for detailed help."
    let renderedAbstract = abstract.isEmpty ? "" : "OVERVIEW: \(abstract)".wrapped(to: width) + "\n\n"
    return renderedAbstract + "USAGE: \(usage(stack))\n\n" + sections + helpSubcommandMessage
  }
}

// MARK: - Diagnostics

enum Diagnostics {

  static func message(for error: ParseError, arguments: [ArgumentDeclaration]) -> String {
    switch error {
    case .missingValue(let argument, let name):
      return "Missing value for '\(name.synopsis) <\(argument.valueName)>'"
    case .unexpectedValue(let name, let value):
      return "The option '\(name.synopsis)' does not take any value, but '\(value)' was specified."
    case .invalidValue(let argument, let name, let value):
      let target = name.map { "\($0.synopsis) <\(argument.valueName)>" } ?? "<\(argument.valueName)>"
      return "The value '\(value)' is invalid for '\(target)'" + valueList(argument.allValues)
    case .missingExpectedArgument(let argument):
      var synopsis = argument.unadornedSynopsis
      if argument.arity.isRepeated {
        synopsis += " ..."
      }
      return "Missing expected argument '\(synopsis)'"
    case .unknownOption(let name):
      guard case .long = name else {
        return "Unknown option '\(name.synopsis)'"
      }
      let candidates = arguments.flatMap(\.names).filter { if case .long = $0 { return true } else { return false } }
      var best: (name: Name, distance: Int)?
      for candidate in candidates {
        let distance = candidate.synopsis.editDistance(to: name.synopsis)
        if distance < 4, distance < (best?.distance ?? Int.max) {
          best = (candidate, distance)
        }
      }
      if let best {
        return "Unknown option '\(name.synopsis)'. Did you mean '\(best.name.synopsis)'?"
      }
      return "Unknown option '\(name.synopsis)'"
    case .unexpectedArguments(let values):
      if values.count == 1 {
        return "Unexpected argument '\(values[0])'"
      }
      return "\(values.count) unexpected arguments: '\(values.joined(separator: "', '"))'"
    case .validation(let error):
      if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
      }
      return String(describing: error)
    }
  }

  static func valueList(_ values: [String]) -> String {
    guard !values.isEmpty else {
      return ""
    }
    guard values.count < 6 else {
      return ". Please provide one of the following:\n" + values.map { "  - \($0)" }.joined(separator: "\n")
    }
    let quoted = values.map { "'\($0)'" }
    let list = quoted.count <= 2 ? quoted.joined(separator: " and ") : quoted.dropLast().joined(separator: ", ") + " or \(quoted.last!)"
    return ". Please provide one of \(list)."
  }

  /// The "Help:" line content for errors that name one argument, else "".
  static func helpLine(for error: ParseError) -> String {
    switch error {
    case .missingValue(let argument, let name):
      return "\(name.synopsis) <\(argument.valueName)>  \(argument.abstract)"
    case .invalidValue(let argument, let name, _):
      guard let name else {
        return "<\(argument.valueName)>  \(argument.abstract)"
      }
      return "\(name.synopsis) <\(argument.valueName)>  \(argument.abstract)"
    case .missingExpectedArgument(let argument):
      guard let first = argument.names.first else {
        return "<\(argument.valueName)>  \(argument.abstract)"
      }
      return "\(first.synopsis) <\(argument.valueName)>  \(argument.abstract)"
    default:
      return ""
    }
  }

  /// "Error: ...\nHelp:  ...\nUsage: ...\n  See '<command> --help' for more information."
  static func usageError(_ message: String, help: String, stack: [any ParsableCommand.Type]) -> String {
    var text = message.isEmpty ? "" : "Error: \(message)\n"
    if !help.isEmpty {
      text += "Help:  \(help)\n"
    }
    text += "Usage: \(HelpText.usage(stack))"
    if stack.last!.configuration.showsHelpOption {
      text += "\n  See '\(HelpText.toolName(stack)) --help' for more information."
    }
    return text
  }

  static func usageError(for error: ParseError, stack: [any ParsableCommand.Type]) -> String {
    usageError(message(for: error, arguments: stack.last!.declaredArguments()), help: helpLine(for: error), stack: stack)
  }
}
