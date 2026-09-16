// TapTapTapArguments: a small, dependency-free command-line parser that covers exactly what
// taptaptap's commands declare. It replaces swift-argument-parser 1.5.0 while keeping the same
// declaration style (@Option / @Flag / @Argument property wrappers, CommandConfiguration,
// ValidationError) and the same accepted syntax, help text, error text and exit codes. That
// compatibility is verified by Tests/Goldens (stable + parser cases recorded from the
// ArgumentParser build). No ArgumentParser code is included; behaviour was matched from its
// observable output and documentation.
//
// Supported: --name value, --name=value, -x value, -x=value, flags, repeated options collected into
// arrays, positional arguments (required, optional, repeated), String/Int/Double and String-backed
// CaseIterable enum values, defaults, `--`, -h/--help/--help-hidden, --version, `help [<subcommand>]`.
// Not supported (never used by taptaptap): option groups, grouped short flags, custom parsing
// strategies, transforms. ArgumentParser's generated extras --generate-completion-script and
// --experimental-dump-help are deliberately absent (shell-completion and JSON help generators).

import Foundation

// MARK: - Commands

public struct CommandConfiguration {
  public var commandName: String?
  public var abstract: String
  public var discussion: String
  public var version: String
  public var shouldDisplay: Bool
  public var subcommands: [any ParsableCommand.Type]
  var showsHelpOption = true

  public init(
    commandName: String? = nil,
    abstract: String = "",
    discussion: String = "",
    version: String = "",
    shouldDisplay: Bool = true,
    subcommands: [any ParsableCommand.Type] = []
  ) {
    self.commandName = commandName
    self.abstract = abstract
    self.discussion = discussion
    self.version = version
    self.shouldDisplay = shouldDisplay
    self.subcommands = subcommands
  }
}

public protocol ParsableCommand {
  static var configuration: CommandConfiguration { get }
  init()
  mutating func validate() throws
}

extension ParsableCommand {
  public mutating func validate() throws {}
}

public protocol AsyncParsableCommand: ParsableCommand {
  mutating func run() async throws
}

extension AsyncParsableCommand {
  /// A command with subcommands and no run() of its own prints its help.
  public mutating func run() async throws {
    throw HelpRequest()
  }
}

/// Raised by the default run(): print the help of the command being run.
struct HelpRequest: Error {}

/// A user error found while validating arguments. Printed with the command's usage; exit code 64.
public struct ValidationError: Error, CustomStringConvertible, LocalizedError {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var description: String {
    message
  }

  // Deliberate difference from ArgumentParser: its ValidationError had no localized description,
  // so batch step failures (which print localizedDescription) read "The operation couldn't be
  // completed. (ArgumentParser.ValidationError error 1.)". Here they print the message.
  public var errorDescription: String? {
    message
  }
}

// MARK: - Values

public protocol ExpressibleByArgument {
  init?(argument: String)
  /// Every accepted value, listed in help and in invalid-value errors (empty: unrestricted).
  static var allValueStrings: [String] { get }
  /// How a default value is shown in help ("(default: ...)").
  var defaultValueDescription: String { get }
}

extension ExpressibleByArgument {
  public static var allValueStrings: [String] {
    []
  }

  public var defaultValueDescription: String {
    "\(self)"
  }
}

extension ExpressibleByArgument where Self: CaseIterable, Self: RawRepresentable, RawValue == String {
  public init?(argument: String) {
    self.init(rawValue: argument)
  }

  public static var allValueStrings: [String] {
    allCases.map(\.rawValue)
  }

  public var defaultValueDescription: String {
    rawValue
  }
}

extension String: ExpressibleByArgument {
  public init?(argument: String) {
    self = argument
  }
}

extension Int: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(argument)
  }
}

extension Double: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(argument)
  }
}

// MARK: - Names and help

public struct NameSpecification: ExpressibleByArrayLiteral {
  enum Element {
    /// The property name, converted to kebab case.
    case derivedLong
    case long(String)
    case short(Character)
  }

  let elements: [Element]

  init(_ elements: [Element]) {
    self.elements = elements
  }

  public init(arrayLiteral elements: NameSpecification...) {
    self.elements = elements.flatMap(\.elements)
  }

  public static var long: NameSpecification {
    NameSpecification([.derivedLong])
  }

  public static func customLong(_ name: String) -> NameSpecification {
    NameSpecification([.long(name)])
  }

  public static func customShort(_ name: Character) -> NameSpecification {
    NameSpecification([.short(name)])
  }
}

public struct ArgumentHelp: ExpressibleByStringInterpolation {
  public var abstract: String
  public var valueName: String?

  public init(_ abstract: String, valueName: String? = nil) {
    self.abstract = abstract
    self.valueName = valueName
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }
}

// MARK: - Property wrappers

@propertyWrapper
public struct Option<Value>: ArgumentProvider {
  let argument: ArgumentDeclaration

  public var wrappedValue: Value {
    get { argument.value as! Value }
    set { argument.value = newValue }
  }
}

extension Option where Value: ExpressibleByArgument {
  public init(wrappedValue: Value, name: NameSpecification = .long, help: ArgumentHelp? = nil) {
    argument = ArgumentDeclaration(
      kind: .option, names: name.elements, help: help, arity: .single, isOptional: true,
      initialValue: wrappedValue, defaultDescription: wrappedValue.defaultValueDescription,
      allValues: Value.allValueStrings, convert: { Value(argument: $0) })
  }

