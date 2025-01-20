#if os(Windows)
import Foundation
import FileMonitorShared
import WinSDK

public struct WindowsWatcher: WatcherProtocol {
    var fsWatcher: WinDirectoryWatcher
    public var delegate: WatcherDelegate?

    public init(directory: URL) {
        fsWatcher = WinDirectoryWatcher(directory: directory)
    }

    public func observe() throws {
        fsWatcher.watch { (file, action) in
            guard let delegate = delegate else { return }
            let url = URL(filePath: file)
            if action == FILE_ACTION_ADDED {
                delegate.fileDidChanged(event: FileChangeEvent.added(file: URL(filePath: file)))
            } else if action == FILE_ACTION_REMOVED {
                delegate.fileDidChanged(event: FileChangeEvent.deleted(file: URL(filePath: file)))
            } else if action == FILE_ACTION_MODIFIED {
                delegate.fileDidChanged(event: FileChangeEvent.changed(file: URL(filePath: file)))
            }
        }

        fsWatcher.start()
    }

    public func stop() {
        fsWatcher.stop()
    }
}
#endif
