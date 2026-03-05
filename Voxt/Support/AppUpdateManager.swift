import Foundation
import Sparkle

@MainActor
final class AppUpdateManager: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    enum CheckSource {
        case automatic
        case manual
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    private let stableFeedURLString = "https://voxt.actnow.dev/updates/stable/appcast.xml"
    private let betaFeedURLString = "https://voxt.actnow.dev/updates/beta/appcast.xml"

    // Background/dockless apps should opt into Sparkle's gentle reminder support
    // to avoid missing scheduled update alerts.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    var hasUpdate: Bool {
        false
    }

    var latestVersion: String? {
        nil
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates(source: CheckSource) {
        switch source {
        case .manual:
            VoxtLog.info("Manual update check triggered via Sparkle.")
            updaterController.checkForUpdates(nil)
        case .automatic:
            VoxtLog.info("Background update check triggered via Sparkle.")
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        selectedFeedURLString
    }

    private var selectedFeedURLString: String {
        // Prefer stable feed by default. Beta feed should be explicitly opted in
        // because local/dev beta channels may contain test-only appcast entries.
        if let channel = ProcessInfo.processInfo.environment["VOXT_UPDATE_CHANNEL"]?.lowercased() {
            switch channel {
            case "beta":
                return betaFeedURLString
            case "stable":
                return stableFeedURLString
            default:
                break
            }
        }
        return stableFeedURLString
    }
}
