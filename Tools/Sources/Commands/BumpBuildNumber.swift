import ArgumentParser
import CommandLineTools
import Foundation

// AGENT-PLATFORM (Brief 0067): the build number's only source of truth is
// `CURRENT_PROJECT_VERSION` in project.yml. Spiral has no CI that stamps it,
// and App Store Connect rejects a second upload of the same (version, build),
// so every TestFlight archive is preceded by one run of this command and a
// commit — the bump is then in git history next to what it shipped.
struct BumpBuildNumber: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Increments CURRENT_PROJECT_VERSION in project.yml and regenerates the Xcode project.",
                                                    discussion: "Run once before each TestFlight/App Store archive, then commit. Pass --to to set an explicit value (e.g. after a rejected upload).")

    @Option(name: .long, help: "Set the build number to this exact value instead of incrementing.")
    var to: Int?

    func run() throws {
        let newValue = try updateProjectYAML()
        logger.info("CURRENT_PROJECT_VERSION is now \(newValue)")
        try Zsh.run(command: "xcodegen")
    }

    /// Rewrites the single `CURRENT_PROJECT_VERSION:` line, preserving the rest
    /// of the file byte for byte (the same approach as `BumpCalendarVersion`).
    private func updateProjectYAML() throws -> Int {
        let yamlURL = URL.projectDirectory.appendingPathComponent("project.yml")
        let yamlString = try String(contentsOf: yamlURL, encoding: .utf8)

        let buildNumberRegex = /CURRENT_PROJECT_VERSION:\s*(\d+)/
        var updatedYAMLString = ""
        var newValue: Int?

        yamlString.enumerateLines { line, _ in
            if let match = line.firstMatch(of: buildNumberRegex), let current = Int(match.1) {
                let next = to ?? current + 1
                if let to, to <= current {
                    logger.warning("Setting the build number to \(to), which is not above the current \(current); App Store Connect will reject a reused (version, build) pair.")
                }
                newValue = next
                updatedYAMLString.append(line.replacingOccurrences(of: match.0, with: "CURRENT_PROJECT_VERSION: \(next)") + "\n")
            } else {
                updatedYAMLString.append(line + "\n")
            }
        }

        guard let newValue else {
            throw ValidationError("project.yml has no CURRENT_PROJECT_VERSION line to bump.")
        }

        try updatedYAMLString.write(to: yamlURL, atomically: true, encoding: .utf8)
        return newValue
    }
}
