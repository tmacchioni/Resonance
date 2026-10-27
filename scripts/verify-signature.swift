import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
      let key = Data(base64Encoded: try String(contentsOfFile: args[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)),
      let signature = Data(base64Encoded: args[3]) else { exit(2) }
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
let file = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
guard publicKey.isValidSignature(signature, for: file) else { print("Invalid update signature"); exit(1) }
print("Update signature verified with the app's public key")
