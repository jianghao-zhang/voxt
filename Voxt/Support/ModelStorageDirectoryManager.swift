import Foundation
import AppKit
import HuggingFace

enum ModelStorageDirectoryManager {
    private struct ResolvedRootCache {
        let bookmarkData: Data?
        let path: String?
        let rootURL: URL
    }

    private static let lock = NSLock()
    private static var securityScopedURL: URL?
    private static var resolvedRootCache: ResolvedRootCache?
    private static let fileManager = FileManager.default

    static var defaultRootURL: URL {
        HubCache.default.cacheDirectory
    }

    static func resolvedRootURL() -> URL {
        let defaults = UserDefaults.standard
        let bookmarkData = defaults.data(forKey: AppPreferenceKey.modelStorageRootBookmark)
        let storedPath = normalizedStoredPath(defaults.string(forKey: AppPreferenceKey.modelStorageRootPath))

        lock.lock()
        if let resolvedRootCache,
           resolvedRootCache.bookmarkData == bookmarkData,
           resolvedRootCache.path == storedPath {
            let cachedRootURL = resolvedRootCache.rootURL
            lock.unlock()
            return cachedRootURL
        }
        lock.unlock()

        let rootURL: URL
        if let bookmarkData,
           let bookmarkedURL = resolveSecurityScopedURL(from: bookmarkData) {
            rootURL = bookmarkedURL
        } else if let storedPath {
            rootURL = URL(fileURLWithPath: storedPath, isDirectory: true)
        } else {
            rootURL = defaultRootURL
        }

        updateResolvedRootCache(
            bookmarkData: bookmarkData,
            path: storedPath,
            rootURL: rootURL
        )
        return rootURL
    }

    static func saveUserSelectedRootURL(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        let bookmark = try normalized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let defaults = UserDefaults.standard
        defaults.set(normalized.path, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.set(bookmark, forKey: AppPreferenceKey.modelStorageRootBookmark)
        updateResolvedRootCache(
            bookmarkData: bookmark,
            path: normalized.path,
            rootURL: normalized
        )

        _ = resolveSecurityScopedURL(from: bookmark)
    }

    static func openRootInFinder() {
        let url = resolvedRootURL()
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func resolveSecurityScopedURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if securityScopedURL?.path != resolved.path {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            if resolved.startAccessingSecurityScopedResource() {
                securityScopedURL = resolved
            }
        }

        if isStale,
           let refreshed = try? resolved.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
           ) {
            UserDefaults.standard.set(refreshed, forKey: AppPreferenceKey.modelStorageRootBookmark)
            updateResolvedRootCache(
                bookmarkData: refreshed,
                path: normalizedStoredPath(UserDefaults.standard.string(forKey: AppPreferenceKey.modelStorageRootPath)),
                rootURL: resolved
            )
        }

        return resolved
    }

    private static func normalizedStoredPath(_ path: String?) -> String? {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    private static func updateResolvedRootCache(bookmarkData: Data?, path: String?, rootURL: URL) {
        lock.lock()
        resolvedRootCache = ResolvedRootCache(
            bookmarkData: bookmarkData,
            path: path,
            rootURL: rootURL
        )
        lock.unlock()
    }
}
