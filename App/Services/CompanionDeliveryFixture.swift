#if DEBUG
import Foundation

/// UI regression traverses the real service, attachment validation and encrypted commit pipeline.
final class CompanionDeliveryFixture:URLProtocol {
    override class func canInit(with request:URLRequest)->Bool {request.url?.host=="api.deepseek.com"}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        do {
            var bytes=request.httpBody ?? Data()
            if bytes.isEmpty,let stream=request.httpBodyStream {
                stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:2048)
                while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0 {break};bytes.append(buffer,count:n)}
            }
            let body=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],messages=body?["messages"] as? [[String:Any]] ?? []
            let system=messages.first?["content"] as? String ?? "",question=messages.last?["content"] as? String ?? ""
            let id=system.contains("男性AI伙伴") ? "male_hug":"hug",sticker=CompanionSticker.find(id)!
            let prefix=question.contains("用表情包") ? "好，这次也用抱抱图。":"来，抱一下。"
            var response:[String:Any]=["content":prefix+"\n[表情包："+sticker.description+"]"]
            if question.contains("天气") {
                let tools=body?["tools"] as? [[String:Any]] ?? []
                if tools.contains(where:{($0["function"] as? [String:Any])?["name"] as? String=="propose_companion_name"}) {
                    response=["tool_calls":[["index":0,"id":"stale-name","function":["name":"propose_companion_name","arguments":"{\"name\":\"大肥鱼\",\"quote\":\"大肥鱼\"}"]]]]
                } else {response=["content":"你想查哪座城市的天气？"]}
            }
            let delta:[String:Any]=["choices":[["delta":response]]]
            let json=try JSONSerialization.data(withJSONObject:delta),data=Data(("data: "+String(decoding:json,as:UTF8.self)+"\n\ndata: [DONE]\n\n").utf8)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"text/event-stream"])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
    static func client()->DeepSeekWebClient {let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[CompanionDeliveryFixture.self];return DeepSeekWebClient(apiKey:"ui-fixture-placeholder",configuration:config)}
}
#endif
