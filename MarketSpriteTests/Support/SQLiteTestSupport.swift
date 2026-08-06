import Foundation

enum SQLiteTestSupport {
    static func execute(_ sql: String, atPath path: String) throws {
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, sql]
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sqlite3 failed"
            throw SQLiteTestSupportError.commandFailed(message)
        }
    }
}

private enum SQLiteTestSupportError: Error {
    case commandFailed(String)
}
