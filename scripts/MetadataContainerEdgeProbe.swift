// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftMediaMetadata

func frame(_ value: RTMDFrameAttribute) -> [String: Any] {
    ["frameIndex": value.frameIndex, "timestamp": value.timestampSeconds,
     "iso": value.iso as Any? ?? NSNull(),
     "allFields": String(reflecting: value)]
}
func motion(_ value: RTMDMotionSample) -> [String: Any] {
    ["timestamp": value.timestampSeconds, "x": Int(value.x), "y": Int(value.y), "z": Int(value.z)]
}
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
var result: [String: Any] = ["hasRTMD": RTMDReader.hasRTMDTrack(in: data),
                            "imuRate": RTMDReader.estimateIMUSampleRate(in: data) as Any? ?? NSNull(),
                            "firstFrame": RTMDReader.firstFrameSnapshot(from: data).map(frame) as Any? ?? NSNull()]
do {
    result["frames"] = try RTMDReader.readAttributes(from: data).map(frame)
} catch {
    result["attributeError"] = String(describing: error)
}
do {
    result["gyroscope"] = try RTMDReader.readMotionSamples(from: data, stream: .gyroscope).map(motion)
} catch {
    result["gyroscopeError"] = String(describing: error)
}
do {
    result["accelerometer"] = try RTMDReader.readMotionSamples(from: data, stream: .accelerometer).map(motion)
} catch {
    result["accelerometerError"] = String(describing: error)
}
let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: json, as: UTF8.self))
