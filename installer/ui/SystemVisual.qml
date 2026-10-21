import QtQuick
import QtQuick.Layouts
import "../.."
import "../../components"

// A living cedar. Rings reflect completed engine operations; orbiting lights
// indicate activity only. No timer invents progress or an estimated finish time.
Item {
    id: root
    property var model
    readonly property string stage: model.stage
    readonly property bool working: ["scan", "update", "install"].includes(stage)
    readonly property bool settled: ["finish", "update-current"].includes(stage)
    readonly property bool stopped: ["error", "update-error", "attention", "interrupted"].includes(stage)
    readonly property bool animated: visible && working && model.motion
    readonly property color accent: stopped ? Theme.amber : settled ? Theme.green : Theme.teal
    readonly property real progress: settled ? 1 : ["update", "install"].includes(stage) ? model.progress : 0
    readonly property var facts: model.facts || ({})
    readonly property string status: stage === "scan" ? "READING YOUR SYSTEM"
        : stage === "update" ? "GATHERING THE LATEST"
        : stage === "install" ? "GROWING YOUR DESKTOP"
        : stage === "update-current" ? "UP TO DATE"
        : stage === "finish" ? (model.cedarRunning ? "CEDAR READY" : "CEDAR INSTALLED")
        : stopped ? "WAITING FOR YOU" : stage === "restored" ? "DESKTOP RESTORED" : "READY WHEN YOU ARE"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(Theme.background, Qt.alpha(Theme.teal, .06)) }
            GradientStop { position: 1; color: Theme.background }
        }
    }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(Theme.teal, .12) }

    ColumnLayout {
        anchors { fill: parent; margins: 32; topMargin: 38; bottomMargin: 30 }
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Text { text: "CEDAR"; color: Theme.text; font.family: Theme.labelFont; font.pixelSize: 19; font.weight: Font.DemiBold; font.letterSpacing: 5 }
            Item { Layout.fillWidth: true }
            Text { text: root.model.version ? "v" + root.model.version : "DESKTOP / EVOLVING"; color: Theme.muted; font.family: Theme.dataFont; font.pixelSize: 9; elide: Text.ElideRight; Layout.maximumWidth: 170 }
        }
        Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }
        Item {
            id: grove
            objectName: "installerGrove"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(340, root.width - 72, root.height * .47)
            Layout.preferredHeight: width
            property real fill: root.progress
            Behavior on fill { enabled: root.model.motion; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            onFillChanged: rings.requestPaint()
            // Static artwork only repaints on state, palette or size changes.
            Canvas {
                id: rings
                anchors.fill: parent
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: root
                    function onAccentChanged() { rings.requestPaint(); }
                }
                Connections {
                    target: Theme
                    function onPaletteChanged() { rings.requestPaint(); }
                }
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    const size = width, mid = size / 2;
                    c.translate(mid, mid);
                    for (let ring = 0; ring < 5; ring++) {
                        const radius = size * (.30 + ring * .043);
                        c.beginPath(); c.arc(0, 0, radius, 0, Math.PI * 2);
                        c.strokeStyle = Qt.alpha(root.accent, ring === 4 ? .18 : .07);
                        c.lineWidth = ring === 4 ? 2 : 1; c.stroke();
                    }
                    // Fine calibration marks around the progress ring.
                    for (let i = 0; i < 60; i++) {
                        const angle = i / 60 * Math.PI * 2 - Math.PI / 2;
                        const inner = size * (i % 5 === 0 ? .485 : .491);
                        c.beginPath(); c.moveTo(Math.cos(angle) * inner, Math.sin(angle) * inner);
                        c.lineTo(Math.cos(angle) * size * .50, Math.sin(angle) * size * .50);
                        c.strokeStyle = Qt.alpha(root.accent, i / 60 < grove.fill ? .8 : .17);
                        c.lineWidth = 1; c.stroke();
                    }
                    if (grove.fill > 0) {
                        c.beginPath(); c.arc(0, 0, size * .472, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * grove.fill);
                        c.strokeStyle = root.accent; c.lineWidth = 3; c.lineCap = "round"; c.stroke();
                    }
                    // A geometric cedar, with a lit spine and tiered branches.
                    c.scale(size / 340, size / 340);
                    c.beginPath(); c.moveTo(0, -101);
                    c.lineTo(36, -47); c.lineTo(20, -47); c.lineTo(57, 3);
                    c.lineTo(35, 3); c.lineTo(79, 59); c.lineTo(-79, 59);
                    c.lineTo(-35, 3); c.lineTo(-57, 3); c.lineTo(-20, -47);
                    c.lineTo(-36, -47); c.closePath();
                    const gradient = c.createLinearGradient(0, -101, 0, 59);
                    gradient.addColorStop(0, Qt.alpha(root.accent, .34));
                    gradient.addColorStop(1, Qt.alpha(root.accent, .06));
                    c.fillStyle = gradient; c.fill();
                    c.strokeStyle = Qt.alpha(root.accent, .8); c.lineWidth = 1.3; c.stroke();
                    c.beginPath(); c.moveTo(0, -78); c.lineTo(0, 83);
                    for (let level = 0; level < 3; level++) {
                        const y = -36 + level * 42, spread = 21 + level * 18;
                        c.moveTo(-spread, y); c.lineTo(0, y + 18); c.lineTo(spread, y);
                    }
                    c.moveTo(0, 70); c.lineTo(-25, 87); c.moveTo(0, 70); c.lineTo(25, 87);
                    c.strokeStyle = Qt.alpha(root.accent, .55); c.lineWidth = 1; c.stroke();
                }
            }
            // Scene-graph transforms animate these lights without repainting art.
            Item {
                id: orbit
                objectName: "installerOrbit"
                anchors.fill: parent
                visible: root.working
                RotationAnimation on rotation { running: root.animated; from: 0; to: 360; duration: 18000; loops: Animation.Infinite }
                Repeater {
                    model: 3
                    Item {
                        required property int index
                        anchors.fill: parent; rotation: index * 120
                        Rectangle {
                            x: parent.width / 2 - width / 2; y: parent.height * .071 - height / 2
                            width: 18; height: 18; radius: 9; color: Qt.alpha(root.accent, .08)
                            Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 3; color: root.accent }
                        }
                    }
                }
            }
            Repeater {
                model: 6
                Rectangle {
                    id: mote
                    required property int index
                    property real travel: 0
                    x: grove.width * (.27 + (index * .137) % .46)
                    y: grove.height * (.74 - travel * .44)
                    width: index % 2 ? 3 : 2; height: width; radius: width
                    color: root.accent
                    visible: root.animated
                    opacity: Math.sin(travel * Math.PI) * .65
                    SequentialAnimation on travel {
                        running: root.animated; loops: Animation.Infinite
                        PauseAnimation { duration: mote.index * 370 }
                        NumberAnimation { from: 0; to: 1; duration: 3400 + mote.index * 210 }
                    }
                }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8
            text: root.status; color: root.accent
            font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.5
        }
        Text {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            text: root.working && root.stage !== "scan"
                ? root.model.doneCount + " / " + root.model.operations.length + " steps complete"
                : root.settled ? "Ready for what comes next." : root.stopped ? "Your next step is on the right." : "A little care for your desktop."
            color: Theme.muted; font.family: Theme.labelFont; font.pixelSize: 16
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.working && root.model.operations.length > 0
            spacing: 5
            Repeater {
                model: root.model.operations
                Rectangle {
                    required property var modelData
                    width: Math.min(24, (root.width - 100) / Math.max(1, root.model.operations.length) - 5)
                    height: 3; radius: 1.5
                    color: ["complete", "warning", "skipped"].includes(modelData.state) ? root.accent
                        : modelData.state === "running" ? Qt.alpha(root.accent, .6) : Qt.alpha(root.accent, .14)
                    Behavior on color { enabled: root.model.motion; ColorAnimation { duration: 250 } }
                }
            }
        }
        Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }
        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Theme.teal, .14) }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                Text { Layout.fillWidth: true; text: root.facts.distro ? root.facts.distro.name : "Your desktop"; color: Theme.text; font.family: Theme.labelFont; font.pixelSize: 16; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: root.model.environment.name || "CEDAR environment"; color: Theme.muted; font.family: Theme.dataFont; font.pixelSize: 10; elide: Text.ElideRight }
            }
            Text {
                text: root.stage === "update" ? "FETCHING" : root.stage === "install" ? Math.round(root.progress * 100) + "%" : root.settled ? "✓" : "•"
                color: root.accent; font.family: Theme.dataFont; font.pixelSize: root.settled ? 22 : 12
            }
        }
    }
}
