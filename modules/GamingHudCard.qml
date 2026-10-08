import QtQuick
import ".."
import "../components"
import "../services"

// The Gaming Mode preparation card: the shared TransactionHudCard fed from
// Gaming's transaction. It reads Gaming.steps and nothing else; the words
// below are the card's whole vocabulary for this mode.
TransactionHudCard {
    id: root
    readonly property bool forGame: Gaming.trigger === "gamemode" && !leave
    leave: Gaming.hudMode === "leave"
    settled: Gaming.hudSettled
    failed: Gaming.failures.length
    title: "CEDAR GAMING"
    steps: Gaming.steps
    closing: Gaming.hudClosing
    notInstalledIds: ["gamemode"]
    heading: settled ? (leave ? "Gaming Mode Ended" : "Gaming Mode Ready") : leave ? "Restoring system…" : forGame ? "Preparing for" : "Preparing system…"
    subtitle: forGame ? (Gaming.gameName || "game") : ""
    footer: !settled ? Gaming.readyCount + " / " + Gaming.plannedCount + (leave ? " restored" : " ready")
        : leave ? (failed ? Gaming.readyCount + " / " + Gaming.plannedCount + " restored" : "System restored")
        : failed ? Gaming.readyCount + " / " + Gaming.plannedCount + " optimizations" : "Gaming Mode Active"
    count: Gaming.readyCount + " / " + Gaming.plannedCount
    countWord: settled ? (leave ? (failed ? "RESTORED" : "SYSTEM RESTORED") : failed ? "OPTIMIZATIONS" : "GAMING MODE ACTIVE") : leave ? "RESTORED" : "READY"
    accent: settled ? (failed ? Theme.warning : Theme.success) : Theme.teal
    progress: Gaming.progress
}
