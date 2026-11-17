import QtQuick

// A wall clock that cannot schedule into the past.
//
// Quickshell's SystemClock truncates the local QDateTime to the current second
// or minute and arms a QTimer for the distance to the next whole tick. During
// a DST fall-back the truncated local time resolves to the FIRST pass through
// the repeated hour, so that distance comes out around -3600 s; Qt clamps the
// negative interval to 1 ms and the clock then re-arms the same way on every
// timeout, storming at about 1 kHz for the whole hour (quickshell #329, #1383,
// fixed upstream in 0.3.2.r7). CEDAR froze on the 2026-11-01 fall-back: 8.8 M
// warning lines, an 891 MB shell.log and a wedged render loop.
//
// This clock derives the next tick from epoch milliseconds instead. Epoch time
// never repeats, so the distance to the next whole tick is always positive, and
// it is floored at one frame and capped at one step so no arithmetic slip -
// clock step, suspend/resume, a timezone edit - can ever arm a hot timer.
//
// API mirrors the SystemClock it replaces: `date` (truncated to `precision`),
// `precision`, `enabled`, and the epoch-math helpers, which are pure so a
// harness can exercise fold and step instants without moving the system clock.
QtObject {
    id: root

    enum Precision { Hours = 1, Minutes = 2, Seconds = 3 }

    property bool enabled: true
    property int precision: WallClock.Seconds

    function stepFor(p) {
        return p === WallClock.Seconds ? 1000 : p === WallClock.Minutes ? 60000 : 3600000;
    }
    // The instant rounded down to the clock's precision.
    //
    // Never truncate with Date setters: inside a DST fold Qt's JS engine
    // resolves the mutated local time to the other occurrence of the repeated
    // hour (probe: setMilliseconds(0) on 2026-11-01 01:23 EST moves the instant
    // an hour forward), which is the same trap that broke SystemClock. Minutes
    // and seconds are truncated by epoch arithmetic — exact for every timezone,
    // because all offsets are whole minutes — and hours use the offset in effect
    // at that instant, read without mutating anything.
    function floorFor(ms, p) {
        const step = stepFor(p);
        if (p === WallClock.Hours) {
            const offset = new Date(ms).getTimezoneOffset() * 60000;
            const local = ms - offset;
            return local - (local % step) + offset;
        }
        return ms - (ms % step);
    }
    // Milliseconds until the next whole tick, always in [16, step].
    function nextDelayFor(ms, p) {
        const step = stepFor(p);
        const delay = floorFor(ms, p) + step - ms;
        return delay > 0 && delay <= step ? Math.max(16, delay) : step;
    }

    // Reading of the clock, advanced by the timer below.
    property double stamp: Date.now()
    property int ticks: 0
    readonly property date date: new Date(floorFor(stamp, precision))
    readonly property int hours: date.getHours()
    readonly property int minutes: date.getMinutes()
    readonly property int seconds: date.getSeconds()
    readonly property double nextDelay: nextDelayFor(stamp, precision)

    onEnabledChanged: if (enabled) stamp = Date.now()

    property Timer tick: Timer {
        interval: root.nextDelay
        repeat: true
        running: root.enabled
        onTriggered: { root.ticks++; root.stamp = Date.now(); }
    }
}
