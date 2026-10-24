import UIKit
import ImageIO

enum ChatImageService {
    static func prepare(_ data:Data) throws -> ChatImage {
        guard data.count<=32*1024*1024,let source=CGImageSourceCreateWithData(data as CFData,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1600] as CFDictionary) else {throw AppError.message("图片无法读取或超过 32 MB，请换一张图片")}
        // Re-encode oriented pixels, omitting photo location and original metadata.
        let image=UIImage(cgImage:cg)
        for quality in [0.85,0.7,0.5] {
            if let jpeg=image.jpegData(compressionQuality:quality),jpeg.count<=ChatImage.maximumBytes {return try ChatImage(jpeg:jpeg).validated()}
        }
        throw AppError.message("图片压缩后仍过大，请裁剪后重试")
    }
}
