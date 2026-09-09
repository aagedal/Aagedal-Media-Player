// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit
import SwiftMediaMetadata

// This diagnostic deliberately leaves the upstream real-file assertions intact.
let original = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let parsed = try JXLParser.parse(original)
let streams = parsed.boxes.filter { $0.type == "jxlc" }
guard parsed.isContainer, streams.count == 1,
      !parsed.boxes.contains(where: { $0.type == "jxlp" }),
      let bare = streams.first?.data, bare.starts(with: [0xff, 0x0a]) else {
    throw NSError(domain: "JXLFixtureProbe", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Expected one complete jxlc codestream in the fixture container"])
}
let metadata = try ImageMetadata.read(from: original)
let containerWritten = try metadata.writeToData()
let containerReparsed = try JXLParser.parse(containerWritten)
let bareMetadata = try ImageMetadata.read(from: bare)
let bareWritten = try bareMetadata.writeToData()
var edited = bareMetadata
edited.setOrientation(6)
let wrapped = try edited.writeToData()
let reparsed = try JXLParser.parse(wrapped)
let editedMetadata = try ImageMetadata.read(from: wrapped)
func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
let result: [String: Any] = [
    "fixtureSHA256": hash(original), "codestreamSHA256": hash(bare),
    "fixtureBytes": original.count, "codestreamBytes": bare.count,
    "boxTypes": parsed.boxes.map(\.type),
    "containerWriteSucceeds": true,
    "containerPreservesCodestream": containerReparsed.findBox("jxlc")?.data == bare,
    "bareWriteSucceeds": true, "bareWritePreservesBytes": bareWritten == bare,
    "editedBareWrapsOnce": reparsed.isContainer && reparsed.boxes.filter { $0.type == "jxlc" }.count == 1,
    "editedBarePreservesCodestream": reparsed.findBox("jxlc")?.data == bare,
    "editedBareOrientationRoundTrips": editedMetadata.exif?.orientation == 6,
]
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
