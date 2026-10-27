// Public-key verification only. No private keys, Keychain or network access.
import Foundation
import CryptoKit

do {
 guard CommandLine.arguments.count == 4,
       let rawKey = Data(base64Encoded:CommandLine.arguments[1]), rawKey.count == 32,
       let signature = Data(base64Encoded:CommandLine.arguments[2]), signature.count == 64 else { throw CocoaError(.fileReadCorruptFile) }
 let key = try Curve25519.Signing.PublicKey(rawRepresentation:rawKey)
 let content = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))
 guard key.isValidSignature(signature,for:content) else { throw CocoaError(.fileReadCorruptFile) }
 print("Verified Ed25519 signature")
} catch {
 FileHandle.standardError.write(Data("Ed25519 verification failed\n".utf8)); exit(1)
}
