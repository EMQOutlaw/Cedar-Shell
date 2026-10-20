import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."
import "../../components"
import "../../modules"
import "../../services"

ShellRoot {
    readonly property var expected: EXPECTED_THEME_FIXTURE
    FloatingWindow {
        visible: true
        implicitWidth: 1080
        implicitHeight: 1440
        Rectangle {
            id: canvas
            anchors.fill: parent
            color: Theme.background
            ColumnLayout {
                anchors { left:parent.left; right:parent.right; top:parent.top; margins:24 }
                spacing:16
                GlowText { text:expected.label; font.pixelSize:28; color:Theme.text }
                AppearanceSettings { active:true; Layout.fillWidth:true }
            }
        }
        Timer {
            interval:700; running:true
            onTriggered: {
                for (const key of Object.keys(expected.palette)) {
                    if (String(Theme[key]).toLowerCase() !== expected.palette[key].toLowerCase()) {
                        console.error("FAIL: " + expected.name + " token " + key + " = " + Theme[key]);
                        Qt.exit(1);
                        return;
                    }
                }
                canvas.grabToImage(result => {
                    const destination=Quickshell.env("CEDAR_THEME_SCREENSHOT");
                    if (destination && !result.saveToFile(destination)) {
                        console.error("FAIL: screenshot was not saved");
                        Qt.exit(1);
                        return;
                    }
                    console.log("PASS: bundled theme " + expected.name);
                    Qt.quit();
                });
            }
        }
    }
    Component.onCompleted: {
        SettingsInfo.data={theme:expected.name,themes:BUNDLED_THEMES_FIXTURE};
        SettingsInfo.themePreview={name:expected.name, palette:expected.palette};
    }
}
