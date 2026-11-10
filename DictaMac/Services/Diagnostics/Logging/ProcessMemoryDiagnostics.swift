import Darwin
import Foundation
import OSLog

enum ProcessMemoryDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DictaMac",
        category: "Memory"
    )

    static func logFootprint(
        _ context: DiagnosticMemoryContext,
        diagnosticLog: any DiagnosticLogging
    ) {
        let bytes = physicalFootprint
        diagnosticLog.memory(context: context, bytes: bytes)
        guard let bytes else {
            logger.error("phys_footprint unavailable context=\(context.rawValue, privacy: .public)")
            return
        }
        logger.info(
            "phys_footprint context=\(context.rawValue, privacy: .public) bytes=\(bytes) mib=\(Double(bytes) / 1_048_576, format: .fixed(precision: 1))"
        )
    }

    static var physicalFootprint: UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
