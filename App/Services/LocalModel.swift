import Foundation
import CryptoKit
import Combine

final class LocalModel: @unchecked Sendable {
    static let shared = LocalModel()
    private init() {}
    static let size: Int64 = 1_117_320_736
    static let hash = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    private let queue = DispatchQueue(label:"cn.local.assistant.qwen",qos:.userInitiated)
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var current: UInt64 = 0
    private var lastActive = Date()
    var file: URL { get throws { try PrivateFiles.url("qwen2.5-1.5b-q4_k_m.gguf") } }
    var available: Bool { guard let file = try? file, let attributes = try? FileManager.default.attributesOfItem(atPath:file.path), let size = attributes[.size] as? NSNumber else { return false }; return size.int64Value == Self.size }
    static let companionSize: Int64 = 986_048_064
    static let companionHash = "07fcb0fdd9a9e116f3ddb0926a5f9059fc8f9e3369f6455b80397cab562c4f4f"
    var companionFile: URL? {
        guard let url = Bundle.main.url(forResource:"CompanionModel",withExtension:"gguf"),
              let attributes = try? FileManager.default.attributesOfItem(atPath:url.path),
              (attributes[.size] as? NSNumber)?.int64Value == Self.companionSize else { return nil }
        return url
    }
    var companionAvailable: Bool { companionFile != nil }
    func cancel() { lock.lock(); let id = current; lock.unlock(); if id > 0 { pa_cancel(id) } }
    func release() { queue.async { pa_release() } }
    func install(_ source: URL, progress: @Sendable (Double)->Void = {_ in}) throws {
        let size = try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size == Self.size else { throw AppError.message("请选择 Qwen2.5-1.5B Q4_K_M 的完整 GGUF 文件（约 1.12 GB）") }
        let handle = try FileHandle(forReadingFrom:source); defer { try? handle.close() }
        var digest = SHA256(); var received: Int64 = 0
        while let data = try handle.read(upToCount:1024*1024), !data.isEmpty { try Task.checkCancellation(); digest.update(data:data); received += Int64(data.count); progress(Double(received)/Double(Self.size)) }
        guard digest.finalize().map({String(format:"%02x",$0)}).joined() == Self.hash else { throw AppError.message("模型校验不一致，请重新下载原始 Q4_K_M 文件") }
        let destination = try file, staging = destination.appendingPathExtension("install")
        try? FileManager.default.removeItem(at:staging); try FileManager.default.copyItem(at:source,to:staging)
        if FileManager.default.fileExists(atPath:destination.path) { _ = try FileManager.default.replaceItemAt(destination,withItemAt:staging) } else { try FileManager.default.moveItem(at:staging,to:destination) }
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:destination.path)
        release()
    }
    func remove() async throws {
        cancel()
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            queue.async { do { pa_release(); try FileManager.default.removeItem(at:self.file); continuation.resume() } catch { continuation.resume(throwing:error) } }
        }
    }
    func generate(system: String, input: String, maxTokens: Int = 640) async throws -> String {
        guard available else { throw AppError.message("尚未安装本机模型，请到个人详情 → 本机智能下载或导入") }
        let clean = input.replacingOccurrences(of:"<|",with:"＜｜").replacingOccurrences(of:"|>",with:"｜＞")
        let prompt = "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(clean)<|im_end|>\n<|im_start|>assistant\n"
        return try await generatePrompt(prompt,at:try file,maxTokens:maxTokens)
    }
    /// All model variants share one native queue, model cache and cancellation sequence.
    func companion(system:String, history:[CompanionMessage], input:String, maxTokens:Int = 240) async throws -> String {
        guard let file=companionFile else {throw AppError.message("此安装包缺少伙伴模型，请安装完整的内部研究版")}
        let prompt=CompanionRules.prompt(system:system,history:history,input:input)
        return try await generatePrompt(prompt,at:file,maxTokens:maxTokens)
    }
    private func generatePrompt(_ prompt:String,at file:URL,maxTokens:Int) async throws -> String {
        lock.lock(); sequence += 1; let id = sequence; current = id; lock.unlock()
        let output: String = try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard let result = pa_generate(file.path,prompt,Int32(maxTokens),id) else { continuation.resume(throwing:AppError.message(String(cString:pa_error()))); return }
                    let text = String(cString:result); pa_free(result); self.lastActive = Date()
                    self.queue.asyncAfter(deadline:.now()+120) { if Date().timeIntervalSince(self.lastActive)>=119 { pa_release() } }
                    continuation.resume(returning:text)
                }
            }
        },onCancel:{pa_cancel(id)})
        try Task.checkCancellation()
        return output
    }
}

@MainActor final class ModelDownload: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress = 0.0
    @Published var running = false
    @Published var stage = ""
    @Published var error: String?
    private var task: URLSessionDownloadTask?
    private var installTask: Task<Void,Never>?
    private var session: URLSession?
    private var attempt = 0
    private let urls = ["https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/qwen2.5-1.5b-instruct-q4_k_m.gguf","https://modelscope.cn/api/v1/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/repo?Revision=master&FilePath=qwen2.5-1.5b-instruct-q4_k_m.gguf","https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true"]
    func start() { guard !running else { return }; attempt = 0; running = true; error = nil; progress = 0; next() }
    private func next() {
        guard attempt < urls.count else { running = false; error = "模型下载失败，请稍后重试或导入 GGUF 文件"; return }
        stage = attempt == 0 ? "下载模型":"切换下载线路"
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 7200
        session = URLSession(configuration:config,delegate:self,delegateQueue:nil)
        task = session!.downloadTask(with:URL(string:urls[attempt])!); task?.resume(); attempt += 1
    }
    func cancel() { running = false; task?.cancel(); task = nil; installTask?.cancel(); session?.invalidateAndCancel(); stage = "" }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,totalBytesWritten: Int64,totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in self.progress = min(0.95,Double(totalBytesWritten)/Double(LocalModel.size)*0.95) }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200, response.url?.scheme == "https" else { Task { @MainActor in if self.running { self.next() } }; return }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".gguf")
        do { try FileManager.default.moveItem(at:location,to:staging) }
        catch { Task { @MainActor in self.error = "无法保存下载文件，请检查空间"; self.running = false }; return }
        Task { @MainActor in
            self.stage = "校验模型"
            self.installTask = Task {
                do {
                    try await Task.detached(priority:.utility) { try LocalModel.shared.install(staging) }.value
                    if self.running { self.progress = 1; self.stage = "已安装"; self.running = false }
                } catch { if self.running { self.error = error.localizedDescription; self.running = false } }
                try? FileManager.default.removeItem(at:staging)
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession,task: URLSessionTask,didCompleteWithError error: Error?) {
        if error != nil { Task { @MainActor in if self.running && self.installTask == nil { self.next() } } }
    }
}
