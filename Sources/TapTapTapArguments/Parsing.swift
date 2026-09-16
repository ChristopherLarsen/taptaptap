import Foundation

// MARK: - Names

enum Name: Equatable {
  case long(String)
  case short(Character)

  /// "--udid", "-x"
  var synopsis: String {
    switch self {
    case .long(let name): return "--" + name
    case .short(let name): return "-" + String(name)
    }
  }
}

extension ArgumentDeclaration {
  var names: [Name] {
    nameElements.map { element in
      switch element {
      case .derivedLong: return .long(propertyName.kebabCased())
      case .long(let name): return .long(name)
      case .short(let name): return .short(name)
      }
    }
  }

  /// The long name if there is one, else the short name.
  var preferredName: Name? {
    names.first { if case .long = $0 { return true } else { return false } } ?? names.first
  }

  var valueName: String {
    if let valueName = help?.valueName, !valueName.isEmpty {
      return valueName
    }
    switch preferredName {
    case .long(let name)?: return name
    case .short(let name)?: return String(name)
    case nil: return propertyName.kebabCased()
    }
  }

  var abstract: String {
    help?.abstract ?? ""
  }

  /// "--udid <udid>", "--stdin", "<text>" (the preferred name only; no brackets).
  var unadornedSynopsis: String {
    switch kind {
    case .positional: return "<\(valueName)>"
    case .flag: return preferredName?.synopsis ?? ""
    case .option: return (preferredName?.synopsis ?? "") + " <\(valueName)>"
    }
  }

  /// Usage-line form: "... " for repeated, "[...]" for optional.
  var synopsis: String {
    var text = unadornedSynopsis
    if arity.isRepeated {
      text += " ..."
    }
    return isOptional ? "[\(text)]" : text
  }

  /// Help-row label: every name (short names first), then "<value>" for options.
  var helpLabel: String {
    switch kind {
    case .positional:
      return "<\(valueName)>"
    case .flag, .option:
      let shorts = names.filter { if case .short = $0 { return true } else { return false } }
      let longs = names.filter { if case .long = $0 { return true } else { return false } }
      let joined = (shorts + longs).map(\.synopsis).joined(separator: ", ")
      return kind == .option ? "\(joined) <\(valueName)>" : joined
    }
  }
}

extension String {
  /// "buttonType" -> "button-type", "DescribeUI" -> "describe-ui", "URLSession" -> "url-session".
  func kebabCased() -> String {
    var result = ""
    var separateOnUppercase = true
    let characters = Array(self)
    for (index, character) in characters.enumerated() {
      if character.isUppercase {
        if separateOnUppercase && !result.isEmpty {
          result.append("-")
        }
        // Inside an acronym, separate again only before its last capital when a lowercase follows.
        separateOnUppercase = index + 2 < characters.count && characters[index + 1].isUppercase && characters[index + 2].isLowercase
      } else {
        separateOnUppercase = character != "-"
      }
      result += character.lowercased()
    }
    return result
  }

  /// Levenshtein distance, used for "Did you mean" suggestions.
  func editDistance(to other: String) -> Int {
    let source = Array(self)
    let target = Array(other)
    if source.isEmpty || target.isEmpty {
      return Swift.max(source.count, target.count)
    }
    var previous = Array(0...target.count)
    for (i, sourceCharacter) in source.enumerated() {
      var current = [i + 1] + Array(repeating: 0, count: target.count)
      for (j, targetCharacter) in target.enumerated() {
        let substitution = previous[j] + (sourceCharacter == targetCharacter ? 0 : 1)
        current[j + 1] = Swift.min(previous[j + 1] + 1, current[j] + 1, substitution)
      }
      previous = current
    }
    return previous[target.count]
  }
}

// MARK: - Command metadata

extension ParsableCommand {
  static var commandName: String {
    configuration.commandName ?? String(describing: self).kebabCased()
  }

  /// The declared arguments of a fresh instance, in declaration order.
  static func declaredArguments() -> [ArgumentDeclaration] {
    declaredArguments(of: Self())
  }

  static func declaredArguments(of instance: Self) -> [ArgumentDeclaration] {
    Mirror(reflecting: instance).children.compactMap { child in
      guard let provider = child.value as? ArgumentProvider else {
        return nil
      }
      let argument = provider.argument
      argument.propertyName = String((child.label ?? "").drop(while: { $0 == "_" }))
      return argument
    }
  }
}

/// The built-in `help [<subcommands> ...]` command.
struct HelpCommand: ParsableCommand {
  static var configuration: CommandConfiguration {
    var configuration = CommandConfiguration(commandName: "help", abstract: "Show subcommand help information.", shouldDisplay: false)
    configuration.showsHelpOption = false
    return configuration
  }

  @Argument var subcommands: [String] = []

  init() {}
}

// MARK: - Errors

enum ParseError: Error {
  case missingValue(ArgumentDeclaration, Name)
  case unexpectedValue(Name, String)
  case invalidValue(ArgumentDeclaration, Name?, String)
  case missingExpectedArgument(ArgumentDeclaration)
  case unknownOption(Name)
  case unexpectedArguments([String])
  case validation(Error)
}

/// A parse or validation failure, with the command stack it happened in.
struct CommandFailure: Error, LocalizedError {
  let stack: [any ParsableCommand.Type]
  let error: ParseError

  /// One-line message (deliberate difference from ArgumentParser, whose CommandError had no
  /// localized description; batch step failures print this).
  var errorDescription: String? {
    Diagnostics.message(for: error, arguments: stack.last!.declaredArguments())
  }
}

// MARK: - Parsing one command

