import QtQuick
import ".."
import "../components"
import "../services"

// The Focus preparation card: the shared TransactionHudCard fed from the
// Focus transaction.
TransactionHudCard {
    id: root
    leave: Focus.hudMode === "leave"
    settled: Focus.hudSettled
    failed: Focus.failures.length
    title: "CEDAR · FOCUS"
    steps: Focus.steps
    closing: Focus.hudClosing
    heading: settled ? (leave ? "Focus ended" : "Focus on") : leave ? "Restoring the desktop…" : "Quieting the desktop…"
    subtitle: leave ? "" : Focus.minutes(Focus.planned)
    footer: !settled ? Focus.readyCount + " / " + Focus.plannedCount + (leave ? " restored" : " ready")
        : leave ? (failed ? Focus.readyCount + " / " + Focus.plannedCount + " restored" : "Desktop restored")
        : failed ? Focus.readyCount + " / " + Focus.plannedCount + " changes" : Focus.minutes(Focus.planned)
    count: Focus.readyCount + " / " + Focus.plannedCount
    countWord: settled ? (leave ? (failed ? "RESTORED" : (Focus.lastSession ? Focus.minutes(Focus.lastSession.actual).toUpperCase() + " · " + Focus.lastSession.held + " HELD" : "DESKTOP RESTORED")) : failed ? "CHANGES" : "FOCUS ON") : leave ? "RESTORED" : "READY"
    accent: settled ? (failed ? Theme.warning : Theme.green) : Theme.teal
    progress: Focus.progress
}
