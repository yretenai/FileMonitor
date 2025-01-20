#if os(Windows)
import FileMonitorShared
import Foundation
import WinSDK

public final class WinDirectoryWatcher {
    private let dispatchQueue: DispatchQueue
	private var terminate: HANDLE
	private var directory: HANDLE
    private var shouldStopWatching: Bool = false

	public init(directory dir: URL) {
        dispatchQueue = DispatchQueue.global(qos: .background)
		terminate = CreateEventW(nil, true, false, nil)
		directory = CreateFileA(dir.path, DWORD(FILE_LIST_DIRECTORY), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil, DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED), nil)
	}

	deinit {
		stop()
	}
	
    public func start() {
        shouldStopWatching = false
        dispatchQueue.activate()
    }

    public func stop() {
        shouldStopWatching = true
        dispatchQueue.suspend()

		// stop() deinits the watcher, and should be recreated as the state is not easily recoverable at this point
		if terminate != INVALID_HANDLE_VALUE {
			SetEvent(terminate)
			terminate = INVALID_HANDLE_VALUE
		}

		if directory != INVALID_HANDLE_VALUE {
			CloseHandle(directory)
			directory = INVALID_HANDLE_VALUE
		}
    }

    public func watch(thenInvoke callback: @escaping (String, DWORD) -> Void) {
        self.dispatchQueue.async { [self] in
			// stop() calls indicate an unrecoverable state
			var overlapped = OVERLAPPED()
			overlapped.hEvent = CreateEventW(nil, false, false, nil)

			let entrySize = MemoryLayout<FILE_NOTIFY_INFORMATION>.stride + (Int(MAX_PATH) * MemoryLayout<WCHAR>.stride)
			let capacity = entrySize * 16 / MemoryLayout<DWORD>.stride
			var buffer = UnsafeMutableBufferPointer<DWORD>.allocate(capacity: capacity)

			let filter = DWORD(FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME | FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_CREATION)
			while !self.shouldStopWatching {
				let terminate = self.terminate
				if terminate == INVALID_HANDLE_VALUE {
					stop()
					return
				}

				let handle = self.directory
				if handle == INVALID_HANDLE_VALUE {
					stop()
					return
				}

				var bytes: DWORD = 0
				if !ReadDirectoryChangesW(handle, &buffer, DWORD(capacity), true, filter, &bytes, &overlapped, nil) {
					stop()
					return
				}

				var handles: (HANDLE?, HANDLE?) = (terminate, overlapped.hEvent)
				switch WaitForMultipleObjects(2, &handles.0, false, INFINITE) {
					case WAIT_OBJECT_0 + 1:
						break
					case DWORD(WAIT_TIMEOUT):
						continue
					case WAIT_FAILED, WAIT_OBJECT_0:
						fallthrough
					default:
						stop()
						return
				}

				if !GetOverlappedResult(handle, &overlapped, &bytes, false) {
					stop()
					return
				}

				if bytes == 0 {
					continue  // ??
				}

				buffer.withMemoryRebound(to: FILE_NOTIFY_INFORMATION.self) {
					let pNotify: UnsafeMutablePointer<FILE_NOTIFY_INFORMATION>? = $0.baseAddress
					while var pNotify = pNotify {
						let file = String(utf16CodeUnitsNoCopy: &pNotify.pointee.FileName, count: Int(pNotify.pointee.FileNameLength) / MemoryLayout<WCHAR>.stride, freeWhenDone: false)
						let action = pNotify.pointee.Action

                        self.dispatchQueue.async() {
                            callback(file, action)
                        }
						
						pNotify = (UnsafeMutableRawPointer(pNotify) + Int(pNotify.pointee.NextEntryOffset)).assumingMemoryBound(to: FILE_NOTIFY_INFORMATION.self)
					}
				}
			}
		}
	}
}
#endif
