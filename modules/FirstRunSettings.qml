import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    objectName: "firstRunPage"
    property bool active: false
    signal navigate(string page)
    readonly property var steps: ["Welcome", "Desktop handoff", "Display & input", "Applications", "Privacy", "Ready"]
    property string confirming: ""
    spacing: Theme.spaceLg
    onActiveChanged: if(active) SetupFlow.run("status")
    Component.onCompleted: if(active) SetupFlow.run("status")
    GlowText { text:"SETUP " + (SetupFlow.step+1) + " / 6"; color:Theme.muted; font.pixelSize:Theme.small }
    Flow {
        Layout.fillWidth:true;spacing:Theme.spaceSm
        Repeater { model:root.steps; StationButton { required property string modelData; required property int index; text:modelData; checked:SetupFlow.step===index; onClicked:SetupFlow.step=index } }
    }
    GlowText { text:root.steps[SetupFlow.step];font.pixelSize:Theme.title;Layout.fillWidth:true;wrapMode:Text.WordWrap }
    GlowText {
        Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted
        text:["A living desktop environment for Hyprland. Preview it, review the handoff, then keep it or return to your previous desktop. Your applications and display arrangement stay in place.",
              "Review the actual desktop roles below. The existing locker stays in place until Trailwatch passes its local password and secure-unlock tests. Retained providers are shown explicitly.",
              "Keep your existing monitor arrangement and input preferences, or adjust them in Settings. Display changes use a timed recovery check.",
              "Choose installed applications for everyday tasks. CEDAR keeps your current associations until you select a replacement.",
              "External services and sensitive history are off by default. These preferences apply immediately; no account is required.",
              "A running preview or successful file copy does not prove desktop adoption. Review the recorded session state before keeping CEDAR or enabling it at login."][SetupFlow.step]
    }
    ColumnLayout {
        visible:SetupFlow.step===1;Layout.fillWidth:true;spacing:Theme.spaceMd
        StationToggle { Layout.fillWidth:true;label:"Use CEDAR Go";description:"Replace only the reviewed launcher shortcut.";checked:SetupFlow.launcher;onToggled:value=>SetupFlow.launcher=value }
        StationToggle { Layout.fillWidth:true;label:"Verify and use Trailwatch";description:"Authentication happens in the existing local security window. No password is entered here.";checked:SetupFlow.trailwatch;onToggled:value=>SetupFlow.trailwatch=value }
        StationButton { text:"Inspect desktop and review plan";enabled:!SetupFlow.busy;onClicked:SetupFlow.run("plan") }
        Repeater {
            model:SetupFlow.plan ? Object.keys(SetupFlow.plan.roles):[]
            SettingRow { required property string modelData;Layout.fillWidth:true;title:modelData;description:SetupFlow.plan?.roles[modelData] || "" }
        }
        GlowText { visible:SetupFlow.plan!==null;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted;text:(SetupFlow.plan?.mode || "")+" · "+(SetupFlow.plan?.recovery || "") }
        StationButton { visible:SetupFlow.plan!==null;text:"Approve this plan and try CEDAR";accent:Theme.green;enabled:!SetupFlow.busy;onClicked:SetupFlow.run("try",true) }
    }
    Flow { visible:SetupFlow.step===2;Layout.fillWidth:true;spacing:8
        StationButton { text:"Displays";onClicked:root.navigate("displays") }
        StationButton { text:"Input";onClicked:root.navigate("input") }
    }
    Loader { visible:SetupFlow.step===3;active:visible;Layout.fillWidth:true;sourceComponent:Component { DefaultAppsSettings { active:root.active && SetupFlow.step===3 } } }
    ColumnLayout {
        visible:SetupFlow.step===4;Layout.fillWidth:true
        StationToggle { Layout.fillWidth:true;label:"Local-only mode";description:"Block CEDAR-initiated weather, location and remote artwork requests.";checked:Config.saved.localOnly;onToggled:value=>Config.set("localOnly",value) }
        StationToggle { Layout.fillWidth:true;label:"Clipboard history";description:"Opt in to bounded local history. It clears when locked.";checked:Config.saved.clipboardHistory;onToggled:value=>Config.set("clipboardHistory",value) }
        StationToggle { Layout.fillWidth:true;label:"Desktop Trails";description:"Opt in to recent local navigation history.";checked:Config.saved.forestTrails;onToggled:value=>Config.set("forestTrails",value) }
    }
    ColumnLayout {
        visible:SetupFlow.step===5;Layout.fillWidth:true
        GlowText { Layout.fillWidth:true;wrapMode:Text.WordWrap;text:"Session: "+(SetupFlow.status.mode || SetupFlow.status.stage)+(SetupFlow.status.login ? " · selected for login":" · login activation not confirmed");color:Theme.text }
        GlowText { visible:!!SetupFlow.status.error;Layout.fillWidth:true;wrapMode:Text.WordWrap;text:SetupFlow.status.error || "";color:Theme.amber }
        Flow { Layout.fillWidth:true;spacing:8
            StationButton { text:"Refresh status";enabled:!SetupFlow.busy;onClicked:SetupFlow.run("status") }
            StationButton { text:"Keep this session";visible:SetupFlow.status.stage==="trial";enabled:!SetupFlow.busy;onClicked:root.confirming="keep" }
            StationButton { text:"Review login activation";visible:SetupFlow.status.stage==="kept" && !SetupFlow.status.login;enabled:!SetupFlow.busy;onClicked:SetupFlow.run("activation-plan") }
            StationButton { text:"Restore previous desktop";visible:["trial","kept","failed","restore-requested"].includes(SetupFlow.status.stage);enabled:!SetupFlow.busy;onClicked:root.confirming="restore" }
        }
        GlowText { visible:SetupFlow.loginPlan!==null;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted;text:(SetupFlow.loginPlan?.path || "")+"\n"+(SetupFlow.loginPlan?.change || "") }
        StationButton { visible:SetupFlow.loginPlan!==null && !SetupFlow.status.login;text:"Approve reviewed login change";enabled:!SetupFlow.busy;onClicked:root.confirming="activate" }
        GlowText { visible:root.confirming!=="";Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.amber;text:root.confirming==="activate" ? "Prepare the reviewed CEDAR startup entry for future logins? cedar restore reverses this integration." : root.confirming==="restore" ? "Restore the previous desktop integration? Later manual edits remain protected." : "Keep the current CEDAR trial for this session?" }
        RowLayout { visible:root.confirming!=="";StationButton { text:"Confirm";onClicked:{SetupFlow.run(root.confirming,true);root.confirming="";} } StationButton { text:"Cancel";onClicked:root.confirming="" } }
    }
    GlowText { visible:SetupFlow.busy || !!SetupFlow.error;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:SetupFlow.error ? Theme.amber:Theme.muted;text:SetupFlow.error || "Waiting for the requested operation to finish…" }
    GlowText { visible:Config.testMode;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.amber;text:"Isolated preview. Desktop operations are disabled here." }
    RowLayout { Layout.fillWidth:true
        StationButton { text:"Back";enabled:SetupFlow.step>0;onClicked:SetupFlow.step-- }
        Item { Layout.fillWidth:true }
        StationButton { text:SetupFlow.step===5 ? "Done":"Next";onClicked:SetupFlow.step===5 ? root.navigate("overview"):SetupFlow.step++ }
    }
}