enum ParseOutcome<C: ParsableCommand> {
  case command(C)
  case help
  case version
}

enum CommandArgumentsParser {

  /// Parses `tokens` for command `C` in the order ArgumentParser reports problems:
  /// 1. while reading tokens: a missing option value, a value given to a flag, an unconvertible value;
  /// 2. -h/--help, then --version (when `versionAvailable`);
  /// 3. the first missing required argument, in declaration order;
  /// 4. validate();
  /// 5. the first unknown option, then unexpected extra values.
  static func parse<C: ParsableCommand>(_ type: C.Type, _ tokens: [String], versionAvailable: Bool) throws -> ParseOutcome<C> {
    var command = C()
    let declared = C.declaredArguments(of: command)
    let named = declared.filter { $0.kind != .positional }
    let positionals = declared.filter { $0.kind == .positional }
    let helpEnabled = C.configuration.showsHelpOption

    var helpRequested = false
    var versionRequested = false
    var unknownOptions: [Name] = []
    var values: [String] = []
    var terminated = false
    var index = 0

    func isValueToken(_ token: String) -> Bool {
      token == "-" || !token.hasPrefix("-")
    }

    func assign(_ argument: ArgumentDeclaration, name: Name?, raw: String) throws {
      guard let converted = argument.convert(raw) else {
        throw ParseError.invalidValue(argument, name, raw)
      }
      if case .repeated(let append) = argument.arity {
        argument.value = append(argument.wasSet ? argument.value : nil, converted)
      } else {
        argument.value = converted
      }
      argument.wasSet = true
    }

    func lookup(_ name: Name) -> ArgumentDeclaration? {
      named.first { $0.names.contains(name) }
    }

    /// Handles a matched named argument whose value is `attached` (from "=") or the next token.
    func consume(_ argument: ArgumentDeclaration, name: Name, attached: String?) throws {
      if argument.kind == .flag {
        if let attached {
          throw ParseError.unexpectedValue(name, attached)
        }
        argument.value = true
        argument.wasSet = true
        return
      }
      if let attached {
        guard !attached.isEmpty else {
          throw ParseError.missingValue(argument, name)
        }
        try assign(argument, name: name, raw: attached)
        return
      }
      guard index < tokens.count, isValueToken(tokens[index]) else {
        throw ParseError.missingValue(argument, name)
      }
      let raw = tokens[index]
      index += 1
      try assign(argument, name: name, raw: raw)
    }

    while index < tokens.count {
      let token = tokens[index]
      index += 1

      if terminated || isValueToken(token) {
        values.append(token)
        continue
      }
      if token == "--" {
        terminated = true
        continue
      }

      if token.hasPrefix("--") {
        let body = token.dropFirst(2)
        let nameText = body.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let attached = body.contains("=") ? String(body[body.index(after: body.firstIndex(of: "=")!)...]) : nil
        let name = Name.long(nameText)
        // --help-hidden also shows help: taptaptap declares no hidden arguments, so the output is the same.
        if helpEnabled && (nameText == "help" || nameText == "help-hidden") {
          helpRequested = true
        } else if versionAvailable && nameText == "version" {
          versionRequested = true
        } else if let argument = lookup(name) {
          try consume(argument, name: name, attached: attached)
        } else {
          unknownOptions.append(name)
        }
        continue
      }

      // Single dash: "-x", "-x=5", or a group such as "-x5" / "-udid".
      let body = Array(token.dropFirst())
      if let equals = body.firstIndex(of: "="), equals == 1 {
        let name = Name.short(body[0])
        if let argument = lookup(name) {
          try consume(argument, name: name, attached: String(body[2...]))
        } else {
          unknownOptions.append(name)
        }
        continue
      }
      for (position, character) in body.enumerated() {
        let name = Name.short(character)
        if helpEnabled && character == "h" {
          helpRequested = true
        } else if let argument = lookup(name) {
          if argument.kind == .option && position != body.count - 1 {
            // A value cannot follow inside the group.
            throw ParseError.missingValue(argument, name)
          }
          try consume(argument, name: name, attached: nil)
        } else {
          unknownOptions.append(name)
        }
      }
    }

    // Positional values, converted in order; anything beyond the declared positionals is extra.
    var extraValues: [String] = []
    var positionalIndex = 0
    for value in values {
      guard positionalIndex < positionals.count else {
        extraValues.append(value)
        continue
      }
      let argument = positionals[positionalIndex]
      try assign(argument, name: nil, raw: value)
      if !argument.arity.isRepeated {
        positionalIndex += 1
      }
    }

    if helpRequested {
      return .help
    }
    if versionRequested {
      return .version
    }
    if let missing = declared.first(where: { !$0.isOptional && !$0.wasSet }) {
      throw ParseError.missingExpectedArgument(missing)
    }
    do {
      try command.validate()
    } catch {
      throw ParseError.validation(error)
    }
    if let unknown = unknownOptions.first {
      throw ParseError.unknownOption(unknown)
    }
    if !extraValues.isEmpty {
      throw ParseError.unexpectedArguments(extraValues)
    }
    return .command(command)
  }
}

extension ParsableCommand {
  /// Parses `arguments` as this command (no subcommand dispatch) and validates it.
  /// If help or the version is requested, the returned value is not a `Self`.
  public static func parseAsRoot(_ arguments: [String]) throws -> any ParsableCommand {
    do {
      switch try CommandArgumentsParser.parse(Self.self, arguments, versionAvailable: !configuration.version.isEmpty) {
      case .command(let command):
        return command
      case .help, .version:
        return HelpCommand()
      }
    } catch let error as ParseError {
      throw CommandFailure(stack: [Self.self], error: error)
    }
  }
}
