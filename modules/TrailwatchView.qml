pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."
import "../services"
import "../components"
import "../components/trailwatch"

Rectangle {
    id: root
    required property var auth
    property bool responseVisible: false
    property bool active: false
    property bool preview: false
    property bool held: false
    readonly property bool privateMode: Config.saved.lockPrivacy || Trailwatch.shielded
    readonly property bool wide: width >= 1120 && height >= 640
    readonly property real margin: width < 600 ? 16 : Math.max(24, Math.min(56, width * .035))
    readonly property real faceSize: wide ? Math.min(860, body.height - 190, body.width * .47) : Math.max(220, Math.min(380, body.height * .52, body.width - 20))
    property date date: systemClock.date
    readonly property alias terminal: terminal
    signal submitted(string value)
    // Entrance: the surface is opaque from its first frame; the lantern blooms,
    // contours and instruments settle in over about a second. One linear clock
    // drives every element through ease(), so there is a single animation.
    property real reveal: 0
    function ease(start, span) {
        const t = Math.max(0, Math.min(1, (reveal - start) / span));
        return 1 - Math.pow(1 - t, 3);
    }
    function enter() {
        entrance.stop();
        if (Theme.reducedMotion) { reveal = 1; return; }
        reveal = 0;
        entrance.start();
    }
    NumberAnimation { id: entrance; target: root; property: "reveal"; from: 0; to: 1; duration: 950 }
    Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { entrance.stop(); root.reveal = 1; } } }
    color: Theme.background
    focus: true
    function syncHold() {
        if (active !== held) {
            held = active;
            Trailwatch.viewers += active ? 1 : -1;
        }
        if (active)
            Weather.refresh();
    }
    onActiveChanged: {
        syncHold();
        if (active) {
            enter();
            Qt.callLater(terminal.refocus);
        } else {
            entrance.stop();
            reveal = 0;
            terminal.field.clear();
        }
    }
    Component.onCompleted: { syncHold(); if (active) enter(); }
    Component.onDestruction: if (held)
        Trailwatch.viewers--
    SystemClock {
        id: systemClock
        enabled: root.active
        precision: Theme.reducedMotion ? SystemClock.Minutes : SystemClock.Seconds
    }
    Keys.onPressed: event => {
        if (!root.auth.busy && event.text && /^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            terminal.field.forceActiveFocus();
            terminal.field.insert(terminal.field.cursorPosition, event.text);
            event.accepted = true;
        }
    }
    Topo {
        anchors.fill: parent
        opacity: root.ease(0, .9)
        transform: Translate { y: 24 * (1 - root.ease(0, .9)) }
    }
    // Spores drift while someone is at the lock screen and rest with Motion.
    CedarAtmosphere {
        anchors.fill: parent
        active: root.active && Config.saved.ambientIntensity > 0
        opacity: Config.saved.ambientIntensity * .45 * root.ease(.2, .7)
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * .56
        height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: Theme.transparent
            }
            GradientStop {
                position: .25
                color: Theme.background
            }
            GradientStop {
                position: .75
                color: Theme.background
            }
            GradientStop {
                position: 1
                color: Theme.transparent
            }
        }
    }
    RowLayout {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: root.margin
            rightMargin: root.margin
            topMargin: 20
        }
        spacing: 12
        height: 42
        opacity: root.ease(.1, .4)
        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            FieldText {
                text: "CEDAR"
                font.family: Theme.labelFont
                font.bold: true
                font.letterSpacing: 6 + 10 * (1 - root.ease(.1, .6))
                font.pixelSize: 24
                color: Theme.green
            }
            FieldText {
                visible: root.width >= 600
                text: "TRAILWATCH  /  FIELD INSTRUMENTS"
                font.pixelSize: 10
                font.letterSpacing: 1.5
                color: Theme.muted
            }
        }
        Rectangle {
            implicitWidth: 7
            implicitHeight: 7
            radius: 4
            color: Trailwatch.ready.warning ? Theme.amber : Theme.green
            // The lock surface stays mapped for hours; step the pulse and rest it.
            opacity: statusPulse.running ? statusPulse.value : 1
            Breath {
                id: statusPulse
                running: root.active && Motion.active
                from: 1
                to: .4
                rise: 2400
            }
        }
        FieldText {
            text: Trailwatch.ready.label
            font.pixelSize: 12
            font.letterSpacing: 1
            color: Trailwatch.ready.warning ? Theme.amber : Theme.green
        }
        StationButton {
            visible: !root.privateMode
            text: "SHIELD"
            hint: "Hide sensitive details for this lock session"
            onClicked: Trailwatch.shielded = true
        }
        FieldText {
            visible: root.privateMode && root.width >= 720
            text: "  /  PRIVACY ON"
            font.pixelSize: 10
            color: Theme.muted
        }
    }
    // The filament lights from the center outward: the light stays on.
    Rectangle {
        anchors {
            top: header.bottom
            topMargin: 12
            horizontalCenter: parent.horizontalCenter
        }
        width: (parent.width - root.margin * 2) * root.ease(.15, .6)
        height: 1
        color: Theme.border
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, 180)
            height: 1
            color: Theme.green
            opacity: .6 * (1 - root.ease(.45, .5))
        }
    }
    Item {
        id: body
        anchors {
            top: header.bottom
            topMargin: 28
            bottom: footer.top
            bottomMargin: 12
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(1800, parent.width - root.margin * 2)
        // Lantern bloom behind the watch face. Painted once per size; only
        // opacity and scale move, which the scene graph handles without repaint.
        Canvas {
            id: lantern
            readonly property real bloom: root.ease(0, .7)
            width: root.faceSize * 1.9
            height: width
            x: center.x + face.x + face.width / 2 - width / 2
            y: center.y + face.y + face.height / 2 - height / 2
            opacity: .9 * bloom
            scale: .55 + .45 * bloom
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const c = getContext("2d"); c.reset();
                const r = width / 2, g = c.createRadialGradient(r, r, 0, r, r, r);
                g.addColorStop(0, Qt.alpha(Theme.green, .13));
                g.addColorStop(.45, Qt.alpha(Theme.green, .05));
                g.addColorStop(1, Qt.alpha(Theme.green, 0));
                c.fillStyle = g; c.fillRect(0, 0, width, height);
            }
        }
        Column {
            id: center
            width: root.wide ? root.faceSize : parent.width
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.wide ? Math.max(0, (parent.height - height) / 2) : 0
            spacing: 12
            WatchFace {
                id: face
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.faceSize
                height: width
                date: root.date
                active: root.active
                lockLabel: root.preview ? "PREVIEW / NOT LOCKED" : "SESSION SECURED"
                opacity: root.ease(.08, .6)
                scale: .94 + .06 * root.ease(.08, .6)
            }
            Column {
                width: parent.width
                spacing: 4
                opacity: root.ease(.3, .45)
                transform: Translate { y: 14 * (1 - root.ease(.3, .45)) }
                FieldText {
                    width: parent.width
                    text: "07  /  FOREST STATE   ·   " + Trailwatch.forestState
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: Trailwatch.forestState === "EMBER" ? Theme.amber : Theme.teal
                    horizontalAlignment: Text.AlignHCenter
                }
                FieldText {
                    width: parent.width
                    text: Trailwatch.forestPhrase
                    font.family: Theme.labelFont
                    font.pixelSize: 19
                    color: Theme.muted
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            LockTerminal {
                id: terminal
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(460, parent.width)
                auth: root.auth
                responseVisible: root.responseVisible
                active: root.active
                preview: root.preview
                onSubmitted: value => root.submitted(value)
                opacity: root.ease(.38, .45)
                transform: Translate { y: 14 * (1 - root.ease(.38, .45)) }
            }
        }
        Flickable {
            id: left
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
            visible: root.wide
            anchors.left: parent.left
            y: Math.max(0, (parent.height - Math.max(leftColumn.height, rightColumn.height)) / 2)
            height: parent.height - y
            width: (parent.width - root.faceSize) / 2 - 30
            contentHeight: leftColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: leftColumn
                width: parent.width
                spacing: 20
                Complication {
                    width: parent.width
                    kind: "sky"
                    date: root.date
                    privateMode: root.privateMode
                    opacity: root.ease(0.3, .45)
                    transform: Translate { y: 18 * (1 - root.ease(0.3, .45)) }
                }
                Complication {
                    width: parent.width
                    kind: "trail"
                    date: root.date
                    privateMode: root.privateMode
                    opacity: root.ease(0.38, .45)
                    transform: Translate { y: 18 * (1 - root.ease(0.38, .45)) }
                }
                Complication {
                    width: parent.width
                    kind: "media"
                    date: root.date
                    privateMode: root.privateMode
                    opacity: root.ease(0.46, .45)
                    transform: Translate { y: 18 * (1 - root.ease(0.46, .45)) }
                }
            }
        }
        Flickable {
            id: right
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
            visible: root.wide
            anchors.right: parent.right
            y: left.y
            height: parent.height - y
            width: left.width
            contentHeight: rightColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: rightColumn
                width: parent.width
                spacing: 20
                Complication {
                    width: parent.width
                    kind: "power"
                    date: root.date
                    privateMode: root.privateMode
                    opacity: root.ease(0.34, .45)
                    transform: Translate { y: 18 * (1 - root.ease(0.34, .45)) }
                }
                Complication {
                    width: parent.width
                    kind: "signal"
                    date: root.date
                    privateMode: root.privateMode
                    opacity: root.ease(0.42, .45)
                    transform: Translate { y: 18 * (1 - root.ease(0.42, .45)) }
                }
                Complication {
                    width: parent.width
                    kind: "system"
                    date: root.date
                    privateMode: root.privateMode
                    opacity: root.ease(0.5, .45)
                    transform: Translate { y: 18 * (1 - root.ease(0.5, .45)) }
                }
            }
        }
        Flickable {
            id: stack
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
            visible: !root.wide
            anchors {
                top: center.bottom
                topMargin: 20
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            clip: true
            contentHeight: grid.height
            boundsBehavior: Flickable.StopAtBounds
            GridLayout {
                id: grid
                width: parent.width
                columns: root.width >= 680 ? 2 : 1
                rowSpacing: 16
                columnSpacing: 16
                Repeater {
                    model: ["sky", "trail", "power", "signal", "media", "system"]
                    Complication {
                        required property string modelData
                        required property int index
                        kind: modelData
                        date: root.date
                        privateMode: root.privateMode
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        opacity: root.ease(.3 + .06 * index, .45)
                        transform: Translate { y: 18 * (1 - root.ease(.3 + .06 * index, .45)) }
                    }
                }
            }
        }
    }
    RowLayout {
        id: footer
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            leftMargin: root.margin
            rightMargin: root.margin
            bottomMargin: 14
        }
        height: 20
        opacity: root.ease(.55, .4)
        FieldText {
            Layout.fillWidth: true
            text: root.width < 700 ? "TRAILWATCH / " + (root.privateMode ? "PRIVACY ON" : "DETAILS ON") : Trailwatch.ready.reason
            font.pixelSize: 10
            color: Theme.muted
        }
        FieldText {
            text: (!root.wide || left.contentHeight > left.height || right.contentHeight > right.height) ? "SCROLL FOR INSTRUMENTS ↓" : root.date.getHours() < 12 ? "MORNING WATCH" : root.date.getHours() >= 17 ? "EVENING WATCH" : "DAY WATCH"
            font.pixelSize: 10
            color: Theme.muted
        }
    }
}
