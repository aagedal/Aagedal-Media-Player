// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

/// libmpv may reorder async calls. Submit the next transport command only
/// after the previous command's reply; owned by MPVPlayer's event queue.
nonisolated struct MPVCommandQueue {
    struct Command: Equatable {
        let id: UInt64
        let arguments: [String]
    }

    private(set) var inFlight: Command?
    private var pending: [Command] = []
    private var nextID: UInt64 = 0

    mutating func enqueue(arguments: [String], id: UInt64 = 0) -> Command? {
        let commandID: UInt64
        if id == 0 {
            nextID &+= 1
            commandID = (1 << 62) | nextID
        } else {
            commandID = id
        }
        pending.append(Command(id: commandID, arguments: arguments))
        return takeNext()
    }

    mutating func completed(id: UInt64) -> Command? {
        guard inFlight?.id == id else { return nil }
        inFlight = nil
        return takeNext()
    }

    mutating func discardPending() { pending.removeAll() }

    mutating func reset() {
        discardPending()
        inFlight = nil
    }

    private mutating func takeNext() -> Command? {
        guard inFlight == nil, !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        inFlight = next
        return next
    }
}
