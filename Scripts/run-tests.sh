#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which is how CI reported success over a harness that had not compiled since phase 10.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/forge-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    if ! swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; then
        printf '\033[31mFAIL\033[0m  %-22s did not compile\n' "$name"
        : > "$BIN/$name.failed"
        exit 0
    fi
    if ! "$BIN/$name" > "$BIN/$name.log" 2>&1; then
        printf '\033[31mFAIL\033[0m  %-22s assertion failed\n' "$name"
        : > "$BIN/$name.failed"
        exit 0
    fi
    printf '\033[32mok\033[0m    %-22s\n' "$name"
    exit 0
fi

QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed

failed=()
ran=0
only="${1:-}"

# `--index` merges each harness's compile command into .compile instead of running anything.
# xcodebuild never compiles the harnesses, so without this nothing in Tests/ resolves in an editor.
# The source lists below are the only copy, which is why this lives here rather than in its own script.
emit_db=0
DB="${TMPDIR:-/tmp}/forge-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# run [slow] [-O] [index] <name> <source...> — queue the harness. `slow` dispatches it in the first
# wave; `index` claims editor flags for a harness that is compiled by hand rather than by the suite.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths throughout: sourcekit-lsp resolves the command itself and does not apply
    # `directory` to relative arguments, so a relative path there silently yields no index.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Claim every file under `Tests/`: the harness and any helper compiled beside it. A shipped
        # source stays unclaimed, because it would get this short command instead of the app's full
        # one and `.compile` is last-wins — but the app never compiles anything in `Tests/`.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Forge/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/EntryNaming.swift $L/LauncherOrder.swift
