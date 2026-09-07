// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit
import SwiftMediaMetadata

func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
func jsonDigest(_ value: Any) throws -> String {
    digest(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
}
func reflectedDigest<T>(_ value: T) -> String {
    digest(Data(String(reflecting: value).utf8))
}
var result: [String: Any]
do {
    guard CommandLine.arguments.count == 3 else { throw NSError(domain: "ProbeArguments", code: 1) }
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    switch CommandLine.arguments[1] {
    case "metadata":
        let metadata = try VideoMetadata.read(from: url)
        let fields = VideoMetadataExporter.buildDictionary(metadata)
        guard !fields.isEmpty else { throw NSError(domain: "EmptyMetadataExport", code: 1) }
        result = ["metadataSHA256": try jsonDigest(fields), "exportedFieldCount": fields.count,
                  "format": metadata.format.rawValue, "hasRTMD": metadata.rtmd != nil,
                  "videoStreamCount": metadata.videoStreams.count, "audioStreamCount": metadata.audioStreams.count]
    case "rtmd":
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard RTMDReader.hasRTMDTrack(in: data) else { throw NSError(domain: "MissingRTMDTrack", code: 1) }
        let frames = try RTMDReader.readAttributes(from: data)
        let gyro = try RTMDReader.readMotionSamples(from: data, stream: .gyroscope)
        let acceleration = try RTMDReader.readMotionSamples(from: data, stream: .accelerometer)
        let first = RTMDReader.firstFrameSnapshot(from: data)
        guard let first, !frames.isEmpty, first == frames.first else {
            throw NSError(domain: "MissingOrInconsistentRTMDFrame", code: 1)
        }
        result = ["hasRTMD": true, "frameCount": frames.count,
                  "firstFrameSHA256": reflectedDigest(first),
                  "allFramesSHA256": try jsonDigest(frames.map { String(reflecting: $0) }),
                  "gyroscopeCount": gyro.count, "gyroscopeSHA256": try jsonDigest(gyro.map { String(reflecting: $0) }),
                  "accelerometerCount": acceleration.count,
                  "accelerometerSHA256": try jsonDigest(acceleration.map { String(reflecting: $0) }),
                  "imuRate": RTMDReader.estimateIMUSampleRate(in: data) as Any? ?? NSNull()]
    default: throw NSError(domain: "ProbeMode", code: 1)
    }
} catch {
    // Keep camera serials, GPS, timestamps and other personal metadata out of logs.
    result = ["errorType": String(reflecting: type(of: error)), "errorSHA256": reflectedDigest(error)]
}
let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: output, as: UTF8.self))
if result["errorType"] != nil { exit(1) }
