import Foundation

final class AsyncJSONPersistenceCoordinator {
    private let queue: DispatchQueue

    init(label: String) {
        self.queue = DispatchQueue(label: label, qos: .utility)
    }

    func scheduleWrite<Value: Encodable>(_ value: Value, to url: URL) {
        queue.async {
            do {
                let data = try JSONEncoder().encode(value)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: [.atomic])
            } catch {
                // Keep UI responsive even if persistence fails.
            }
        }
    }
}