run slow -O corpus-test    $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift
run file-search-test       $L/SearchRelevance.swift \
                           Forge/Features/FileSearch/Model/*.swift
run file-search-session-test Forge/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             Forge/Features/FileSearch/Model/*.swift \
                             Forge/Features/FileSearch/Service/*.swift
run menu-search-test       $L/SearchRelevance.swift \
                           Forge/Features/MenuSearch/Model/*.swift \
                           Forge/Features/MenuSearch/Service/*.swift
run window-switch-test     $L/SearchRelevance.swift \
                           Forge/Features/WindowSwitcher/Model/*.swift
run index file-search-performance Forge/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Forge/Features/FileSearch/Model/*.swift \
                           Forge/Features/FileSearch/Service/FileSearchService.swift
run ranking-test           $L/SearchRelevance.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Forge/Platform/AppDisplayName.swift \
                           Forge/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run calc-test              Forge/Features/Calculator/Model/*.swift
run index calc-performance Forge/Features/Calculator/Model/*.swift
run calendar-test          Forge/Features/Calendar/Model/*.swift
run clipboard-test         Forge/Features/Clipboard/Model/ClipboardStore.swift \
                           Forge/Features/Clipboard/Model/ClipboardFilter.swift \
                           Forge/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Forge/Features/Clipboard/Model/ColorValue.swift \
                           Forge/Features/Clipboard/Model/ColorFormat.swift \
                           Forge/Features/Clipboard/Model/ColorSpaces.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Forge/Features/Quicklinks/Model/QuicklinkDestination.swift
run clipboard-search-test  Forge/Features/Clipboard/Model/*.swift $Q
run clipboard-text-test    Forge/Features/Clipboard/Model/*.swift $Q \
                           Forge/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Forge/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Forge/Features/Clipboard/Service/ClipboardTextWorker.swift
run clipboard-worker-test  Forge/Features/Clipboard/Model/*.swift $Q \
                           Forge/Features/Clipboard/Service/ClipboardTextWorker.swift
run pasteboard-test        Forge/Platform/PasteboardFiles.swift \
                           Forge/Features/Clipboard/Model/ClipboardStore.swift \
                           Forge/Features/Clipboard/Model/ClipboardFilter.swift \
                           Forge/Features/Clipboard/Model/ColorValue.swift \
                           Forge/Features/Clipboard/Model/ColorFormat.swift \
                           Forge/Features/Clipboard/Model/ColorSpaces.swift \
                           Forge/Features/Clipboard/Service/ClipboardManager.swift \
                           Forge/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Forge/Platform/PasteboardFiles.swift \
                           Forge/Features/Clipboard/Model/ClipboardStore.swift \
                           Forge/Features/Clipboard/Model/ClipboardFilter.swift \
                           Forge/Features/Clipboard/Model/ColorValue.swift \
                           Forge/Features/Clipboard/Model/ColorFormat.swift \
                           Forge/Features/Clipboard/Model/ColorSpaces.swift \
                           Forge/Features/Clipboard/Service/ClipboardManager.swift
run emoji-test             Forge/Features/Emoji/Model/EmojiCatalog.swift \
                           Forge/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Forge/Features/Emoji/Model/EmojiData.generated.swift
run palette-selection-test Forge/Features/PaletteRowIndex.swift \
                           Forge/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Forge/Platform/Appearance.swift \
                           Forge/DesignSystem/Theme.swift \
                           Forge/DesignSystem/InterfaceMetrics.swift \
                           Forge/Features/Settings/AppAppearance.swift
run interface-size-test    Forge/Platform/Appearance.swift \
                           Forge/DesignSystem/Theme.swift \
                           Forge/DesignSystem/InterfaceMetrics.swift \
                           Forge/Features/Settings/InterfaceSize.swift \
                           Forge/Features/Extensions/Model/ExtensionFormMetrics.swift
run palette-placement-test Forge/Platform/Appearance.swift \
                           Forge/DesignSystem/Theme.swift \
                           Forge/DesignSystem/InterfaceMetrics.swift \
                           Forge/Features/Settings/InterfaceSize.swift \
                           Forge/Palette/PalettePlacement.swift
run scroll-reveal-test     Forge/DesignSystem/Scrolling/SelectionReveal.swift
run redaction-test         Forge/DesignSystem/RedactedPlaceholder.swift
run keyboard-focus-test    Forge/DesignSystem/Interaction/KeyboardFocus.swift
run ai-instructions-test   Forge/Features/AI/Model/AIInstructions.swift \
                           Forge/Features/AI/Model/AIPreamble.swift
run hover-arming-test      Forge/Palette/HoverArming.swift \
                           Forge/Palette/PaletteState.swift \
                           Forge/Palette/PaletteMode.swift \
                           Forge/Features/Clipboard/Model/ClipboardStore.swift \
                           Forge/Features/Clipboard/Model/ClipboardFilter.swift \
                           Forge/Features/FileSearch/Model/FileSearchFilter.swift \
                           Forge/Features/Clipboard/Model/ColorValue.swift \
                           Forge/Features/Clipboard/Model/ColorFormat.swift \
                           Forge/Features/Clipboard/Model/ColorSpaces.swift \
                           Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/CustomCommands/Model/CustomCommand.swift
run palette-escape-test    Forge/Palette/PaletteMode.swift \
                           Forge/Palette/PaletteEscapeAction.swift \
                           Forge/Palette/CommandEscapeTap.swift \
                           Forge/Features/Settings/EscapeKeyBehavior.swift \
                           Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test Forge/Palette/PaletteState.swift \
                           Forge/Palette/PaletteMode.swift \
                           Forge/Palette/HoverArming.swift \
                           Forge/Features/Clipboard/Model/ClipboardStore.swift \
                           Forge/Features/Clipboard/Model/ClipboardFilter.swift \
                           Forge/Features/FileSearch/Model/FileSearchFilter.swift \
                           Forge/Features/Clipboard/Model/ColorValue.swift \
                           Forge/Features/Clipboard/Model/ColorFormat.swift \
                           Forge/Features/Clipboard/Model/ColorSpaces.swift \
                           Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    Forge/Palette/PaletteMode.swift \
                           Forge/Palette/PaletteFilterAction.swift \
                           Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/CustomCommands/Model/CustomCommand.swift
run palette-tab-test       Forge/Palette/PaletteMode.swift \
                           Forge/Palette/PaletteTabAction.swift \
                           Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/CustomCommands/Model/CustomCommand.swift
run fallback-test          Forge/Features/Launcher/Model/Fallback.swift \
                           Forge/Features/Launcher/Model/CommandID.swift \
                           Forge/Features/HotKeys/Model/HotKeyAction.swift \
                           Forge/Features/QuickActions/Model/QuickAction.swift \
                           Forge/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Forge/Features/QuickActions/Model/CustomQuickAction.swift \
                           Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/SystemActions/Model/SystemAction.swift \
                           Forge/Features/WindowManagement/Model/WindowCommand.swift
run hotkey-test            Forge/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Forge/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Forge/Features/HotKeys/Model/HyperKey.swift \
                           Forge/Platform/ASCIIKeyboardLayout.swift \
                           Forge/Features/HotKeys/Service/KeyShortcut.swift \
                           Forge/Features/HotKeys/Model/HotKeyAction.swift \
                           Forge/Features/QuickActions/Model/QuickAction.swift \
                           Forge/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Forge/Features/QuickActions/Model/CustomQuickAction.swift \
                           Forge/Features/Launcher/Model/CommandID.swift \
                           Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/SystemActions/Model/SystemAction.swift \
                           Forge/Features/WindowManagement/Model/WindowCommand.swift
run callout-test           Forge/Platform/Appearance.swift \
                           Forge/DesignSystem/Theme.swift \
                           Forge/DesignSystem/InterfaceMetrics.swift \
                           Forge/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Forge/Platform/Appearance.swift \
                           Forge/Platform/Images/IconCache.swift
run entry-icon-test        Forge/Platform/Appearance.swift \
                           Forge/Platform/Images/IconCache.swift \
                           Forge/Platform/Images/FileIconStamp.swift
run ext-icon-test          Forge/Platform/Appearance.swift \
                           Forge/Platform/Images/IconCache.swift \
                           Forge/Platform/Compression/Zlib.swift \
                           Forge/DesignSystem/Theme.swift \
                           Forge/DesignSystem/InterfaceMetrics.swift \
                           Forge/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Forge/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Forge/Features/Extensions/Model/ExtensionManifest.swift \
                           Forge/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Forge/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Forge/Features/Extensions/Model/RenderNode.swift \
                           Forge/Features/Extensions/Service/ExtensionCatalog.swift \
                           Forge/Features/Extensions/Service/ExtensionFetcher.swift \
                           Forge/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Forge/Features/Extensions/Service/ExtensionOAuthKeychain.swift \
                           Forge/Features/Extensions/Service/ExtensionOAuthSession.swift \
                           Forge/Features/Extensions/Service/ExtensionRuntime.swift \
                           Forge/Features/Extensions/Service/ExtensionIconCache.swift \
                           Forge/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Forge/Features/Extensions/UI/ExtensionImage.swift
run system-action-test     Forge/Features/SystemActions/Model/SystemAction.swift
run volume-test            Forge/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Forge/Features/WindowManagement/Model/WindowCommand.swift \
                           Forge/Features/WindowManagement/Model/WindowCycle.swift \
                           Forge/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Forge/Features/WindowManagement/Model/WindowActionMemory.swift
run space-gesture-test     Forge/Features/WindowManagement/Model/WindowCommand.swift \
                           Forge/Features/WindowManagement/Model/SpaceGesture.swift
run window-layout-test     Forge/Features/WindowManagement/Model/WindowCommand.swift \
                           Forge/Features/WindowManagement/Model/WindowCycle.swift \
                           Forge/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Forge/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Forge/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Forge/Features/WindowManagement/Model/WindowLayout.swift \
                           Forge/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Forge/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Forge/Features/WindowManagement/Model/WindowLayoutStore.swift
run custom-command-test    Forge/Platform/PseudoTerminal.swift \
                           Forge/Features/CustomCommands/Model/CustomCommand.swift \
                           Forge/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Forge/Features/CustomCommands/Service/ShellCommandRunner.swift \
                           Forge/Features/CustomCommands/Service/CustomCommandArgumentSession.swift
run uninstall-test         Forge/Features/Uninstall/Model/UninstallTarget.swift \
                           Forge/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Forge/Features/Uninstall/Model/UninstallRules.swift \
                           Forge/Features/Uninstall/Model/UninstallProtection.swift \
                           Forge/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Forge/Features/Quicklinks/Model/Quicklink.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Forge/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Forge/Features/Quicklinks/Model/RaycastQuicklinkImport.swift
run slow snippets-test     Forge/Platform/NotificationToken.swift \
                           Forge/Platform/HealthTicker.swift \
                           Forge/Platform/AccessibilityText.swift \
                           Forge/Features/Snippets/Model/*.swift \
                           Forge/Features/Snippets/Service/*.swift \
                           Forge/Features/TextInjection/Service/*.swift
run notes-test             Forge/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Forge/Features/Notes/Model/*.swift \
                           Forge/Features/Notes/Service/*.swift
run notes-editor-test      Forge/Platform/Signposts.swift \
                           Forge/Platform/Appearance.swift \
                           Forge/DesignSystem/Theme.swift \
                           Forge/DesignSystem/InterfaceMetrics.swift \
                           Forge/Features/TextInjection/Service/InjectableTextView.swift \
                           Forge/Features/Notes/Model/NoteDocument.swift \
                           Forge/Features/Notes/UI/NoteTextView.swift \
                           Forge/Features/Notes/UI/NoteEditorView.swift
run slow -O raycast-test   Forge/Features/Backup/Model/RaycastImportError.swift \
                           Forge/Features/Backup/Service/RaycastDecoder.swift \
                           Forge/Features/Backup/Service/Scrypt.swift \
                           Forge/Platform/Compression/Zlib.swift
run settings-backup-test   Forge/Features/Settings/AppSettingsKey.swift \
                           Forge/Features/Backup/Model/SettingsBackupCoverage.swift
run backup-archive-test    Forge/Platform/AppPaths.swift \
                           Forge/Features/Backup/Model/BackupArchive.swift \
                           Forge/Features/Backup/Model/BackupBundle.swift \
                           Forge/Features/Backup/Model/BackupCategory.swift \
                           Forge/Features/Backup/Model/BackupClipboardItem.swift \
                           Forge/Features/Backup/Model/BackupManifest.swift \
                           Forge/Features/Backup/Service/BackupStaging.swift
E=Forge/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-refresh-test       $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-metadata-test      $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ext-store-test         $E/Model/ExtensionRegistry.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-form-test          $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ext-list-key-test.swift
run ext-accessory-test     $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ext-test          -parse-as-library \
                           Forge/Platform/Appearance.swift \
                           Forge/Platform/Images/IconCache.swift \
                           Forge/DesignSystem/Theme.swift \
                           Forge/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionOAuthKeychain.swift \
                           $E/Service/ExtensionOAuthSession.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Forge/Platform/Compression/Zlib.swift
run settings-history-test  Forge/Features/Settings/SettingsTab.swift \
                           Forge/Features/Settings/SettingsHistory.swift \
                           Forge/Features/Settings/SettingsAnchor.swift \
                           Forge/Features/Settings/SettingsNavigationState.swift \
                           Forge/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift
run updates-test           Forge/Features/Updates/Model/*.swift \
                           Forge/Features/Updates/Service/BundleSignature.swift
run support-test           Forge/Features/Support/Model/*.swift
run ai-provider-test       Forge/Features/Settings/AppSettingsKey.swift \
                           Forge/Features/AI/Model/*.swift \
                           Forge/Features/AI/Settings/AISettingsStore.swift
run ai-chat-test           Forge/Features/AI/Model/AIRequest.swift \
                           Forge/Features/AI/Model/AIAttachmentPolicy.swift \
                           Forge/Features/AI/Model/AIRetention.swift \
                           Forge/Features/AI/Model/AITool.swift \
                           Forge/Features/AI/Model/JSONValue.swift \
                           Forge/Features/AI/Model/ChatMessage.swift \
                           Forge/Features/AI/Model/ChatSession.swift \
                           Forge/Features/AI/Model/MarkdownBlock.swift \
                           Forge/Features/AI/Service/AIProvider.swift \
                           Forge/Features/AI/Service/ChatHistoryStore.swift \
                           Forge/Features/AI/Service/AIToolLoopProvider.swift \
                           Forge/Features/AI/UI/AIChatState.swift
run mcp-test               Forge/Features/Settings/AppSettingsKey.swift \
                           Forge/Features/AI/Model/AIConnection.swift \
                           Forge/Features/AI/Model/AppleIntelligence.swift \
                           Forge/Features/AI/Model/AITool.swift \
                           Forge/Features/AI/Model/JSONValue.swift \
                           Forge/Features/MCP/Model/*.swift \
                           Forge/Features/MCP/Settings/MCPSettingsStore.swift
run -O text-diff-test      Forge/Features/QuickActions/Model/TextDiffEngine.swift
run index text-diff-performance Forge/Features/QuickActions/Model/TextDiffEngine.swift
run quick-action-test      Forge/Features/Settings/AppSettingsKey.swift \
                           Forge/Features/AI/Model/AIConnection.swift \
                           Forge/Features/AI/Model/AppleIntelligence.swift \
                           Forge/Features/AI/Model/ChatGPTSubscription.swift \
                           Forge/Features/AI/Model/InstalledAI.swift \
                           Forge/Features/QuickActions/Model/*.swift \
                           Forge/Features/QuickActions/Settings/QuickActionSettingsStore.swift
run apple-intelligence-test Forge/Features/Settings/AppSettingsKey.swift \
                           Forge/Features/AI/Model/*.swift \
                           Forge/Features/AI/Service/AIProvider.swift \
                           Forge/Features/AI/Service/AppleIntelligenceProvider.swift
run slow mcp-stdio-test    Forge/Platform/ExecutableLocator.swift \
                           Forge/Platform/KeychainSecretStore.swift \
                           Forge/Features/Settings/AppSettingsKey.swift \
                           Forge/Features/AI/Model/AIConnection.swift \
                           Forge/Features/AI/Model/AppleIntelligence.swift \
                           Forge/Features/AI/Model/AITool.swift \
                           Forge/Features/AI/Model/AIStreamDecoder.swift \
                           Forge/Features/AI/Model/AIRequest.swift \
                           Forge/Features/AI/Model/JSONValue.swift \
                           Forge/Features/MCP/Model/*.swift \
                           Forge/Features/MCP/Service/*.swift
run slow codex-turn-test   Forge/Platform/AppPaths.swift \
                           Forge/Features/AI/Model/*.swift \
                           Forge/Features/AI/Service/AIProvider.swift \
                           Forge/Features/AI/Service/ChatGPTSubscriptionManager.swift \
                           Forge/Features/AI/Service/CodexAppServerClient.swift \
                           Forge/Platform/ExecutableLocator.swift \
                           Forge/Features/AI/Service/CodexTurnRunner.swift
run installed-ai-test     Forge/Features/AI/Model/*.swift \
                          Forge/Features/AI/Service/AIProvider.swift \
                          Forge/Platform/ExecutableLocator.swift \
                          Forge/Features/AI/Service/InstalledCLIProvider.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${FORGE_TEST_JOBS:-$(sysctl -n hw.ncpu)}"
# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n%d harness(es) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
    exit 1
fi
echo
if [ -n "$only" ]; then echo "$only passed."; else echo "All $ran harnesses passed."; fi
