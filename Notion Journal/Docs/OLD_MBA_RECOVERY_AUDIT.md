# Old MBA Recovery Audit

Source compared:

- Current repo: `/Users/mac/Developer/Notion Journal/Notion Journal`
- Old MBA iCloud copy: `/Users/mac/Library/Mobile Documents/com~apple~CloudDocs/Notion Journal/Notion Journal`

Comparison summary:

- Shared files: `140`
- Shared files with different contents: `55`
- Files only in current repo: `2`
- Files only in old MBA copy: `5`

Important context:

- The current repo is already dirty with many local changes.
- This is not a full rollback of the whole app.
- The biggest regressions are concentrated in `Outline`, `DB`, `UI`, `AppStore`, `Health`, and app bootstrap/model files.
- Some current files are clearly newer and should not be blindly replaced.

## Restore Directly

These exist in the old MBA source but are missing from the current repo and are strong recovery candidates.

- `Outline/NJMindElixirOfflineAssets.swift`
- `Outline/MindElixirAssets/mind-elixir.js`
- `Outline/MindElixirAssets/style.css`
- `Health/NJTrainingRuntime.swift`
- `Docs/Finance_Premise_Registry.md`

## Manual Merge Needed

These differ substantially and should be merged carefully, not overwritten blindly.

High priority:

- `Outline/NJOutlineDetailView.swift`
  - current: `28,596` bytes
  - old MBA: `183,407` bytes
  - old MBA includes missing mindmap/ink/gantt/handwriting/web content features
- `UI/NJCalendarView.swift`
  - current: `107,785`
  - old MBA: `208,333`
- `DB/DBCalendarTable.swift`
  - current: `19,379`
  - old MBA: `70,625`
- `DB/NJLocalBLRunner.swift`
  - current: `9,634`
  - old MBA: `30,728`
- `AppStore.swift`
  - current: `30,512`
  - old MBA: `50,972`
- `DB/DBSchemaInstaller.swift`
  - current: `36,386`
  - old MBA: `54,865`

Medium priority:

- `DB/DBBlockPayloadStore.swift`
- `DB/DBBlockTable.swift`
- `DB/DBNoteBlockTable.swift`
- `DB/DBNoteRepository.swift`
- `DB/DBNoteRepositoryExport.swift`
- `DB/DBNoteRepositoryOutline.swift`
- `DB/DBPlannedExerciseTable.swift`
- `Health/NJHealthLogger.swift`
- `Health/NJHealthLoggerPage.swift`
- `Model.swift`
- `Notion_JournalApp.swift`
- `Outline/NJOutlineModels.swift`
- `Outline/NJOutlineSidebarView.swift`
- `Outline/NJOutlineStore.swift`
- `Sync/DBCloudBridge.swift`
- `Sync/NJCloudKitTransport.swift`
- `Sync/NJCloudSchema.swift`
- `Sync/NJCloudSyncCoordinator.swift`
- `UI/NJTimeModuleView.swift`

Lower priority but still changed:

- `Attachments/NJAttachment.swift`
- `Attachments/NJPhotoLibraryPresenter.swift`
- `Common/NJAudioIngestor.swift`
- `Common/NJClipIngestor.swift`
- `Common/NJTimeSlotQuickAddIntent.swift`
- `Common/NJTimeSlotStore.swift`
- `DB/DBAttachmentTable.swift`
- `DB/DBSQL.swift`
- `GPS/NJGPSLogger.swift`
- `Notes/NoteEditor/NJClipboardInboxView.swift`
- `Notes/NoteEditor/NJNoteEditorContainerActions.swift`
- `Notes/NoteEditor/NJNoteEditorContainerPersistence.swift`
- `Notes/NoteEditor/NJNoteEditorContainerView.swift`
- `Notes/NoteEditor/NJProtonFloatingFormatBar.swift`
- `Notes/NoteEditor/Rescontruct/NJReconstructedManualView.swift`
- `Proton/NJProtonEditorBridge.swift`
- `Sync/CloudSyncEngine.swift`
- `UI/NJChronoNoteListView.swift`
- `UI/UIRootView.swift`

## Keep Current

These are current-only or current appears intentionally newer/larger. They should generally stay as-is unless a targeted issue is found.

Current-only:

- `Common/NJTimeSlotReminderScheduler.swift`
- `Goals/NJGoalJournalDashboardView.swift`

Current likely newer / intentionally expanded:

- `Notes/NoteEditor/NJBlockHostView.swift`
- `Notes/NoteEditor/Rescontruct/NJReconstructedNoteView.swift`
- `Notes/NoteEditor/Rescontruct/NJReconstructedNotePersistence.swift`
- `Notes/NoteEditor/Rescontruct/NJReconstructedTagMatch.swift`
- `Proton/NJProtonAttachments.swift`
- `UI/UISidebar.swift`
- `Goals/NJGoalQuickPickSheet.swift`
- `DB/DBNoteRepositoryReadWrite.swift`
- `Notion Journal.entitlements`

## Damage Assessment

By module size delta, old MBA is larger by:

- `Outline`: `+378,147` bytes
- `DB`: `+135,315` bytes
- `UI`: `+104,532` bytes
- `AppStore.swift`: `+20,460` bytes
- `Health`: `+20,155` bytes
- `Notion_JournalApp.swift`: `+7,864` bytes
- `Model.swift`: `+7,450` bytes

This strongly suggests real regression, not just normal code churn.

## Recommended Recovery Order

1. Restore missing files from `Restore Directly`.
2. Recover the `Outline` module first.
3. Recover `DB` + `UI` pieces that support outline/calendar behavior.
4. Merge `AppStore.swift`, `Model.swift`, and `Notion_JournalApp.swift`.
5. Review `Health` and `Sync` changes after the core app compiles again.

## Safety Notes

- Do not replace the entire repo with the old MBA copy.
- The current repo has active local edits in multiple files, including reconstructed notes, weather work, and editor code.
- For files already modified in the current repo, recovery should be done by manual merge.
