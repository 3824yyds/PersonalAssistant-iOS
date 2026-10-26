import XCTest
import UIKit
import ImageIO
@testable import PersonalAssistant

final class PINAndAttachmentTests:XCTestCase {
    func testPINEncryptionRoundTripAndWrongPINRejects() throws {
        let salt=try VaultCrypto.random(32),key=try VaultCrypto.derive(password:"0426",salt:salt)
        let payload=Data("四位PIN资料".utf8),encrypted=try VaultCrypto.encrypt(payload,key:key,salt:salt)
        XCTAssertEqual(encrypted[7],2);XCTAssertEqual(try VaultCrypto.decrypt(encrypted,key:VaultCrypto.derive(password:"0426",salt:VaultCrypto.salt(encrypted))),payload)
        XCTAssertThrowsError(try VaultCrypto.decrypt(encrypted,key:VaultCrypto.derive(password:"9999",salt:salt)))
        for value in ["123","12345","123456789012","１２３４","abcd"] {XCTAssertThrowsError(try VaultCrypto.derive(password:value,salt:salt))}
    }
    func testPhotoPreparationBoundsPixelsAndPreservesTransparentPNG() throws {
        let format=UIGraphicsImageRendererFormat();format.opaque=false;format.scale=1
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:1400,height:1000),format:format)
        let original=renderer.image {c in UIColor.systemBlue.setFill();c.fill(CGRect(x:100,y:100,width:1000,height:600))}.pngData()!
        let prepared=try CompanionStickerPhoto.prepare(original),source=try XCTUnwrap(CGImageSourceCreateWithData(prepared as CFData,nil))
        let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any])
        XCTAssertLessThanOrEqual((properties[kCGImagePropertyPixelWidth as String] as? Int) ?? 9999,512)
        XCTAssertLessThanOrEqual((properties[kCGImagePropertyPixelHeight as String] as? Int) ?? 9999,512)
        XCTAssertLessThanOrEqual(prepared.count,CompanionCustomSticker.maximumBytes)
        XCTAssertTrue(prepared.starts(with:[137,80,78,71]));XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let sticker=CompanionCustomSticker(title:"蓝色图",meaning:"开心",image:prepared)
        XCTAssertNotNil(CompanionStickerPhoto.thumbnail(sticker))
    }
    func testUnreadableAndOversizedPhotoRejectsWithoutCreatingSticker() {
        XCTAssertThrowsError(try CompanionStickerPhoto.prepare(Data("not an image".utf8)))
        XCTAssertThrowsError(try CompanionStickerPhoto.prepare(Data(repeating:0,count:32*1024*1024+1)))
    }
    func testCustomImageAndQuoteAreEncryptedAndRestoreWithFreshPIN() throws {
        let image=UIImage(named:"CompanionAvatar")!.pngData()!,prepared=try CompanionStickerPhoto.prepare(image)
        var state=CompanionData();let sticker=CompanionCustomSticker(title:"私有表情",meaning:"只表达关心",image:prepared)
        try state.addSticker(sticker)
        let original=CompanionMessage(role:"assistant",content:"周六去哪里？",stickerID:sticker.id,stickerMeaning:sticker.descriptor.description);state.messages=[original]
        _=try CompanionRules.appendUserTurn("这条我想再聊聊",to:&state,replyTo:CompanionQuote.snapshot(original,data:state))
        var document=Document();try state.write(to:&document)
        let salt=try VaultCrypto.random(32),key=try VaultCrypto.derive(password:"0007",salt:salt)
        let encrypted=try VaultCrypto.encrypt(document.encoded(),key:key,salt:salt)
        XCTAssertFalse(String(decoding:encrypted,as:UTF8.self).contains("私有表情"))
        let restored=try CompanionData.read(JSONDecoder().decode(Document.self,from:VaultCrypto.decrypt(encrypted,key:key)))
        XCTAssertEqual(state,restored)
        let messages=CompanionConversation.messages(question:"继续",data:state,history:state.messages)
        XCTAssertFalse(String(describing:messages).contains(prepared.base64EncodedString()))
    }
}