  public init(name: NameSpecification = .long, help: ArgumentHelp? = nil) {
    argument = ArgumentDeclaration(
      kind: .option, names: name.elements, help: help, arity: .single, isOptional: false,
      initialValue: nil, defaultDescription: nil,
      allValues: Value.allValueStrings, convert: { Value(argument: $0) })
  }
}

extension Option {
  public init<Element: ExpressibleByArgument>(name: NameSpecification = .long, help: ArgumentHelp? = nil) where Value == Element? {
    argument = ArgumentDeclaration(
      kind: .option, names: name.elements, help: help, arity: .single, isOptional: true,
      initialValue: Element?.none as Any, defaultDescription: nil,
      allValues: Element.allValueStrings, convert: { Element(argument: $0) })
  }

  public init<Element: ExpressibleByArgument>(wrappedValue: [Element], name: NameSpecification = .long, help: ArgumentHelp? = nil) where Value == [Element] {
    argument = ArgumentDeclaration(
      kind: .option, names: name.elements, help: help, arity: .repeated(append: { (($0 as? [Element]) ?? []) + [$1 as! Element] }),
      isOptional: true, initialValue: wrappedValue,
      defaultDescription: wrappedValue.isEmpty ? nil : wrappedValue.map(\.defaultValueDescription).joined(separator: " "),
      allValues: Element.allValueStrings, convert: { Element(argument: $0) })
  }
}

@propertyWrapper
public struct Flag: ArgumentProvider {
  let argument: ArgumentDeclaration

  public var wrappedValue: Bool {
    get { argument.value as! Bool }
    set { argument.value = newValue }
  }

  public init(wrappedValue: Bool = false, name: NameSpecification = .long, help: ArgumentHelp? = nil) {
    argument = ArgumentDeclaration(
      kind: .flag, names: name.elements, help: help, arity: .single, isOptional: true,
      initialValue: wrappedValue, defaultDescription: nil, allValues: [], convert: { _ in true })
  }
}

@propertyWrapper
public struct Argument<Value>: ArgumentProvider {
  let argument: ArgumentDeclaration

  public var wrappedValue: Value {
    get { argument.value as! Value }
    set { argument.value = newValue }
  }
}

extension Argument where Value: ExpressibleByArgument {
  public init(help: ArgumentHelp? = nil) {
    argument = ArgumentDeclaration(
      kind: .positional, names: [], help: help, arity: .single, isOptional: false,
      initialValue: nil, defaultDescription: nil,
      allValues: Value.allValueStrings, convert: { Value(argument: $0) })
  }
}

extension Argument {
  public init<Element: ExpressibleByArgument>(help: ArgumentHelp? = nil) where Value == Element? {
    argument = ArgumentDeclaration(
      kind: .positional, names: [], help: help, arity: .single, isOptional: true,
      initialValue: Element?.none as Any, defaultDescription: nil,
      allValues: Element.allValueStrings, convert: { Element(argument: $0) })
  }

  // Phase 4: made public (was module-internal) so a command declared outside this module — e.g.
  // `ui key-sequence [<keycode> ...]` in TapTapTapCLI, matching idb's `nargs="*"` — can declare a
  // repeated positional array. Previously only HelpCommand (in this module) used this shape.
  public init<Element: ExpressibleByArgument>(wrappedValue: [Element], help: ArgumentHelp? = nil) where Value == [Element] {
    argument = ArgumentDeclaration(
      kind: .positional, names: [], help: help, arity: .repeated(append: { (($0 as? [Element]) ?? []) + [$1 as! Element] }),
      isOptional: true, initialValue: wrappedValue, defaultDescription: nil,
      allValues: Element.allValueStrings, convert: { Element(argument: $0) })
  }
}

// MARK: - Declaration storage

protocol ArgumentProvider {
  var argument: ArgumentDeclaration { get }
}

/// One declared argument. A reference type shared by the property wrapper and the parser: a command
/// value is created, parsed once and then run, so shared storage between copies is intended.
final class ArgumentDeclaration {
  enum Kind {
    case option
    case flag
    case positional
  }

  enum Arity {
    case single
    /// Appends a converted value to the current array (nil: start empty, replacing any default).
    case repeated(append: (Any?, Any) -> Any)

    var isRepeated: Bool {
      if case .repeated = self { return true }
      return false
    }
  }

  let kind: Kind
  let nameElements: [NameSpecification.Element]
  let help: ArgumentHelp?
  let arity: Arity
  /// Not required on the command line: an Optional, a default value, a flag or an array.
  let isOptional: Bool
  let defaultDescription: String?
  let allValues: [String]
  let convert: (String) -> Any?
  var value: Any?
  var propertyName = ""
  var wasSet = false

  init(
    kind: Kind, names: [NameSpecification.Element], help: ArgumentHelp?, arity: Arity, isOptional: Bool,
    initialValue: Any?, defaultDescription: String?, allValues: [String], convert: @escaping (String) -> Any?
  ) {
    self.kind = kind
    self.nameElements = names
    self.help = help
    self.arity = arity
    self.isOptional = isOptional
    self.defaultDescription = defaultDescription
    self.allValues = allValues
    self.convert = convert
    self.value = initialValue
  }
}
