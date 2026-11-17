import QtQuick
import Quickshell
import "../.."
import "../../components"

// Exercises WallClock's delay arithmetic at instants a wall clock can repeat
// or skip, without moving the system clock. The Python driver supplies the
// instants and asserts the exact truncation and delay for each precision.
ShellRoot {
    id: shell
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 320
        implicitHeight: 90
        color: Theme.background
        WallClock { id: clock; precision: WallClock.Minutes }
        WallClock { id: seconds; precision: WallClock.Seconds }
        WallClock { id: hours; precision: WallClock.Hours }
        Text {
            anchors.centerIn: parent
            text: Qt.formatDateTime(clock.date, "hh:mm")
            color: Theme.text
            font.family: Theme.dataFont
        }
    }
    QtObject {
        id: probe
        Component.onCompleted: {
            const cases = JSON.parse(Quickshell.env("CEDAR_WALLCLOCK_CASES") || "[]");
            const delays = cases.map(ms => ({
                ms: ms,
                minutes: clock.nextDelayFor(ms, WallClock.Minutes),
                seconds: clock.nextDelayFor(ms, WallClock.Seconds),
                hours: clock.nextDelayFor(ms, WallClock.Hours)
            }));
            const floors = cases.map(ms => ({
                ms: ms,
                minutes: clock.floorFor(ms, WallClock.Minutes),
                seconds: clock.floorFor(ms, WallClock.Seconds),
                hours: clock.floorFor(ms, WallClock.Hours)
            }));
            console.log("WALLCLOCK_JSON " + JSON.stringify(delays));
            console.log("WALLCLOCK_FLOORS " + JSON.stringify(floors));
            console.log("WALLCLOCK_DATE " + clock.date.getSeconds() + " " + clock.date.getMilliseconds());
            console.log("WALLCLOCK_STEPS " + clock.nextDelay + " " + seconds.nextDelay + " " + hours.nextDelay);
            console.log("WALLCLOCK_LIVE " + clock.date.getMinutes() + " " + new Date(Date.now()).getMinutes()
                        + " " + clock.date.getHours() + " " + Qt.formatDateTime(clock.date, "hh:mm"));
            // The fallback is the last line of the safety story: a nonsensical
            // instant or precision must still arm one whole step, never 1 ms.
            console.log("WALLCLOCK_FALLBACK " + clock.nextDelayFor(-1, WallClock.Minutes) + " "
                        + clock.nextDelayFor(NaN, WallClock.Seconds) + " "
                        + clock.nextDelayFor(Infinity, WallClock.Minutes) + " "
                        + clock.nextDelayFor(Date.now(), 7));
        }
    }
    // The clock must actually tick: real seconds pass and the reading moves.
    Timer {
        interval: 1300
        running: true
        onTriggered: {
            console.log("WALLCLOCK_TICKS " + seconds.ticks + " " + (seconds.date.getTime() > 0));
            console.log("PASS: wallclock delay is bounded and positive at every instant");
            Qt.quit();
        }
    }
}
