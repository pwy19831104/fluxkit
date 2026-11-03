import CommonCrypto
import Foundation

enum AESFixture {
    enum Failure: Error { case cryptFailed(Int32) }

    static func encrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outBuffer in
            data.withUnsafeBytes { inBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBuffer.baseAddress, key.count,
                                ivBuffer.baseAddress,
                                inBuffer.baseAddress, data.count,
                                outBuffer.baseAddress, outBuffer.count,
                                &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.cryptFailed(status) }
        return output.prefix(moved)
    }
}
