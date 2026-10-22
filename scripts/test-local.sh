#!/bin/bash
# Tests en local, sans les classes qui ouvrent une fenêtre à l'écran (elles tournent en CI : `swift test`).
# Options passées telles quelles à `swift test` : scripts/test-local.sh --filter FanControllerTests
#
# Liste à tenir à jour ici. Une classe y entre dès qu'un de ses tests affiche un panneau :
#   grep -rln -E "orderFront|makeKeyAndOrderFront|showWindow|NotchHarness.*measure|\.measure\(" Tests/
#   (ou qu'il passe par NotchController : togglePanelFromKeyboard, mouseDown…).
# Une entrée sans « Tests » final est un préfixe de famille (EarTabs → EarTabsGestureTests, EarTabsHoverTests…).
set -euo pipefail
cd "$(dirname "$0")/.."

WINDOW_TESTS=(
    # Affichent un panneau (orderFrontRegardless, directement ou par NotchController / NotchHarness.measure).
    EarTabs
    TabEditing
    FootprintTests
    GallerySnapshotTests
    LayoutTests
    NotesSnapshotTests
    OptionalClaudeTests
    QuickSettingsSnapshotTests
    ShelfSnapshotTests
    ShelfTests
    ShellControllerTests
    TimerSnapshotTests
    WindowLevelTests
    # Pas de fenêtre trouvée à la lecture du code (contrôleurs sans affichage), gardées par précaution.
    BubbleTests
    ClipboardInteractionTests
    MessagesTests
    ProfilesTests
    SetupAssistantTests
)

ARGS=(--parallel)
for name in "${WINDOW_TESTS[@]}"; do ARGS+=(--skip "$name"); done
exec swift test "${ARGS[@]}" "$@"
