import XCTest
@testable import PersonalAssistant

final class VaultCapacityTests:XCTestCase {
    func testCapacityBoundaryAndAccurateError() throws {
        let key=Data(repeating:1,count:32),salt=Data(repeating:2,count:32)
        let plain=Data(repeating:0,count:VaultCrypto.maximumPlaintext)
        let encrypted=try VaultCrypto.encrypt(plain,key:key,salt:salt)
        XCTAssertEqual(encrypted.count,VaultCrypto.maximum)
        XCTAssertEqual(try VaultCrypto.decrypt(encrypted,key:key),plain)
        XCTAssertThrowsError(try VaultCrypto.encrypt(plain+Data([0]),key:key,salt:salt)) {error in
            XCTAssertTrue(error.localizedDescription.contains("容量不足"))
            XCTAssertTrue(error.localizedDescription.contains("原有资料未改动"))
        }
    }
    func testInvalidKeyHasDistinctError() {
        XCTAssertThrowsError(try VaultCrypto.encrypt(Data(),key:Data(),salt:Data(repeating:2,count:32))) {error in
            XCTAssertTrue(error.localizedDescription.contains("解锁密钥无效"))
            XCTAssertFalse(error.localizedDescription.contains("容量不足"))
        }
    }
}
