import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "components"

// A test application: one ordinary window showing the time the way CEDAR
// formats it. No session lock, notifications, wallpaper or layer surfaces.
// Run with:  qs -p clock-test.qml
ShellRoot {
    id: root
    settings.watchFiles: false
    property date now: new Date()

    // Ticks once a second only while the window is on screen.
    Timer {
        interval: 1000
        repeat: true
        running: window.visible
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    IpcHandler {
        target: "clock"
        function time(): string { return Config.formatTime(root.now); }
        function date(): string { return Config.formatDate(root.now); }
        function quit(): void { Qt.quit(); }
    }

    FloatingWindow {
        id: window
        title: "CEDAR — Clock test"
        visible: true
        color: Theme.background
        implicitWidth: 520
        implicitHeight: 300
        onVisibleChanged: if (!visible) Qt.quit()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padding
            spacing: Theme.spaceMd

            GlowText {
                Layout.fillWidth: true
                text: "TEST APPLICATION · local clock / no desktop takeover"
                color: Theme.amber
                font.pixelSize: Theme.small
                wrapMode: Text.WordWrap
            }

            ChamferFrame {
                Layout.fillWidth: true
                Layout.fillHeight: true
                cut: Theme.chamfer
                fill: Qt.alpha(Theme.surface, .88)
                stroke: Qt.alpha(Theme.teal, .16)
                topLine: true
                topLineColor: Theme.teal

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spaceSm
                    Accessible.role: Accessible.StaticText
                    Accessible.name: "Clock: " + Config.formatTime(root.now) + ", " + Config.formatDate(root.now)

                    GlowText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "LOCAL TIME"
                        font.pixelSize: Theme.small
                        font.letterSpacing: 1.4
                        color: Theme.muted
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.spaceSm
                        GlowText {
                            text: Config.timeDigits(root.now)
                            glow: true
                            color: Theme.green
                            font.pixelSize: Theme.title * 3
                            font.weight: Font.DemiBold
                        }
                        GlowText {
                            text: Qt.formatDateTime(root.now, "ss")
                            color: Theme.teal
                            font.pixelSize: Theme.title
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: Theme.spaceMd
                        }
                        GlowText {
                            visible: !Config.clock24
                            text: Qt.formatDateTime(root.now, "AP")
                            color: Theme.muted
                            font.pixelSize: Theme.title
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: Theme.spaceMd
                        }
                    }
                    GlowText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Config.formatDate(root.now)
                        font.family: Theme.labelFont
                        font.pixelSize: Math.round(18 * Theme.fontScale)
                        color: Theme.text
                    }
                }
            }

            GlowText {
                Layout.fillWidth: true
                text: (Config.clock24 ? "24-hour" : "12-hour") + " · " + Config.dateStyle + " · follows Settings › Clock (settings.json is read live)"
                color: Theme.muted
                font.pixelSize: Theme.small
                wrapMode: Text.WordWrap
            }
        }
    }
}
