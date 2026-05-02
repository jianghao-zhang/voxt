import Foundation
import AppKit
import FaviconFinder

enum EnhancementOverlayIconResolver {
    private static let faviconCache = NSCache<NSString, NSImage>()
    private static let faviconTimeoutNanoseconds: UInt64 = 2_000_000_000

    static func appIcon(bundleID: String) -> NSImage? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = running.icon {
            return icon
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    static func faviconOrigin(fromPageURL urlString: String?) -> String? {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased()
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let port = url.port,
           !((scheme == "http" && port == 80) || (scheme == "https" && port == 443)) {
            components.port = port
        }
        return components.string
    }

    static func faviconLookupURL(forOrigin origin: String) -> URL? {
        URL(string: origin)
    }

    static func cachedFavicon(forOrigin origin: String) -> NSImage? {
        faviconCache.object(forKey: origin as NSString)
    }

    static func favicon(forOrigin origin: String) async -> NSImage? {
        if let cached = cachedFavicon(forOrigin: origin) {
            return cached
        }
        guard let lookupURL = faviconLookupURL(forOrigin: origin) else {
            return nil
        }

        let imageData = await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                do {
                    let favicon = try await FaviconFinder(url: lookupURL)
                        .fetchFaviconURLs()
                        .download()
                        .largest()
                    return favicon.image?.data
                } catch {
                    VoxtLog.warning("Enhancement favicon lookup failed. origin=\(origin), error=\(error.localizedDescription)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: faviconTimeoutNanoseconds)
                return nil
            }

            let resolvedImage = await group.next() ?? nil
            group.cancelAll()
            return resolvedImage
        }

        guard let imageData,
              let image = NSImage(data: imageData) else {
            return nil
        }

        faviconCache.setObject(image, forKey: origin as NSString)
        return image
    }
}

@MainActor
extension AppDelegate {
    func applyEnhancementOverlayIconIfNeeded(
        match: OverlayEnhancementIconMatch?,
        sessionID: UUID
    ) {
        guard shouldAllowEnhancementOverlayIconUpdate(for: sessionID) else { return }
        overlayState.compactLeadingIconImage = nil

        guard let match else { return }

        switch match.kind {
        case .app:
            overlayState.compactLeadingIconImage = EnhancementOverlayIconResolver.appIcon(bundleID: match.bundleID)
        case .url:
            applyURLMatchOverlayIcon(match, sessionID: sessionID)
        }
    }

    private func applyURLMatchOverlayIcon(
        _ match: OverlayEnhancementIconMatch,
        sessionID: UUID
    ) {
        if let browserIcon = EnhancementOverlayIconResolver.appIcon(bundleID: match.bundleID) {
            overlayState.compactLeadingIconImage = browserIcon
        }

        guard let origin = match.urlOrigin else { return }
        if let cached = EnhancementOverlayIconResolver.cachedFavicon(forOrigin: origin) {
            overlayState.compactLeadingIconImage = cached
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let favicon = await EnhancementOverlayIconResolver.favicon(forOrigin: origin)
            await MainActor.run {
                self.applyFetchedEnhancementOverlayIcon(
                    favicon,
                    expectedMatch: match,
                    sessionID: sessionID
                )
            }
        }
    }

    private func applyFetchedEnhancementOverlayIcon(
        _ image: NSImage?,
        expectedMatch: OverlayEnhancementIconMatch,
        sessionID: UUID
    ) {
        guard let image,
              shouldAllowEnhancementOverlayIconUpdate(for: sessionID),
              lastEnhancementPromptContext?.overlayIconMatch == expectedMatch
        else {
            return
        }
        overlayState.compactLeadingIconImage = image
    }

    private func shouldAllowEnhancementOverlayIconUpdate(for sessionID: UUID) -> Bool {
        activeRecordingSessionID == sessionID &&
            sessionOutputMode == .transcription &&
            overlayState.displayMode == .processing &&
            overlayState.sessionIconMode == .transcription &&
            !isSessionCancellationRequested
    }
}
