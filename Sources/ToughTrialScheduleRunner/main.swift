import Foundation
import ToughTrialV2Core

@main
struct ToughTrialScheduleRunner {
    enum RunnerError: Error { case arguments, configuration, changedFile, pendingRequests }

    static func main() async {
        do {
            try await run()
        } catch {
            // Never print model content, provider error bodies, or environment values.
            let message: String
            switch error {
            case RunnerError.arguments:
                message = "Usage: ToughTrialScheduleRunner --validate FILE | --file FILE | --github | --example"
            case RunnerError.configuration:
                message = "Missing or invalid runner configuration. See docs/sync/remote-runner.md."
            case RunnerError.changedFile, V2GitHubScheduleError.conflict:
                message = "Schedule changed concurrently. No stale result was written; run again."
            case RunnerError.pendingRequests:
                message = "Run limit reached; saved changes are retained. Run again for remaining requests."
            case is V2ScheduleMarkdownError, is V2ScheduleMergeError:
                message = "Invalid schedule document; original data was retained."
            case is V2ScheduleClientError:
                message = "AI request failed or returned an invalid proposal; pending request was retained."
            default:
                message = "Runner failed; retry will re-read request status before applying changes."
            }
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let mode = args.first else { throw RunnerError.arguments }
        if mode == "--example", args.count == 1 {
            let document = V2ScheduleDocument(id: "synthetic-schedule-test", timeZoneIdentifier: "Asia/Shanghai",
                taskContexts: [], tasks: [], planItems: [], executionSegments: [], remoteRequests: [
                    .init(id: "synthetic-request-1", prompt: "新增准备演示的任务，拆成整理提纲和检查演示两个步骤。先不要安排日期，备注保留总共最多 2 小时。", createdAt: Date())
                ], preamble: "# 合成日程测试\n此文件没有个人真实日程。")
            print(try V2ScheduleMarkdown.encode(document))
            return
        }
        if mode == "--validate", args.count == 2 {
            let document = try V2ScheduleMarkdown.decode(String(contentsOfFile: args[1], encoding: .utf8))
            print("Valid document: \(document.tasks.count) tasks, \(document.remoteRequests.count) requests.")
            return
        }
        guard (mode == "--github" && args.count == 1) || (mode == "--file" && args.count == 2) else {
            throw RunnerError.arguments
        }
        let env = ProcessInfo.processInfo.environment
        func required(_ name: String) throws -> String {
            guard let value = env[name], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RunnerError.configuration
            }
            return value
        }
        let endpoint = try required("SCHEDULE_AI_ENDPOINT")
        guard let url = URL(string: endpoint), url.scheme == "https" else { throw RunnerError.configuration }
        let client = V2OpenAICompatibleScheduleClient(configuration: .init(endpoint: url,
            apiKey: try required("SCHEDULE_AI_API_KEY"), model: try required("SCHEDULE_AI_MODEL")))
        if mode == "--github" {
            let repo = try required("SCHEDULE_REPOSITORY").split(separator: "/", omittingEmptySubsequences: false)
            guard repo.count == 2 else { throw RunnerError.configuration }
            let github = V2GitHubScheduleClient(location: .init(owner: String(repo[0]), repository: String(repo[1]),
                branch: try required("SCHEDULE_BRANCH"), path: try required("SCHEDULE_PATH")),
                token: try required("SCHEDULE_GITHUB_TOKEN"))
            let result = try await V2ScheduleRemoteRunner.run(github: github, client: client)
            print("Processed: \(result.processedCount); pending: \(result.pendingCount); conflict retries: \(result.conflictRetries).")
            if result.pendingCount > 0 { throw RunnerError.pendingRequests }
        } else {
            let url = URL(fileURLWithPath: args[1])
            for _ in 0..<100 {
                let original = try Data(contentsOf: url)
                guard let text = String(data: original, encoding: .utf8) else { throw RunnerError.arguments }
                let document = try V2ScheduleMarkdown.decode(text)
                guard let updated = try await V2ScheduleRemoteProcessor.processNext(in: document, using: client) else {
                    print("No pending requests.")
                    return
                }
                let output = Data(try V2ScheduleMarkdown.encode(updated).utf8)
                try coordinatedWrite(url: url, original: original, output: output)
                print("Processed one request.")
            }
            throw RunnerError.pendingRequests
        }
    }

    static func coordinatedWrite(url: URL, original: Data, output: Data) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                guard try Data(contentsOf: coordinatedURL) == original else { throw RunnerError.changedFile }
                try output.write(to: coordinatedURL, options: .atomic)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
