// RFC 8032 test vector 1: public test data only, never a deployment credential.
import Foundation
import CryptoKit
let seed = Data(stride(from:0,to:64,by:2).map { offset in
 let hex = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
 let start=hex.index(hex.startIndex,offsetBy:offset)
 return UInt8(hex[start..<hex.index(start,offsetBy:2)],radix:16)!
})
let key = try Curve25519.Signing.PrivateKey(rawRepresentation:seed)
if CommandLine.arguments.count == 1 { print(key.publicKey.rawRepresentation.base64EncodedString()) }
else if CommandLine.arguments[1] == "fixture-key" {
 try seed.base64EncodedString().write(toFile:CommandLine.arguments[2],atomically:true,encoding:.utf8)
} else {
 let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
 print(try key.signature(for:data).base64EncodedString())
}
