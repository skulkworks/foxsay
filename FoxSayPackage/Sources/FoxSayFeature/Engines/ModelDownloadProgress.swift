import Foundation
import os

/// The download progress of one model, written by whichever download library is
/// doing the work and read by the UI.
///
/// Two things this has to get right, both of them learned from a user watching a
/// 450 MB Parakeet download sit at 80% for ten minutes:
///
/// 1. **It is written from an arbitrary queue.** FluidAudio and WhisperKit both
///    call their progress handlers from wherever the download happens to be
///    running, while `ModelManager` polls the value ten times a second on the
///    main actor. That is a data race on a plain `var`, so the value lives
///    behind a lock.
/// 2. **It only ever moves forward.** Both libraries work through a model a file
///    at a time and restart their own fraction at zero for each one, so the raw
///    numbers arrive as a sawtooth. A bar that drops back to 0% four times reads
///    as a broken download, so every report is clamped to the high-water mark.
final class ModelDownloadProgress: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0.0)

    /// The fraction complete, 0…1.
    var value: Double {
        state.withLock { $0 }
    }

    /// Move the bar to `fraction`, ignoring anything at or behind where it
    /// already is. Values outside 0…1 are clamped rather than trusted.
    func advance(to fraction: Double) {
        let clamped = min(max(fraction, 0.0), 1.0)
        state.withLock { current in
            if clamped > current { current = clamped }
        }
    }

    /// Send the bar back to zero at the start of a download. The only write that
    /// is allowed to move backwards.
    func reset() {
        state.withLock { $0 = 0.0 }
    }
}
