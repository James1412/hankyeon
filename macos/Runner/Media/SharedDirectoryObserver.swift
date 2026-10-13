import Foundation
import Darwin

/// 원자적 파일 교체를 놓치지 않도록 파일이 아닌 공유 폴더를 감시합니다. 주기 조회는 없습니다.
final class SharedDirectoryObserver {
    private var source: DispatchSourceFileSystemObject?
    private var notificationObserver: NSObjectProtocol?

    func start(at url: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) throws {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { throw MediaBridgeStore.failure("공유 폴더 변경 감시를 시작할 수 없습니다.") }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
        // 별도 프로세스의 저장 완료 알림도 받아 sandbox 간 파일 이벤트 지연을 보완합니다.
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: MediaBridgeStore.changeNotification, object: nil, queue: .main
        ) { _ in queue.async(execute: onChange) }
    }

    func stop() {
        source?.cancel(); source = nil
        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
        }
        notificationObserver = nil
    }
    deinit { stop() }
}
