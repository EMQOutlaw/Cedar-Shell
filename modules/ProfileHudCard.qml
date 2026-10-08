import QtQuick
import ".."
import "../components"
import "../services"

// The Desktop Profiles preparation card: the shared TransactionHudCard fed
// from the Profiles transaction, in the profile's own accent.
TransactionHudCard {
    id: root
    readonly property string name: (Profiles.definition(Profiles.target || Profiles.active) || { label: "Profile" }).label
    leave: Profiles.hudMode === "leave"
    settled: Profiles.hudSettled
    failed: Profiles.failures.length
    title: "CEDAR · " + name.toUpperCase()
    steps: Profiles.steps
    closing: Profiles.hudClosing
    heading: settled ? (leave ? name + " ended" : name + " ready") : leave ? "Restoring the desktop…" : "Preparing " + name.toLowerCase() + "…"
    footer: !settled ? Profiles.readyCount + " / " + Profiles.plannedCount + (leave ? " restored" : " ready")
        : leave ? (failed ? Profiles.readyCount + " / " + Profiles.plannedCount + " restored" : "Desktop restored")
        : failed ? Profiles.readyCount + " / " + Profiles.plannedCount + " changes" : name + " active"
    count: Profiles.readyCount + " / " + Profiles.plannedCount
    countWord: settled ? (leave ? (failed ? "RESTORED" : "DESKTOP RESTORED") : failed ? "CHANGES" : name.toUpperCase() + " ACTIVE") : leave ? "RESTORED" : "READY"
    accent: settled ? (failed ? Theme.warning : Profiles.accentOf(Profiles.target || Profiles.active)) : Qt.tint(Theme.teal, Qt.alpha(Profiles.accentOf(Profiles.target || Profiles.active), .5))
    progress: Profiles.progress
}
