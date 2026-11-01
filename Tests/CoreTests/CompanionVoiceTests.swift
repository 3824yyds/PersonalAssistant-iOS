import XCTest
@testable import AssistantCore

final class CompanionVoiceTests:XCTestCase {
    func testOldVaultKeepsTextModeAndOptionalVoiceFieldsRoundTrip() throws {
        var d=Document();var data=CompanionData();data.messages=[CompanionMessage(role:"assistant",content:"我在呢。")];try data.write(to:&d)
        XCTAssertEqual(try CompanionData.read(d).profile.voiceMode,.text)
        XCTAssertEqual(try CompanionVoiceSettings.read(d),CompanionVoiceSettings())
        data.profile.voiceReply = .voice;data.messages[0].voiceRequested=true;try data.write(to:&d)
        let decoded=try JSONDecoder().decode(Document.self,from:d.encoded()).validated()
        XCTAssertEqual(try CompanionData.read(decoded),data)
    }
    func testVoiceSettingsValidateBothIdentitiesAndRateWithoutPersistingSecrets() throws {
        var d=Document(),config=CompanionVoiceSettings();config.female="Serena";config.male="Moon";config.rate=0.9;config.autoPlay=true;try config.write(to:&d)
        XCTAssertEqual(try CompanionVoiceSettings.read(d),config);XCTAssertEqual(config.voice(for:.female),"Serena");XCTAssertEqual(config.voice(for:.male),"Moon")
        config.rate = .nan;XCTAssertThrowsError(try config.write(to:&d))
        config.rate=1;config.male="Cherry";XCTAssertThrowsError(try config.write(to:&d))
        XCTAssertFalse(String(decoding:try d.encoded(),as:UTF8.self).contains("API"))
    }
    func testSpokenTextRemovesMarkupLinksAndEmojiButKeepsNumbersAndMeaning() {
        let text="群发言者：female\n**今天** 15:30见😊。[天气](https://example.com/a) [1]\n- 带伞。"
        XCTAssertEqual(CompanionVoiceText.clean(text),"今天 15:30见。天气 \n带伞。")
    }
    func testSplittingPreservesCompleteTextAndNeverExceedsProviderLimit() throws {
        let text=String(repeating:"今天要做的事情，我们一件一件来。",count:80)
        let parts=try CompanionVoiceText.parts(text)
        XCTAssertEqual(parts.joined(),text);XCTAssertTrue(parts.allSatisfy {$0.unicodeScalars.count<=450});XCTAssertGreaterThan(parts.count,1)
        XCTAssertThrowsError(try CompanionVoiceText.parts(String(repeating:"长",count:1801)))
        XCTAssertThrowsError(try CompanionVoiceText.parts("😊🤣"))
    }
    func testVoiceFlagsCannotBeAssignedToHumanMessages() throws {
        var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:"你好",voiceRequested:true)]
        XCTAssertThrowsError(try data.validate())
    }
    func testPrivateAndRoomReplyModeStayIndependent() throws {
        var d=Document(),female=CompanionData();female.profile.voiceReply = .both;try female.write(to:&d)
        let group=try CompanionDirectory.create(name:"工作室",members:[.female,.male],in:&d)
        XCTAssertEqual(group.data.profile.voiceMode,.text)
        XCTAssertEqual(try CompanionDirectory.read(.direct(.male),in:d).profile.voiceMode,.text)
        XCTAssertEqual(try CompanionDirectory.read(.direct(.female),in:d).profile.voiceMode,.both)
    }
}
