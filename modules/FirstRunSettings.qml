import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    objectName: "firstRunPage"
    property bool active: false
    readonly property var steps: ["Welcome", "Desktop handoff", "Privacy", "Ready"]
    readonly property int step: Math.max(0, Math.min(SetupFlow.step, steps.length - 1))
    property string confirming: ""
    spacing: Theme.spaceLg
    onActiveChanged: if(active) SetupFlow.run("status")
    Component.onCompleted: if(active) SetupFlow.run("status")

    // Stepper: equal-width steps; a line leads to the next one.
    RowLayout {
        Layout.fillWidth: true; spacing: 6
        Repeater {
            model: root.steps
            StationButton {
                id: stepItem
                required property string modelData
                required property int index
                readonly property bool here: root.step === index
                readonly property bool done: index < root.step
                Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 40; padding: 4
                checked: here
                Accessible.name: "Step " + (index + 1) + ": " + modelData
                onClicked: SetupFlow.step = index
                background: Rectangle { radius: Theme.controlRadius; color: stepItem.hovered && !stepItem.here ? Qt.alpha(Theme.teal, .04) : Theme.transparent; border.width: stepItem.visualFocus ? Theme.focusWidth : 0; border.color: Theme.green }
                contentItem: RowLayout {
                    spacing: 8
                    Rectangle {
                        implicitWidth: 26; implicitHeight: 26; radius: 13
                        color: stepItem.here ? Qt.alpha(Theme.green, .16) : stepItem.done ? Qt.alpha(Theme.teal, .10) : Theme.transparent
                        border.width: 1; border.color: stepItem.here ? Theme.green : stepItem.done ? Qt.alpha(Theme.teal, .6) : Qt.alpha(Theme.teal, .2)
                        Text { anchors.centerIn: parent; text: stepItem.done ? "✓" : String(stepItem.index + 1); font.family: Theme.dataFont; font.pixelSize: 11; color: stepItem.here ? Theme.green : Theme.text }
                    }
                    Text { visible: root.width > 620 || stepItem.here; text: stepItem.modelData; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: stepItem.here ? Theme.green : Theme.muted; elide: Text.ElideRight; Layout.maximumWidth: 140 }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; opacity: stepItem.index < root.steps.length - 1 ? 1 : 0; color: stepItem.done ? Qt.alpha(Theme.teal, .5) : Qt.alpha(Theme.teal, .15) }
                }
            }
        }
    }

    // Welcome
    SettingsSection {
        visible: root.step === 0; emphasis: true; accent: Theme.green
        heading: "Install it. Try it. Keep it or go back."
        caption: "A living desktop environment for Hyprland. Your applications, display arrangement and existing desktop stay in place while you decide."
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 620 ? 1 : 3; columnSpacing: 10; rowSpacing: 10
            Readout { label: "Try"; value: "Supervised trial"; detail: "CEDAR runs beside a recovery supervisor. If anything fails, your previous desktop returns."; lit: true }
            Readout { label: "Keep"; value: "Your decision"; detail: "Nothing becomes permanent until you confirm the running session."; lit: true; tone: Theme.teal }
            Readout { label: "Go back"; value: "Recorded restore"; detail: "Every change is journaled, and later edits of your own are protected."; lit: true; tone: Theme.teal }
        }
    }

    // Desktop handoff
    SettingsSection {
        visible: root.step === 1
        heading: "Desktop handoff"
        caption: "Review the actual desktop roles. The existing locker stays in place until Trailwatch passes its local password and secure-unlock tests."
        StationToggle { Layout.fillWidth:true;label:"Use CEDAR Go";description:"Replace only the reviewed launcher shortcut.";checked:SetupFlow.launcher;onToggled:value=>SetupFlow.launcher=value }
        StationToggle { Layout.fillWidth:true;label:"Verify and use Trailwatch";description:"Authentication happens in the existing local security window. No password is entered here.";checked:SetupFlow.trailwatch;onToggled:value=>SetupFlow.trailwatch=value }
        StationButton { text:SetupFlow.plan ? "Inspect again" : "Inspect desktop and review plan";enabled:!SetupFlow.busy;onClicked:SetupFlow.run("plan") }
        Repeater {
            model:SetupFlow.plan ? Object.keys(SetupFlow.plan.roles):[]
            SettingRow { required property string modelData;Layout.fillWidth:true;title:modelData;description:SetupFlow.plan?.roles[modelData] || "" }
        }
        GlowText { visible:SetupFlow.plan!==null;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted;font.pixelSize:Theme.small;text:(SetupFlow.plan?.mode || "")+" · "+(SetupFlow.plan?.recovery || "") }
        StationButton { visible:SetupFlow.plan!==null;text:"Approve this plan and try CEDAR";accent:Theme.green;checked:true;enabled:!SetupFlow.busy;onClicked:SetupFlow.run("try",true) }
    }

    // Privacy (read-only summary; each preference has one home)
    SettingsSection {
        visible: root.step === 2
        heading: "Private by default"
        caption: "External services and sensitive history start off. This is what is currently enabled; each preference is changed in its own page."
        Repeater {
            model: [
                {title:"Local-only mode", on:Config.localOnly, where:"Desktop", detail:"Blocks CEDAR weather, location and remote artwork requests."},
                {title:"Weather access", on:Config.saved.weatherEnabled && !Config.localOnly, where:"Desktop", detail:"Open-Meteo forecasts for a saved or approximate location."},
                {title:"Clipboard history", on:Config.saved.clipboardHistory, where:"CEDAR Core", detail:"Bounded, memory-only, cleared when locked."},
                {title:"Trails", on:Config.saved.forestTrails, where:"CEDAR Core", detail:"Session-only application and navigation history."}
            ]
            SettingRow {
                required property var modelData
                Layout.fillWidth: true; title: modelData.title; description: modelData.detail + "  Set in " + modelData.where + "."
                StatusPill { text: modelData.on ? "On" : "Off"; tone: modelData.on ? Theme.green : Theme.muted }
            }
        }
    }

    // Ready
    SettingsSection {
        visible: root.step === 3
        heading: "Session"
        badge: SetupFlow.status.login ? "Selected for login" : (SetupFlow.status.stage || "unknown")
        badgeColor: SetupFlow.status.login ? Theme.green : Theme.teal
        caption: "A running preview or a successful file copy does not prove desktop adoption. Review the recorded session state before keeping CEDAR or enabling it at login."
        GlowText { Layout.fillWidth:true;wrapMode:Text.WordWrap;text:"Session: "+(SetupFlow.status.mode || SetupFlow.status.stage)+(SetupFlow.status.login ? " · selected for login":" · login activation not confirmed");color:Theme.text }
        GlowText { visible:!!SetupFlow.status.error;Layout.fillWidth:true;wrapMode:Text.WordWrap;text:SetupFlow.status.error || "";color:Theme.amber }
        Flow { Layout.fillWidth:true;spacing:8
            StationButton { text:"Refresh status";enabled:!SetupFlow.busy;onClicked:SetupFlow.run("status") }
            StationButton { text:"Keep this session";accent:Theme.green;visible:SetupFlow.status.stage==="trial";enabled:!SetupFlow.busy;onClicked:root.confirming="keep" }
            StationButton { text:"Review login activation";visible:SetupFlow.status.stage==="kept" && !SetupFlow.status.login;enabled:!SetupFlow.busy;onClicked:SetupFlow.run("activation-plan") }
            StationButton { text:"Restore previous desktop";accent:Theme.amber;visible:["trial","kept","failed","restore-requested"].includes(SetupFlow.status.stage);enabled:!SetupFlow.busy;onClicked:root.confirming="restore" }
        }
        GlowText { visible:SetupFlow.loginPlan!==null;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted;font.pixelSize:Theme.small;text:(SetupFlow.loginPlan?.path || "")+"\n"+(SetupFlow.loginPlan?.change || "") }
        StationButton { visible:SetupFlow.loginPlan!==null && !SetupFlow.status.login;text:"Approve reviewed login change";enabled:!SetupFlow.busy;onClicked:root.confirming="activate" }
        GlowText { visible:root.confirming!=="";Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.amber;text:root.confirming==="activate" ? "Prepare the reviewed CEDAR startup entry for future logins? cedar restore reverses this integration." : root.confirming==="restore" ? "Restore the previous desktop integration? Later manual edits remain protected." : "Keep the current CEDAR trial for this session?" }
        RowLayout { visible:root.confirming!=="";StationButton { text:"Confirm";accent:Theme.green;onClicked:{SetupFlow.run(root.confirming,true);root.confirming="";} } StationButton { text:"Cancel";onClicked:root.confirming="" } }
    }

    GlowText { visible:SetupFlow.busy || !!SetupFlow.error;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:SetupFlow.error ? Theme.amber:Theme.muted;text:SetupFlow.error || "Waiting for the requested operation to finish…" }
    GlowText { visible:Config.testMode;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.amber;font.pixelSize:Theme.small;text:"Isolated preview. Desktop operations are disabled here." }
    RowLayout { Layout.fillWidth:true
        StationButton { text:"Back";enabled:root.step>0;onClicked:SetupFlow.step=root.step-1 }
        Item { Layout.fillWidth:true }
        StationButton { visible:root.step<root.steps.length-1;text:"Next";accent:Theme.green;onClicked:SetupFlow.step=root.step+1 }
    }
}
