import UIKit
import ImageIO

enum CompanionStickerPhoto {
    private static let cache=NSCache<NSString,UIImage>()
    static func prepare(_ data:Data) throws -> Data {
        guard data.count<=32*1024*1024,let source=CGImageSourceCreateWithData(data as CFData,nil) else {throw AppError.message("照片无法读取或超过32MB，请换一张")}
        for size in [512,384,256] {
            guard let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:size] as CFDictionary) else {throw AppError.message("请选择有效的照片或透明图片")}
            let image=UIImage(cgImage:cg)
            let alpha=[CGImageAlphaInfo.first,.last,.premultipliedFirst,.premultipliedLast].contains(cg.alphaInfo)
            if alpha {
                if let png=image.pngData(),png.count<=CompanionCustomSticker.maximumBytes {return png}
            } else {
                for quality in [0.85,0.65] {if let jpeg=image.jpegData(compressionQuality:quality),jpeg.count<=CompanionCustomSticker.maximumBytes {return jpeg}}
            }
        }
        throw AppError.message("图片压缩后仍较大，请裁剪后再添加")
    }
    static func thumbnail(_ sticker:CompanionCustomSticker)->UIImage? {
        if let image=cache.object(forKey:sticker.id as NSString) {return image}
        guard let source=CGImageSourceCreateWithData(sticker.image as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:512] as CFDictionary) else {return nil}
        let image=UIImage(cgImage:cg);cache.totalCostLimit=16*1024*1024;cache.setObject(image,forKey:sticker.id as NSString,cost:cg.width*cg.height*4);return image
    }
}
