import Foundation
import CryptoKit
import CommonCrypto
import Security
import LocalAuthentication

enum VaultCrypto {
    static let maximum = 32*1024*1024, rounds: UInt32 = 600_000
    static let overhead = 72
    static var maximumPlaintext:Int {maximum-overhead}
    static func capacityLabel(_ bytes:Int)->String {ByteCountFormatter.string(fromByteCount:Int64(max(0,bytes)),countStyle:.binary)}
    static let magic = Data([0x50,0x41,0x56,0x41,0x55,0x4c,0x54,0x01])
    static func random(_ count: Int) throws -> Data {
        var bytes = Data(count:count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault,count,$0.baseAddress!) }
        guard status == errSecSuccess else { throw AppError.message("无法生成安全随机数，请重新启动应用") }; return bytes
    }
    static func salt(_ envelope: Data) throws -> Data {
        guard (72...maximum).contains(envelope.count), envelope.prefix(8) == magic, Array(envelope[8..<12]) == [0,9,39,192] else { throw AppError.message("备份格式不支持，请选择原生 .pavault 完整备份") }
        return envelope.subdata(in:12..<44)
    }
    static func derive(password: String, salt: Data) throws -> Data {
        guard password.utf16.count >= 12, password.utf8.count <= 1024, salt.count == 32 else { throw AppError.message("备份密码至少 12 个字符，最多 1024 字节") }
        var output = Data(count:32)
        let pass = Array(password.utf8)
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                pass.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),passBytes.baseAddress!.assumingMemoryBound(to:CChar.self),pass.count,saltBytes.baseAddress!.assumingMemoryBound(to:UInt8.self),salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),rounds,out.baseAddress!.assumingMemoryBound(to:UInt8.self),32)
                }
            }
        }
        guard status == kCCSuccess else { throw AppError.message("密钥派生失败") }; return output
    }
    static func encrypt(_ plain: Data, key: Data, salt: Data) throws -> Data {
        guard plain.count <= maximumPlaintext else { throw AppError.message("资料库容量不足：本次保存需要 \(capacityLabel(plain.count+overhead))，上限为 \(capacityLabel(maximum))。原有资料未改动，请先导出备份，再清理不需要的附件或缩小图片后重试。") }
        guard key.count == 32, salt.count == 32 else { throw AppError.message("解锁密钥无效，请重新解锁资料库") }
        let nonce = try random(12), header = magic + Data([0,9,39,192]) + salt + nonce
        let sealed = try AES.GCM.seal(plain,using:SymmetricKey(data:key),nonce:AES.GCM.Nonce(data:nonce),authenticating:header)
        return header + sealed.ciphertext + sealed.tag
    }
    static func decrypt(_ envelope: Data, key: Data) throws -> Data {
        _ = try salt(envelope)
        guard key.count == 32 else { throw AppError.message("解锁密钥无效") }
        do {
            let box = try AES.GCM.SealedBox(nonce:AES.GCM.Nonce(data:envelope.subdata(in:44..<56)),ciphertext:envelope.subdata(in:56..<(envelope.count-16)),tag:envelope.suffix(16))
            return try AES.GCM.open(box,using:SymmetricKey(data:key),authenticating:envelope.prefix(56))
        } catch { throw AppError.message("密码不正确或备份已损坏，请核对后重试") }
    }
}

enum Keychain {
    static var service: String { Bundle.main.bundleIdentifier ?? "cn.local.assistant.ios" }
    static func save(_ data: Data, name: String, biometric: Bool = false) throws {
        var query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:name,kSecValueData as String:data]
        if biometric {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenUnlockedThisDeviceOnly,.userPresence,&error) else { throw AppError.message("设备身份认证不可用") }
            query[kSecAttrAccessControl as String] = access
        } else { query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let old: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:name]
        SecItemDelete(old as CFDictionary)
        guard SecItemAdd(query as CFDictionary,nil) == errSecSuccess else { throw AppError.message("无法保存到系统钥匙串") }
    }
    static func read(_ name: String, prompt: String? = nil) throws -> Data? {
        var query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:name,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        if let prompt {let context=LAContext();context.localizedReason=prompt;query[kSecUseAuthenticationContext as String]=context}
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AppError.message("系统认证未完成，请使用资料库密码解锁") }; return result as? Data
    }
    static func delete(_ name: String) { SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:name] as CFDictionary) }
}

enum PrivateFiles {
    static func directory() throws -> URL {
        var url = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("Vault",isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values); return url
    }
    static func url(_ name: String = "notes.pavault") throws -> URL { try directory().appendingPathComponent(name) }
    static func write(_ data: Data, name: String = "notes.pavault") throws {
        let url = try url(name)
        if name == "notes.pavault", let old = try? Data(contentsOf:url), !old.isEmpty { try old.write(to:try self.url("previous.pavault"),options:[.atomic,.completeFileProtection]) }
        try data.write(to:url,options:[.atomic,.completeFileProtection])
        guard try Data(contentsOf:url) == data else { throw AppError.message("保存没有完成，请检查存储空间") }
    }
    static func boundedRead(_ url: URL, maximum: Int = VaultCrypto.maximum) throws -> Data {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? maximum+1
        guard size <= maximum else { throw AppError.message("文件过大，请分批处理") }
        let data = try Data(contentsOf:url,options:.mappedIfSafe)
        guard data.count <= maximum else { throw AppError.message("文件过大") }; return data
    }
}
