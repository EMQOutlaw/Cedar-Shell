import QtQuick
import QtQuick.Controls
import Quickshell
import "../.."
import "../../modules"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 700
        implicitHeight: 1000
        color: Theme.background
        function check(value, message) { if (!value) { console.error("FAIL: " + message); Qt.exit(1); throw new Error(message); } }
        ScrollView {
            anchors.fill: parent; anchors.margins: 20
            contentWidth: availableWidth
            Item {
                id: preview
                width: window.previewWidth
                implicitHeight: panel.implicitHeight
                Rectangle { anchors.fill: parent; color: Theme.background }
                CalendarCanopy { id: panel; width: parent.width }
            }
        }
        property int previewWidth: 660
        property int step: 0
        Timer {
            interval: 250; running: true; repeat: true
            onTriggered: {
                if (window.step === 0) {
                    panel.selectedDay = 5;
                    const y = panel.month.getFullYear(), m = panel.month.getMonth();
                    const dateKey = day => Qt.formatDateTime(new Date(y, m, day), "yyyy-MM-dd");
                    CalendarFeeds.sources = [
                        { id: "one", name: "Work", provider: "google", color: "#79abd9", enabled: true, updatedAt: Date.now(), status: "ready", error: "", kind: "subscription", webUrl: "https://calendar.google.com/" },
                        { id: "two", name: "Personal", provider: "proton", color: "#62b89a", enabled: true, updatedAt: Date.now(), status: "error", error: "Provider unavailable. Saved events are shown.", kind: "subscription", webUrl: "https://calendar.proton.me/" },
                        { id: "three", name: "Family", provider: "nextcloud", color: "#d7ac69", enabled: true, updatedAt: Date.now(), status: "ready", error: "", kind: "subscription", webUrl: "https://cloud.example.org/index.php/apps/calendar/" }
                    ];
                    CalendarFeeds.events = [
                        { id: "meeting", title: "Planning meeting", start: new Date(y,m,5,9).toISOString(), end: new Date(y,m,5,10).toISOString(), allDay: false, startDate: "", endDate: "", location: "Studio", description: "Review the week's plans.", sourceId: "one", calendar: "Work", color: "#79abd9", stale: false },
                        { id: "trip", title: "Weekend away", start: new Date(y,m,4).toISOString(), end: new Date(y,m,7).toISOString(), allDay: true, startDate: dateKey(4), endDate: dateKey(7), location: "", description: "", sourceId: "two", calendar: "Personal", color: "#62b89a", stale: true }
                    ];
                    window.check(panel.agenda.length === 2, "selected day combines connected calendars");
                } else if (window.step === 1) {
                    preview.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/calendar-connected.png"));
                } else if (window.step === 2) {
                    panel.selectedDay = 6;
                    window.check(panel.agenda.length === 1 && panel.agenda[0].id === "trip", "multi-day all-day event spans days");
                    panel.selectedDay = 7;
                    window.check(panel.agenda.length === 0, "all-day end is exclusive");
                    panel.selectedDay = 5; panel.manage = true; window.previewWidth = 440;
                } else if (window.step === 3) {
                    preview.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/calendar-connections.png"));
                } else if (window.step === 4) {
                    ShellState.locked = true;
                    window.check(CalendarFeeds.events.length === 0, "lock clears event details from service memory");
                    console.log("PASS: calendar agenda, all-day dates, connection controls, narrow layout and lock privacy");
                    Qt.quit();
                }
                window.step++;
            }
        }
    }
}
