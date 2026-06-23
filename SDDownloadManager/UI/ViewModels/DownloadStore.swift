import Foundation

class DownloadStore {
    static let shared = DownloadStore()
    private let key = "com.sddownloadmanager.items"
    private let lock = NSLock()
    private var _items: [DownloadItem] = []

    var items: [DownloadItem] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    private init() { load() }

    func add(_ item: DownloadItem) {
        lock.lock(); _items.insert(item, at: 0); lock.unlock()
        save()
    }

    func update(_ item: DownloadItem) {
        lock.lock()
        if let i = _items.firstIndex(where: { $0.id == item.id }) { _items[i] = item }
        lock.unlock()
    }

    func save() {
        lock.lock(); let copy = _items; lock.unlock()
        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func remove(id: String) {
        lock.lock(); _items.removeAll { $0.id == id }; lock.unlock()
        save()
    }

    func item(forId id: String) -> DownloadItem? {
        lock.lock(); defer { lock.unlock() }
        return _items.first { $0.id == id }
    }

    private func load() {
        guard
            let data  = UserDefaults.standard.data(forKey: key),
            let items = try? JSONDecoder().decode([DownloadItem].self, from: data)
        else { return }
        _items = items
        // Any in-progress items become paused on relaunch
        for item in _items where item.status == .downloading {
            item.status = .paused
        }
    }
}
