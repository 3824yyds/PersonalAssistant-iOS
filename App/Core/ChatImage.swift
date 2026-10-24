import Foundation

/// JPEG thumbnails are kept inside encrypted chat history; no public upload URL is created.
public struct ChatImage:Codable,Identifiable,Equatable,Sendable {
    public var id:String
    public var jpeg:Data
    public static let maximumCount=4
    public static let maximumBytes=1_500_000
    public init(id:String=UUID().uuidString.lowercased(),jpeg:Data) {self.id=id;self.jpeg=jpeg}
    public func validated() throws -> ChatImage {
        guard jpeg.count>3,jpeg.count<=Self.maximumBytes,jpeg.starts(with:[0xff,0xd8,0xff]) else {throw AppError.message("图片格式或大小无效，请重新选择图片")}
        return self
    }
    public static func content(_ text:String,images:[ChatImage]) throws -> Any {
        guard images.count<=maximumCount else {throw AppError.message("每条消息最多选择 4 张图片")}
        if images.isEmpty {return text}
        var blocks:[[String:Any]]=[["type":"text","text":text]]
        for image in images {
            _=try image.validated()
            blocks.append(["type":"image_url","image_url":["url":"data:image/jpeg;base64,"+image.jpeg.base64EncodedString(),"detail":"auto"]])
        }
        return blocks
    }
}
