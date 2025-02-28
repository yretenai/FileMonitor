//
// aus der Technik, on 17.05.23.
// https://www.ausdertechnik.de
//

import Foundation
import FileMonitorShared
#if os(macOS)
import FileMonitorMacOS
#elseif os(Linux)
import FileMonitorLinux
#elseif os(Windows)
import FileMonitorWin32
#endif

/// Errors that `FileMonitor` can throw
public enum FileMonitorErrors: Error {
    case unsupported_os
    case not_implemented_yet
    case not_a_directory(url: URL)
    case can_not_open(url: URL)
}

/// FileMonitor: Watch for file changes in a directory with a unified API on Linux and macOS.
public struct FileMonitor: WatcherDelegate {
    private let fileChangeStream = AsyncStream.makeStream(of: FileChange.self)
    public var stream: AsyncStream<FileChange> {
        fileChangeStream.stream
    }

    var watcher: WatcherProtocol
    public var delegate: FileDidChangeDelegate? {
        didSet {
            // further improvement:
            // bind watcher.delegate direct to delegate to get rid of call-tree
        }
    }

    @discardableResult
    public init(directory url: URL, delegate externDelegate: FileDidChangeDelegate? = nil) throws {
        if url.isDirectory == false {
            throw FileMonitorErrors.not_a_directory(url: url)
        }

        // extern delegate
        if let externDelegate {
            delegate = externDelegate
        }

        #if os(Linux)
            watcher = LinuxWatcher(directory: url)
        #elseif os(macOS)
            watcher = try MacosWatcher(directory: url)
        #elseif os(Windows)
            watcher = try WindowsWatcher(directory: url)
        #else
            throw FileMonitorErrors.unsupported_os
        #endif

        watcher.delegate = self
    }

    /// Start watching file changes
    /// - Throws:
    ///   - FileMonitorErrors
    ///   - Error
    public func start() throws {
        try watcher.observe()
    }

    /// Stop watching file changes
    ///
    /// - Throws:
    ///   - FileMonitorErrors
    ///   - Error
    public func stop() {
        watcher.stop()
        fileChangeStream.continuation.finish()
    }

    // MARK: - WatcherDelegate

    /// Called when the underlying subsystem detect a file change
    ///
    /// - Parameter event: A file change event
    public func fileDidChanged(event: FileChangeEvent) {
        delegate?.fileDidChanged(event: event)
        fileChangeStream.continuation.yield(event)
    }

}
