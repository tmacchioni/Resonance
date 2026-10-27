import CryptoKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let privateFile = root.appendingPathComponent(".private/sparkle-private-key")
let publicFile = root.appendingPathComponent("Config/UpdatePublicKey.txt")
guard !FileManager.default.fileExists(atPath: privateFile.path), !FileManager.default.fileExists(atPath: publicFile.path) else {
    print("Signing key already exists. It will not be replaced.")
    exit(1)
}
try FileManager.default.createDirectory(at: privateFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let key = Curve25519.Signing.PrivateKey()
try (key.rawRepresentation.base64EncodedString() + "\n").write(to: privateFile, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateFile.path)
try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(to: publicFile, atomically: true, encoding: .utf8)
print("Public key written to Config/UpdatePublicKey.txt. Private key saved in excluded .private directory.")
