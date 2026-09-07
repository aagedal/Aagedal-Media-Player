// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone dependency probe; intentionally excludes the app and AVAsset.
import Foundation
import Darwin
import SwiftMediaMetadata

func emit(_ phase: String, extra: [String: Any] = [:]) throws {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { throw NSError(domain: "task_info", code: Int(status)) }
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    var result = extra
    result["phase"] = phase
    result["residentBytes"] = info.resident_size
    result["lifetimePeakResidentBytes"] = usage.ru_maxrss // bytes on Darwin
    let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: json, as: UTF8.self))
    fflush(stdout)
}
func value<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
let arguments = CommandLine.arguments
guard arguments.count == 3, ["read", "rtmd", "skip-mdat"].contains(arguments[1]) else {
    fatalError("Usage: metadata-memory-profiler read|rtmd|skip-mdat MEDIA_FILE")
}
let mode = arguments[1]
let url = URL(fileURLWithPath: arguments[2])
try emit("initial")
let start = ContinuousClock.now
try autoreleasepool {
    if mode == "read" {
        let metadata = try VideoMetadata.read(from: url)
        let snapshot: [String: Any] = [
            "format": metadata.format.rawValue, "duration": value(metadata.duration),
            "fileSize": value(metadata.fileSize), "bitRate": value(metadata.bitRate),
            "title": value(metadata.title), "comment": value(metadata.comment),
            "videoStreamCount": metadata.videoStreams.count,
            "subtitleStreamCount": metadata.subtitleStreams.count,
            "chapterCount": metadata.chapters.count, "hasRTMD": metadata.rtmd != nil,
            "audioStreams": metadata.audioStreams.map { stream -> [String: Any] in
                ["codec": value(stream.codec), "sampleRate": value(stream.sampleRate),
                 "channels": value(stream.channels), "bitDepth": value(stream.bitDepth),
                 "duration": value(stream.duration), "bitRate": value(stream.bitRate),
                 "channelLayout": value(stream.channelLayout)]
            }
        ]
        try withExtendedLifetime(metadata) { try emit("retained", extra: ["metadata": snapshot]) }
    } else {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        try emit("mapped")
        if mode == "rtmd" {
            let found = RTMDReader.hasRTMDTrack(in: data)
            try withExtendedLifetime(data) { try emit("probed", extra: ["hasRTMD": found]) }
        } else {
            let boxes = try ISOBMFFBoxReader.parseTopLevelBoxesSkippingMdat(data)
            try withExtendedLifetime((data, boxes)) {
                try emit("probed", extra: ["boxTypes": boxes.map(\.type), "payloadBytes": boxes.reduce(0) { $0 + $1.data.count }])
            }
        }
    }
}
let elapsed = start.duration(to: .now).components
try emit("released", extra: ["wallSeconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18])
