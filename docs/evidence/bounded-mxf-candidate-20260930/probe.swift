import Foundation
import Darwin
import SwiftMediaMetadata

// Standalone library probe. This does not run the app's MetadataService cache.
func memoryObservation() throws -> [String: UInt64] {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { throw NSError(domain: NSMachErrorDomain, code: Int(status)) }
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    return ["residentBytes": UInt64(info.resident_size), "lifetimePeakResidentBytes": UInt64(usage.ru_maxrss)]
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let before = try memoryObservation()
let start = ContinuousClock.now
var metadata: VideoMetadata? = try autoreleasepool { try VideoMetadata.read(from: url) }
let elapsed = start.duration(to: .now)
let afterLoad = try memoryObservation()
let exporter = VideoMetadataExporter.buildDictionary(metadata!)
let row: [String: Any] = [
    "path": url.path,
    "wallSeconds": Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
    "before": before, "afterLoad": afterLoad,
    "exporter": exporter,
]
metadata = nil
var result = row
result["afterRelease"] = try memoryObservation()
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
