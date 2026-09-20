import Foundation
import ToughTrialV2Core

func checkGitHubScheduleVersionedWrites() async throws {
    let location = V2GitHubScheduleLocation(owner: "example", repository: "private-schedule", branch: "sync/test", path: "日程/执行文件.md")
    let sha = String(repeating: "a", count: 40)
    let response = try JSONSerialization.data(withJSONObject: ["type": "file", "encoding": "base64", "sha": sha, "content": Data("# 日程".utf8).base64EncodedString()])
    let transport = GitHubScheduleTransport(data: response, status: 200)
    let client = V2GitHubScheduleClient(location: location, token: "test-credential", transport: transport)
    let revision = try await client.read()
    require(revision.content == "# 日程" && revision.sha == sha, "GitHub reads need content and baseline SHA")
    let get = await transport.request
    require(get?.url?.host == "api.github.com", "Credentials must only target GitHub API")
    require(URLComponents(url: get!.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "sync/test", "Selected branch must survive URL encoding")
    require(get?.url?.path.contains("日程/执行文件.md") == true, "Unicode file paths must roundtrip")

    await transport.set(data: try JSONSerialization.data(withJSONObject: ["content": ["sha": String(repeating: "b", count: 40)]]), status: 200)
    _ = try await client.write(content: "# 更新日程", expectedSHA: sha)
    let put = await transport.request
    let body = try JSONSerialization.jsonObject(with: put!.httpBody!) as! [String: Any]
    require(put?.httpMethod == "PUT" && body["sha"] as? String == sha, "Writes must send the baseline SHA")
    require(body["branch"] as? String == "sync/test", "Writes must stay on configured branch")
    require(Data(base64Encoded: body["content"] as! String) == Data("# 更新日程".utf8), "Write content must be lossless base64")
    await transport.set(data: Data("test-credential must not appear in error".utf8), status: 409)
    do { _ = try await client.write(content: "x", expectedSHA: sha); fatalError("Version conflict must reject write") }
    catch V2GitHubScheduleError.conflict {}
    for path in ["../secret.md", "/absolute.md", ".github/workflows/test.yml", "folder//x.md"] {
        let invalid = V2GitHubScheduleLocation(owner: "example", repository: "repo", branch: "main", path: path)
        do { _ = try V2GitHubScheduleClient(location: invalid, token: "x", transport: transport).makeReadRequest(); fatalError("Invalid path accepted") }
        catch V2GitHubScheduleError.invalidLocation {}
    }
}

private actor GitHubScheduleTransport: V2PlanningHTTPTransport {
    var data: Data
    var status: Int
    var request: URLRequest?
    init(data: Data, status: Int) { self.data = data; self.status = status }
    func set(data: Data, status: Int) { self.data = data; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
