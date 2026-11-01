import Foundation

/// Official Qwen TTS API only. No demo scraping, system voice fallback, or chat credentials.
struct CompanionVoiceService {
    static let endpoint=URL(string:"https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation")!
    static let maximumBytes=8*1024*1024
    let credential:String
    var session:URLSession
    init(credential:String,session:URLSession = .shared) {self.credential=credential;self.session=session}
    static func request(text:String,voice:String,credential:String) throws -> URLRequest {
        guard !credential.isEmpty,credential.count<=4096,!credential.contains("\n"),!credential.contains("\r") else {throw AppError.message("请在伙伴语音设置填写阿里云百炼 API Key")}
        guard (CompanionVoiceSettings.femaleVoices+CompanionVoiceSettings.maleVoices).contains(voice),!text.isEmpty,text.unicodeScalars.count<=600 else {throw AppError.message("音色或语音文本无效")}
        var request=URLRequest(url:endpoint);request.httpMethod="POST";request.timeoutInterval=45
        request.setValue("Bearer "+credential,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["model":"qwen3-tts-flash","input":["text":text,"voice":voice,"language_type":"Chinese"]])
        return request
    }
    static func audioURL(_ value:String) throws -> URL {
        guard var parts=URLComponents(string:value),parts.user==nil,parts.password==nil,parts.port==nil,
              ["http","https"].contains(parts.scheme?.lowercased() ?? ""),let host=parts.host?.lowercased(),
              host.hasPrefix("dashscope-result-"),host.hasSuffix(".aliyuncs.com"),host.contains(".oss-"),!host.contains("..") else {throw AppError.message("语音服务返回了无法验证的下载地址")}
        parts.scheme="https"
        guard let url=parts.url else {throw AppError.message("语音下载地址无效")};return url
    }
    static func failure(_ status:Int)->AppError {
        switch status {
        case 401,403:return .message("语音密钥无效或服务未开通，请在语音设置检查北京地域百炼 API Key 和语音服务权限")
        case 402:return .message("语音免费额度或余额不足，请检查百炼控制台；文字回复已保留")
        case 429:return .message("语音服务暂时繁忙或额度受限，请稍后点按重试；文字回复已保留")
        default:return .message("语音生成未完成，请检查网络、服务开通状态和额度后重试；文字回复已保留")
        }
    }
    private func load(_ request:URLRequest) async throws -> Data {
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode) else {throw Self.failure((response as? HTTPURLResponse)?.statusCode ?? 0)}
        if response.expectedContentLength>Int64(Self.maximumBytes) {throw AppError.message("语音文件过大，已停止下载")}
        var data=Data();data.reserveCapacity(64*1024)
        for try await byte in bytes {
            if data.count%8192==0 {try Task.checkCancellation()}
            guard data.count<Self.maximumBytes else {throw AppError.message("语音文件过大，已停止下载")};data.append(byte)
        }
        try Task.checkCancellation();return data
    }
    func synthesize(_ text:String,voice:String) async throws -> [Data] {
        var clips:[Data]=[]
        for part in try CompanionVoiceText.parts(text) {
            try Task.checkCancellation()
            let raw=try await load(Self.request(text:part,voice:voice,credential:credential))
            guard let object=try JSONSerialization.jsonObject(with:raw) as? [String:Any],
                  (object["code"] as? String ?? "").isEmpty,
                  (object["status_code"] as? Int ?? 200)==200,
                  let output=object["output"] as? [String:Any],let audio=output["audio"] as? [String:Any],
                  let address=audio["url"] as? String else {throw Self.failure(0)}
            // Use the complete WAV, never intermediate raw PCM or a signed URL stored in the vault.
            var request=URLRequest(url:try Self.audioURL(address));request.timeoutInterval=45
            let data=try await load(request)
            guard data.count>44,data.starts(with:Data("RIFF".utf8)),data.subdata(in:8..<12)==Data("WAVE".utf8) else {throw AppError.message("语音文件不完整，请重试；文字回复已保留")}
            guard clips.reduce(0,{$0+$1.count})+data.count<=Self.maximumBytes else {throw AppError.message("这条语音文件较大，请先查看文字")}
            clips.append(data)
        }
        return clips
    }
}

final class CompanionVoiceNetworkPolicy:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {completionHandler(nil)}
    static func session()->URLSession {
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=45;config.timeoutIntervalForResource=120;config.urlCache=nil;config.httpCookieStorage=nil
        return URLSession(configuration:config,delegate:CompanionVoiceNetworkPolicy(),delegateQueue:nil)
    }
}
