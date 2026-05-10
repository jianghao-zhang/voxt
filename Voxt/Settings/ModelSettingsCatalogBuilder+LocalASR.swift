import SwiftUI

private func localizedModelCatalog(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

@MainActor
extension ModelCatalogBuilder {
    func dictationASREntry() -> ModelCatalogEntry {
        ModelCatalogEntry(
            id: FeatureModelSelectionID.dictation.rawValue,
            title: localizedModelCatalog("Direct Dictation"),
            engine: localizedModelCatalog("System ASR"),
            sizeText: localizedModelCatalog("Built-in"),
            ratingText: "3.4",
            filterTags: catalogFilterTags(
                base: [localizedModelCatalog("Local"), localizedModelCatalog("Built-in"), localizedModelCatalog("Fast")],
                installed: true,
                requiresConfiguration: false,
                configured: true,
                selectionID: .dictation
            ),
            displayTags: catalogDisplayTags(
                base: [localizedModelCatalog("Local"), localizedModelCatalog("Built-in"), localizedModelCatalog("Fast")],
                requiresConfiguration: false,
                configured: true,
                selectionID: .dictation
            ),
            statusText: "",
            usageLocations: usageLocations(for: .dictation),
            badgeText: nil,
            primaryAction: ModelTableAction(title: localizedModelCatalog("Settings")) {
                showASRHintTarget(.dictation)
            },
            secondaryActions: []
        )
    }

    func mlxASREntries() -> [ModelCatalogEntry] {
        MLXModelManager.availableModels.map { model in
            let repo = MLXModelManager.canonicalModelRepo(model.id)
            let selectionID = FeatureModelSelectionID.mlx(repo)
            let snapshot = resolvedMLXCatalogSnapshot(for: repo)
            let isInstalled = snapshot.isDownloaded
            let badge = hasIssue(.mlxModel(repo)) ? localizedModelCatalog("Needs Setup") : nil
            let status = isUninstallingModel(repo)
                ? localizedModelCatalog("Uninstalling…")
                : mlxStatusText(snapshot)

            return ModelCatalogEntry(
                id: "mlx:\(repo)",
                title: mlxModelManager.displayTitle(for: repo),
                engine: localizedModelCatalog("MLX Audio"),
                sizeText: mlxASRSizeText(repo: repo, isInstalled: isInstalled),
                ratingText: MLXModelManager.ratingText(for: repo),
                filterTags: catalogFilterTags(
                    base: [localizedModelCatalog("Local")] + mlxCatalogTags(for: repo),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localizedModelCatalog("Local")] + mlxCatalogTags(for: repo),
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                statusText: status,
                usageLocations: usageLocations(for: selectionID),
                badgeText: badge,
                primaryAction: mlxPrimaryAction(repo: repo, snapshot: snapshot),
                secondaryActions: mlxSecondaryActions(repo: repo, snapshot: snapshot)
            )
        }
    }

    private func resolvedMLXCatalogSnapshot(for repo: String) -> MLXModelManager.CatalogSnapshot {
        let managerSnapshot = mlxModelManager.catalogSnapshot(for: repo)
        let downloading = isDownloadingModel(repo)
        let paused = !downloading && isPausedModel(repo)

        guard downloading || paused else {
            return managerSnapshot
        }

        let state: MLXModelManager.ModelState
        if downloading {
            state = .downloading(
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                completedFiles: 0,
                totalFiles: 0
            )
        } else {
            state = .paused(
                progress: 0,
                completed: 0,
                total: 0,
                currentFile: nil,
                completedFiles: 0,
                totalFiles: 0
            )
        }

        return .init(
            repo: managerSnapshot.repo,
            isDownloaded: managerSnapshot.isDownloaded,
            hasResumableDownload: paused || managerSnapshot.hasResumableDownload,
            state: state,
            pausedStatusMessage: managerSnapshot.pausedStatusMessage,
            hasActiveDownloadTask: downloading || managerSnapshot.hasActiveDownloadTask
        )
    }

    func whisperASREntries() -> [ModelCatalogEntry] {
        WhisperKitModelManager.availableModels.map { model in
            let modelID = WhisperKitModelManager.canonicalModelID(model.id)
            let selectionID = FeatureModelSelectionID.whisper(modelID)
            let isInstalled = whisperModelManager.isModelDownloaded(id: modelID)
            let badge = hasIssue(.whisperModel(modelID)) ? localizedModelCatalog("Needs Setup") : nil
            let status = isUninstallingWhisperModel(modelID) ? localizedModelCatalog("Uninstalling…") : whisperModelStatusText(modelID)

            return ModelCatalogEntry(
                id: "whisper:\(modelID)",
                title: whisperModelManager.displayTitle(for: modelID),
                engine: localizedModelCatalog("Whisper"),
                sizeText: whisperASRSizeText(modelID: modelID, isInstalled: isInstalled),
                ratingText: WhisperKitModelManager.ratingText(for: modelID),
                filterTags: catalogFilterTags(
                    base: [localizedModelCatalog("Local")] + whisperCatalogTags(for: modelID),
                    installed: isInstalled,
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                displayTags: catalogDisplayTags(
                    base: [localizedModelCatalog("Local")] + whisperCatalogTags(for: modelID),
                    requiresConfiguration: false,
                    configured: true,
                    selectionID: selectionID
                ),
                statusText: status,
                usageLocations: usageLocations(for: selectionID),
                badgeText: badge,
                primaryAction: whisperPrimaryAction(modelID: modelID, isInstalled: isInstalled),
                secondaryActions: whisperSecondaryActions(modelID: modelID, isInstalled: isInstalled)
            )
        }
    }

    private func mlxASRSizeText(repo: String, isInstalled: Bool) -> String {
        if isInstalled {
            return mlxModelManager.cachedModelSizeText(repo: repo) ?? mlxModelManager.remoteSizeText(repo: repo)
        }
        return mlxModelManager.remoteSizeText(repo: repo)
    }

    private func whisperASRSizeText(modelID: String, isInstalled: Bool) -> String {
        if isInstalled {
            return whisperModelManager.cachedModelSizeText(id: modelID) ?? whisperModelManager.remoteSizeText(id: modelID)
        }
        return whisperModelManager.remoteSizeText(id: modelID)
    }

    private func mlxPrimaryAction(repo: String, snapshot: MLXModelManager.CatalogSnapshot) -> ModelTableAction? {
        if isUninstallingModel(repo) {
            return ModelTableAction(title: localizedModelCatalog("Uninstalling…"), isEnabled: false) {}
        }
        if snapshot.isDownloading {
            return ModelTableAction(title: localizedModelCatalog("Pause")) {
                pauseModelDownload(repo)
            }
        }
        if snapshot.isPaused {
            return ModelTableAction(title: localizedModelCatalog("Continue")) {
                downloadModel(repo)
            }
        }
        if snapshot.isDownloaded {
            return ModelTableAction(title: localizedModelCatalog("Uninstall"), role: .destructive) {
                deleteModel(repo)
            }
        }
        return ModelTableAction(
            title: localizedModelCatalog("Install")
        ) {
            downloadModel(repo)
        }
    }

    private func mlxSecondaryActions(repo: String, snapshot: MLXModelManager.CatalogSnapshot) -> [ModelTableAction] {
        var actions = [ModelTableAction]()
        if snapshot.isDownloading {
            actions.append(
                ModelTableAction(title: localizedModelCatalog("Cancel"), role: .destructive) {
                    cancelModelDownload(repo)
                }
            )
        } else if snapshot.isPaused {
            actions.append(
                ModelTableAction(title: localizedModelCatalog("Cancel"), role: .destructive) {
                    cancelModelDownload(repo)
                }
            )
        } else if snapshot.isDownloaded {
            actions.append(
                ModelTableAction(title: localizedModelCatalog("Open Location")) {
                    openMLXModelDirectory(repo)
                }
            )
        }
        actions.append(
            ModelTableAction(title: localizedModelCatalog("Settings")) {
                presentMLXSettings(repo)
            }
        )
        return actions
    }

    private func mlxStatusText(_ snapshot: MLXModelManager.CatalogSnapshot) -> String {
        if case .downloading(_, let completed, let total, _, _, _) = snapshot.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .downloading(completed: completed, total: total)
            )
        }

        if case .paused(_, let completed, let total, _, _, _) = snapshot.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: completed,
                    total: total,
                    pauseMessage: snapshot.pausedStatusMessage
                )
            )
        }

        if snapshot.isPaused {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .paused(
                    completed: 0,
                    total: 0,
                    pauseMessage: AppLocalization.localizedString("Paused. Ready to continue.")
                )
            )
        }

        if case .error(let message) = snapshot.state {
            return ModelDownloadPresentationSupport.statusText(
                downloadState: .idle,
                errorMessage: message
            )
        }

        return ""
    }

    private func whisperPrimaryAction(modelID: String, isInstalled: Bool) -> ModelTableAction? {
        if isUninstallingWhisperModel(modelID) {
            return ModelTableAction(title: localizedModelCatalog("Uninstalling…"), isEnabled: false) {}
        }
        if isDownloadingWhisperModel(modelID) {
            return ModelTableAction(title: localizedModelCatalog("Pause")) {
                whisperModelManager.pauseDownload()
            }
        }
        if isPausedWhisperModel(modelID) {
            return ModelTableAction(title: localizedModelCatalog("Continue")) {
                downloadWhisperModel(modelID)
            }
        }
        if isInstalled {
            return ModelTableAction(title: localizedModelCatalog("Uninstall"), role: .destructive) {
                deleteWhisperModel(modelID)
            }
        }
        return ModelTableAction(
            title: localizedModelCatalog("Install"),
            isEnabled: !isAnotherWhisperModelDownloading(modelID)
        ) {
            downloadWhisperModel(modelID)
        }
    }

    private func whisperSecondaryActions(modelID: String, isInstalled: Bool) -> [ModelTableAction] {
        var actions = [ModelTableAction]()
        if isDownloadingWhisperModel(modelID) {
            actions.append(
                ModelTableAction(title: localizedModelCatalog("Cancel"), role: .destructive) {
                    whisperModelManager.cancelDownload()
                }
            )
        } else if isPausedWhisperModel(modelID) {
            actions.append(
                ModelTableAction(title: localizedModelCatalog("Cancel"), role: .destructive) {
                    cancelWhisperDownload(modelID)
                }
            )
        } else if isInstalled {
            actions.append(
                ModelTableAction(title: localizedModelCatalog("Open Location")) {
                    openWhisperModelDirectory(modelID)
                }
            )
        }
        actions.append(
            ModelTableAction(title: localizedModelCatalog("Whisper Settings")) {
                presentWhisperSettings()
            }
        )
        return actions
    }
}
