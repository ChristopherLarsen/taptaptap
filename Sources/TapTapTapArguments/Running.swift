import Foundation

extension AsyncParsableCommand {
  /// Entry point for `@main`: parses the process arguments, runs the selected command and exits with
  /// 0 (success, help, version), 64 (usage or validation error) or 1 (any other error).
  public static func main() async {
    exit(await CommandRunner.run(Self.self, arguments: Array(CommandLine.arguments.dropFirst())))
  }
}

enum CommandRunner {

  /// Walks as many levels of `subcommands` as the input tokens name (e.g. `ui tap 100 200`
  /// descends root -> `ui` -> `tap` before parsing `100 200` against `tap`'s own arguments),
  /// stopping at the first token that isn't a declared subcommand name of the deepest match so
  /// far, or that starts with `-`. `help [<subcommand> ...]` is a root-only shortcut, matching
  /// ArgumentParser's own behaviour, and is handled by `runHelp`, which already walks its own
  /// token list to arbitrary depth.
  static func run(_ root: any AsyncParsableCommand.Type, arguments: [String]) async -> Int32 {
    if let first = arguments.first, first == "help", !root.configuration.subcommands.isEmpty {
      return runHelp(root: root, tokens: Array(arguments.dropFirst()))
    }

    var stack: [any ParsableCommand.Type] = [root]
    var tokens = arguments
    while let first = tokens.first, !first.hasPrefix("-"),
          let subcommand = stack.last!.configuration.subcommands.first(where: { $0.commandName == first }) {
      stack.append(subcommand)
      tokens = Array(tokens.dropFirst())
    }

    guard let leaf = stack.last as? any AsyncParsableCommand.Type else {
      return 1
    }
    return await run(leaf, stack: stack, tokens: tokens)
  }

  private static func run<C: AsyncParsableCommand>(_ type: C.Type, stack: [any ParsableCommand.Type], tokens: [String]) async -> Int32 {
    let outcome: ParseOutcome<C>
    do {
      outcome = try CommandArgumentsParser.parse(type, tokens, versionAvailable: stack.contains { !$0.configuration.version.isEmpty })
    } catch let error as ParseError {
      writeError(Diagnostics.usageError(for: error, stack: stack))
      return 64
    } catch {
      writeError("Error: \(String(describing: error))")
      return 1
    }

    switch outcome {
    case .help:
      print(HelpText.render(stack))
      return 0
    case .version:
      print(version(of: stack))
      return 0
    case .command(var command):
      do {
        try await command.run()
        return 0
      } catch {
        return report(error, root: stack[0])
      }
    }
  }

  /// `help [<subcommand> ...]`: help for the deepest named command that exists (root if none).
  private static func runHelp(root: any ParsableCommand.Type, tokens: [String]) -> Int32 {
    let helpStack: [any ParsableCommand.Type] = [root, HelpCommand.self]
    let names: [String]
    do {
      switch try CommandArgumentsParser.parse(HelpCommand.self, tokens, versionAvailable: !root.configuration.version.isEmpty) {
      case .command(let command):
        names = command.subcommands
      case .help:
        names = []
      case .version:
        print(version(of: helpStack))
        return 0
      }
    } catch let error as ParseError {
      writeError(Diagnostics.usageError(for: error, stack: helpStack))
      return 64
    } catch {
      return 1
    }

    var stack: [any ParsableCommand.Type] = [root]
    for name in names {
      let children = stack.last!.configuration.subcommands + (stack.count == 1 ? [HelpCommand.self] : [])
      guard let child = children.first(where: { $0.commandName == name }) else {
        break
      }
      stack.append(child)
    }
    print(HelpText.render(stack))
    return 0
  }

  /// Errors thrown by run(): usage errors are reported against the root command.
  private static func report(_ error: Error, root: any ParsableCommand.Type) -> Int32 {
    switch error {
    case is HelpRequest:
      print(HelpText.render([root]))
      return 0
    case let failure as CommandFailure:
      writeError(Diagnostics.usageError(for: failure.error, stack: failure.stack))
      return 64
    case let validation as ValidationError:
      writeError(Diagnostics.usageError(validation.message, help: "", stack: [root]))
      return 64
    case let localized as LocalizedError where localized.errorDescription != nil:
      writeError("Error: \(localized.errorDescription!)")
      return 1
    default:
      let message = type(of: error) is NSError.Type ? error.localizedDescription : String(describing: error)
      writeError("Error: \(message)")
      return 1
    }
  }

  private static func version(of stack: [any ParsableCommand.Type]) -> String {
    stack.map { $0.configuration.version }.last { !$0.isEmpty } ?? "Unspecified version"
  }

  private static func writeError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }
}
