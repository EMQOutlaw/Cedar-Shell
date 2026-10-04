pragma ComponentBehavior: Bound
import QtQuick
import "../.."
import "../../services"
import "Policy.js" as Policy

Item {
    id: root
    required property date date
    property bool active: false
    property string lockLabel: "SESSION SECURED"
    readonly property var sun: Policy.solar(date, Config.latitude, Config.longitude)
    readonly property bool sunAvailable: !!sun && sun.dawn !== null && sun.dusk !== null && sun.sunrise !== null
    readonly property real dayProgress: sunAvailable ? Math.max(0, Math.min(1, (date.getTime() - sun.dawn) / (sun.dusk - sun.dawn))) : 0
    readonly property bool daylight: sunAvailable && date.getTime() >= sun.dawn && date.getTime() <= sun.dusk
    readonly property real seconds: date.getSeconds()
    readonly property var nextSun: {
        if (!sunAvailable)
            return null;
        if (date.getTime() < sun.sunrise)
            return sun.sunrise;
        const tomorrow = new Date(date);
        tomorrow.setDate(tomorrow.getDate() + 1);
        return Policy.solar(tomorrow, Config.latitude, Config.longitude)?.sunrise;
    }
    onSunChanged: if (active)
        dial.requestPaint()
    onActiveChanged: if (active)
        dial.requestPaint()
    onDateChanged: if (active)
        dial.requestPaint()
    function stamp(value) {
        return value === null || value === undefined ? "—" : Config.formatTime(new Date(value));
    }
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * .83
        height: width
        radius: width / 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        Rectangle {
            anchors.fill: parent
            anchors.margins: 12
            radius: width / 2
            color: Theme.background
            border.color: Qt.alpha(Theme.border, .5)
        }
    }
    Canvas {
        id: dial
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const cx = width / 2, cy = height / 2, r = width * .44;
            function point(radius, angle) {
                return [cx + radius * Math.cos(angle), cy + radius * Math.sin(angle)];
            }
            function arc(radius, start, end, color, line) {
                c.beginPath();
                c.strokeStyle = color;
                c.lineWidth = line;
                c.arc(cx, cy, radius, start, end);
                c.stroke();
            }
            // Sixty fencepost marks form the seconds trail. No animation loop.
            for (let i = 0; i < 60; i++) {
                const a = i / 60 * Math.PI * 2 - Math.PI / 2, p = point(r, a), q = point(r - (i % 5 === 0 ? 12 : 5), a);
                c.beginPath();
                c.strokeStyle = i === root.seconds && !Theme.reducedMotion ? Theme.green : i % 5 === 0 ? Theme.muted : Theme.border;
                c.lineWidth = i === root.seconds && !Theme.reducedMotion ? 3 : 1;
                c.moveTo(p[0], p[1]);
                c.lineTo(q[0], q[1]);
                c.stroke();
            }
            const start = Math.PI * .8, sweep = Math.PI * 1.4;
            arc(width * .485, start, start + sweep, Qt.alpha(Theme.border, .6), 2);
            if (root.sunAvailable) {
                const fraction = t => (t - root.sun.dawn) / (root.sun.dusk - root.sun.dawn);
                arc(width * .485, start, start + sweep, Qt.alpha(Theme.teal, .25), 3);
                arc(width * .485, start + sweep * fraction(root.sun.sunrise), start + sweep * fraction(root.sun.sunset), Qt.alpha(Theme.amber, .65), 3);
                for (const t of [root.sun.dawn, root.sun.sunrise, root.sun.noon, root.sun.sunset, root.sun.dusk]) {
                    const p = point(width * .485, start + sweep * fraction(t));
                    c.beginPath();
                    c.fillStyle = Theme.amber;
                    c.arc(p[0], p[1], 3, 0, Math.PI * 2);
                    c.fill();
                }
                if (root.daylight) {
                    const p = point(width * .485, start + sweep * root.dayProgress);
                    c.beginPath();
                    c.fillStyle = Theme.white;
                    c.arc(p[0], p[1], 5, 0, Math.PI * 2);
                    c.fill();
                }
            }
        }
        Connections {
            target: Theme
            function onReducedMotionChanged() {
                dial.requestPaint();
            }
        }
    }
    Repeater {
        model: 4
        FieldText {
            required property int index
            width: 24
            height: 16
            x: root.width / 2 + root.width * .397 * Math.sin(index * Math.PI / 2) - 12
            y: root.height / 2 - root.width * .397 * Math.cos(index * Math.PI / 2) - 8
            text: String(index * 15).padStart(2, "0")
            color: Theme.muted
            font.pixelSize: 9
            horizontalAlignment: Text.AlignHCenter
        }
    }
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -width * .012
        width: parent.width * .71
        spacing: root.width * .027
        FieldText {
            width: parent.width
            text: "C E D A R   /   T R A I L W A T C H"
            font.family: Theme.labelFont
            font.pixelSize: Math.max(11, root.width * .022)
            color: Theme.teal
            horizontalAlignment: Text.AlignHCenter
        }
        FieldText {
            width: parent.width
            text: Qt.formatDateTime(root.date, "ddd").toUpperCase() + "  /  " + Qt.formatDateTime(root.date, "dd MMM yyyy").toUpperCase()
            font.pixelSize: Math.max(11, root.width * .025)
            color: Theme.muted
            horizontalAlignment: Text.AlignHCenter
        }
        FieldText {
            width: parent.width
            text: Config.timeDigits(root.date)
            font.family: Theme.labelFont
            font.bold: true
            font.pixelSize: root.width * .215
            minimumPixelSize: 40
            fontSizeMode: Text.HorizontalFit
            font.letterSpacing: -2
            color: Theme.green
            horizontalAlignment: Text.AlignHCenter
        }
        FieldText {
            width: parent.width
            text: root.lockLabel + (Config.clock24 ? "" : "   /   " + Qt.formatDateTime(root.date, "AP"))
            font.pixelSize: Math.max(10, root.width * .022)
            color: Theme.muted
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            width: parent.width * .75
            height: 1
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.border
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.width * .04
            FieldText {
                text: Weather.updatedAt ? Weather.temperature + (Trailwatch.weatherStale ? " · STALE" : "") : "SKY —"
                color: Theme.text
                font.pixelSize: Math.max(11, root.width * .029)
            }
            FieldText {
                text: "/"
                color: Theme.border
                font.pixelSize: Math.max(11, root.width * .029)
            }
            FieldText {
                text: Trailwatch.hasBattery ? "PWR " + Trailwatch.power : Trailwatch.power === "AC" ? "AC POWER" : "PWR —"
                color: Trailwatch.lowPower ? Theme.amber : Theme.text
                font.pixelSize: Math.max(11, root.width * .029)
            }
        }
    }
    Repeater {
        model: root.sunAvailable && root.width >= 440 ? ["DAWN", "RISE", "NOON", "SET", "DUSK"] : []
        FieldText {
            required property int index
            required property string modelData
            readonly property var instant: [root.sun?.dawn, root.sun?.sunrise, root.sun?.noon, root.sun?.sunset, root.sun?.dusk][index]
            readonly property real angle: Math.PI * .8 + Math.PI * 1.4 * (instant - root.sun.dawn) / (root.sun.dusk - root.sun.dawn)
            width: 82
            height: 24
            x: root.width / 2 + root.width * .485 * Math.cos(angle) - width / 2
            y: root.height / 2 + root.width * .485 * Math.sin(angle) + (index === 1 || index === 3 ? -29 : 9)
            text: modelData
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 9
            font.letterSpacing: 1
            color: Theme.muted
        }
    }
    FieldText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * .94
        width: parent.width
        text: !root.sun ? "SUN PATH · SET LOCATION" : !root.sunAvailable ? "NO TWILIGHT CROSSING TODAY" : root.daylight ? "DAYLIGHT  /  " + Math.round(root.dayProgress * 100) + "% OF CIVIL DAY" : "NIGHT WATCH  /  NEXT LIGHT " + root.stamp(root.nextSun)
        font.pixelSize: 10
        color: Theme.muted
        horizontalAlignment: Text.AlignHCenter
    }
}
