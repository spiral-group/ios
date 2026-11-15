//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 items 16 and 17): how an animated update of the table lands.
//

/// The table's `.top` row animation suits a row arriving at the newest end, which comes in from under the composer. Any other
/// row it slides across its neighbours: "New", on its way out as you write, dropped past the rows below it, over a bubble.
/// So everything else lands in place first, and only what's arriving at the end slides in.
struct TimelineSnapshotSteps<ID: Hashable> {
    /// The rows to apply in place, in turn, before the final rows slide in. Newest first, as the table has them.
    let inPlace: [[ID]]
    /// The rows that are leaving, or moving elsewhere.
    let leaving: Set<ID>
    
    /// - Parameters:
    ///   - current: The table's rows, newest first.
    ///   - new: The rows it's to have, newest first.
    ///   - isVirtual: Whether a row is a date, "New" or the like, which belongs where it is and never slides.
    init(current: [ID], new: [ID], isVirtual: (ID) -> Bool) {
        let currentIDs = Set(current)
        let newIDs = Set(new)
        
        // What's new ahead of the first row already there has arrived at the end. Rows arriving anywhere else go in place.
        let arriving = Set(new.prefix { !currentIDs.contains($0) })
        let moved = Self.movedRows(current: current, new: new, newIDs: newIDs, currentIDs: currentIDs, isVirtual: isVirtual)
        
        var inPlace = [[ID]]()
        if !moved.isEmpty {
            inPlace.append(current.filter { newIDs.contains($0) && !moved.contains($0) })
        }
        let settled = new.filter { !arriving.contains($0) }
        if settled != inPlace.last ?? current {
            inPlace.append(settled)
        }
        
        self.inPlace = inPlace
        leaving = currentIDs.subtracting(newIDs).union(moved)
    }
    
    /// The virtual rows that sit beside another row than they did. Diffing would slide them there.
    private static func movedRows(current: [ID], new: [ID], newIDs: Set<ID>, currentIDs: Set<ID>, isVirtual: (ID) -> Bool) -> Set<ID> {
        let currentNeighbours = neighbours(in: current.filter(newIDs.contains), isVirtual: isVirtual)
        let newNeighbours = neighbours(in: new.filter(currentIDs.contains), isVirtual: isVirtual)
        return Set(currentNeighbours.keys.filter { currentNeighbours[$0] != newNeighbours[$0] })
    }
    
    /// Each virtual row with the first row after it that isn't one.
    private static func neighbours(in rows: [ID], isVirtual: (ID) -> Bool) -> [ID: ID?] {
        var neighbours = [ID: ID?]()
        var nextRow: ID?
        for row in rows.reversed() {
            if isVirtual(row) {
                neighbours[row] = .some(nextRow)
            } else {
                nextRow = row
            }
        }
        return neighbours
    }
}
