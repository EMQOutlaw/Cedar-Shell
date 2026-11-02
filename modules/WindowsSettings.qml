import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import ".."
import "../components"
import "../services"

// Settings › Windows. CEDAR-owned window-manager options written transactionally
// through scripts/desktop.py into ~/.config/cedar/hypr/generated.lua; user
// overrides in user.lua always load last. Anything left out (per-side gaps,
// gradient border rotation, open/close curves, scratchpad rules) stays with
// your own Hyprland configuration. Apply, Discard and change count live in the
// sticky bar below the page (SettingsPanel's windowsApplyBar) — reachable from
// anywhere on the page, so there is no Apply section here.
ColumnLayout {
    id: root
    spacing: 16
    objectName: "windowsPage"
    // Edits made mid-transaction (or before the follow-up snapshot refreshes
    // the baseline) would be silently overwritten; the page stays locked.
    enabled: !DesktopSettings.windowsLocked

    readonly property bool wide: width > 980
    readonly property var draft: DesktopSettings.windowsDraft
    readonly property var edits: DesktopSettings.windowsEdits
    readonly property bool dirty: DesktopSettings.windowsDirty
    readonly property bool externalChange: DesktopSettings.windowsExternalChange
    property bool resetConfirm: false
    function has(key) { return root.draft[key] !== undefined && root.draft[key] !== ""; }
    function v(key, fallback) { return root.draft[key] === undefined ? fallback : root.draft[key]; }
    function change(key, value) { DesktopSettings.editWindow(key, value); }
    function load() { DesktopSettings.loadWindows(); }
    function discard() { load() }
    Component.onCompleted: if (!DesktopSettings.windowsDirty) load()

    component WRow: SettingRow {
        property string key: ""
        objectName: key
        Layout.fillWidth: true
        visible: root.has(key)
    }
    component WCell: SettingsSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.columnSpan: root.wide ? 1 : 2
        Layout.minimumWidth: 0
    }

    GlowText {
        visible: DesktopSettings.error !== "" || DesktopSettings.message !== ""
        text: DesktopSettings.error || DesktopSettings.message
        color: DesktopSettings.error ? Theme.amber : Theme.teal
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
    }
    SettingsSurface {
        Layout.fillWidth: true; padding: 14
        visible: root.externalChange
        GlowText { text: "Window settings changed outside this page. Reload before applying changes to the same options."; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
        RowLayout { StationButton { text: "Reload"; onClicked: root.load() } }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 16

        WCell {
            heading: "Tiling"; caption: "How new windows share the screen."
            WRow { key: "layout"; title: "Tiling layout"; description: "Binary splits, master and stack, or a scrolling strip."
                ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Tiling layout"; options: [{value: "dwindle", label: "Dwindle"}, {value: "master", label: "Master"}, {value: "scrolling", label: "Scrolling"}]; current: root.v("layout", "dwindle"); onChosen: value => root.change("layout", value) } }
        }

        WCell {
            heading: "Behaviour"; caption: "How windows act when you are not looking at them."
            WRow { key: "snap_enabled"; title: "Snap floating windows"; description: "Floating windows stick to edges and other windows."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Snap floating windows"; checked: root.v("snap_enabled", true) === true; onToggled: value => root.change("snap_enabled", value) } }
            WRow { key: "no_focus_fallback"; title: "No focus fallback"; description: "On close, don't refocus the window under the cursor."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "No focus fallback"; checked: root.v("no_focus_fallback", false) === true; onToggled: value => root.change("no_focus_fallback", value) } }
            WRow { key: "allow_tearing"; title: "Allow tearing"; description: "Let windows tear instead of waiting for the frame — fastest, with visible artifacts."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Allow tearing"; checked: root.v("allow_tearing", false) === true; onToggled: value => root.change("allow_tearing", value) } }
        }

        WCell {
            heading: "Gaps"; caption: "Uniform gaps, in pixels. Per-side gaps stay in your own configuration."
            WRow { key: "gaps_in"; title: "Inner (between windows)"; description: "Space between neighbouring tiled windows."
                StationSlider { visible: typeof root.draft["gaps_in"] === "number"; Layout.fillWidth: true; from: 0; to: 50; stepSize: 1; value: Number(root.v("gaps_in", 5)); Accessible.name: "Inner gaps"; onMoved: root.change("gaps_in", Math.round(value)) }
                GlowText { visible: typeof root.draft["gaps_in"] === "string"; text: "Per-side gaps are set (" + root.draft["gaps_in"] + "). They stay in your own configuration; CEDAR only writes uniform gaps."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
            WRow { key: "gaps_out"; title: "Outer (screen edge)"; description: "Space between windows and the screen edge."
                StationSlider { visible: typeof root.draft["gaps_out"] === "number"; Layout.fillWidth: true; from: 0; to: 100; stepSize: 2; value: Number(root.v("gaps_out", 10)); Accessible.name: "Outer gaps"; onMoved: root.change("gaps_out", Math.round(value)) }
                GlowText { visible: typeof root.draft["gaps_out"] === "string"; text: "Per-side gaps are set (" + root.draft["gaps_out"] + "). They stay in your own configuration; CEDAR only writes uniform gaps."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
            WRow { key: "gaps_workspaces"; title: "Workspace gaps"; description: "Extra gap between workspaces while swiping between them."
                StationSlider { visible: typeof root.draft["gaps_workspaces"] === "number"; Layout.fillWidth: true; from: 0; to: 100; stepSize: 2; value: Number(root.v("gaps_workspaces", 0)); Accessible.name: "Workspace gaps"; onMoved: root.change("gaps_workspaces", Math.round(value)) }
                GlowText { visible: typeof root.draft["gaps_workspaces"] === "string"; text: "Per-side gaps are set (" + root.draft["gaps_workspaces"] + "). They stay in your own configuration; CEDAR only writes uniform gaps."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
        }

        WCell {
            heading: "Shape & motion"; caption: "Corner geometry and the animation master switch. Open and close curves stay in your own configuration."
            WRow { key: "rounding"; title: "Corner radius"; description: "How rounded window corners are; 0 keeps them square."
                StationSlider { Layout.fillWidth: true; from: 0; to: 24; stepSize: 1; value: Number(root.v("rounding", 0)); Accessible.name: "Corner radius"; onMoved: root.change("rounding", Math.round(value)) } }
            WRow { key: "rounding_power"; title: "Corner softness"; description: "2 is a circle; higher flattens toward square."
                StationSlider { Layout.fillWidth: true; from: 1; to: 10; stepSize: 0.5; value: Number(root.v("rounding_power", 2)); Accessible.name: "Corner softness"; onMoved: root.change("rounding_power", Math.round(value * 2) / 2) } }
            WRow { key: "animations_enabled"; title: "Animations"; description: "The master switch: motion for open, close, move and workspaces; off snaps. Open and close curves stay in your own configuration."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Animations"; checked: root.v("animations_enabled", true) === true; onToggled: value => root.change("animations_enabled", value) } }
        }

        SettingsSection {
            heading: "Border"; caption: "The frame around every window."
            Layout.fillWidth: true; Layout.columnSpan: 2; Layout.minimumWidth: 0
            WRow { key: "border_size"; title: "Thickness"; description: "Width of the frame; 0 removes it."
                StationSlider { Layout.fillWidth: true; from: 0; to: 10; stepSize: 1; value: Number(root.v("border_size", 2)); Accessible.name: "Border thickness"; onMoved: root.change("border_size", Math.round(value)) } }
            WRow { key: "col_active_border"; title: "Active border"; description: "Colour of the focused window's frame, a hex colour, or a gradient of eight-digit AARRGGBB stops and an angle (alpha first)."
                StationField { Layout.fillWidth: true; text: String(root.v("col_active_border", "")); placeholderText: String(Theme.strataAccent); Accessible.name: "Active border colour"; onCommit: root.change("col_active_border", text) } }
            WRow { key: "col_inactive_border"; title: "Inactive border"; description: "Colour of the frame around windows you are not using."
                StationField { Layout.fillWidth: true; text: String(root.v("col_inactive_border", "")); placeholderText: String(Theme.strataMuted); Accessible.name: "Inactive border colour"; onCommit: root.change("col_inactive_border", text) } }
            WRow { key: "resize_on_border"; title: "Drag to resize at edges"; description: "Grab a window's edge with the mouse to resize it."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Resize on border"; checked: root.v("resize_on_border", true) === true; onToggled: value => root.change("resize_on_border", value) } }
            WRow { key: "extend_border_grab_area"; title: "Border grab area"; description: "How many pixels past the border still grab it for resizing."
                StationSlider { Layout.fillWidth: true; from: 0; to: 50; stepSize: 1; value: Number(root.v("extend_border_grab_area", 15)); Accessible.name: "Border grab area"; onMoved: root.change("extend_border_grab_area", Math.round(value)) } }
            WRow { key: "hover_icon_on_border"; title: "Resize cursor on border"; description: "Show the resize cursor when hovering a window border."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Resize cursor on border"; checked: root.v("hover_icon_on_border", true) === true; onToggled: value => root.change("hover_icon_on_border", value) } }
            WRow { key: "resize_corner"; title: "Resize corner"; description: "Lock resizing to one corner; 0 is off."
                ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Resize corner"; options: [{value: 0, label: "Off"}, {value: 1, label: "1"}, {value: 2, label: "2"}, {value: 3, label: "3"}, {value: 4, label: "4"}]; current: Number(root.v("resize_corner", 0)); onChosen: value => root.change("resize_corner", value) } }
        }

        WCell {
            heading: "Opacity"; caption: "How solid windows are drawn, and dimming."
            WRow { key: "active_opacity"; title: "Active"; description: "Solidity of the focused window; under 100% shows through."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("active_opacity", 1)); Accessible.name: "Active opacity"; onMoved: root.change("active_opacity", Math.round(value * 100) / 100) } }
            WRow { key: "inactive_opacity"; title: "Inactive"; description: "How solid unfocused windows are drawn."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("inactive_opacity", 1)); Accessible.name: "Inactive opacity"; onMoved: root.change("inactive_opacity", Math.round(value * 100) / 100) } }
            WRow { key: "fullscreen_opacity"; title: "Fullscreen"; description: "Opacity of a window while it is fullscreen."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("fullscreen_opacity", 1)); Accessible.name: "Fullscreen opacity"; onMoved: root.change("fullscreen_opacity", Math.round(value * 100) / 100) } }
            WRow { key: "dim_inactive"; title: "Dim inactive windows"; description: "Darkens every window except the focused one."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Dim inactive windows"; checked: root.v("dim_inactive", false) === true; onToggled: value => root.change("dim_inactive", value) } }
            WRow { key: "dim_strength"; title: "Dim strength"; description: "How dark unfocused windows get while dimming is on."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("dim_strength", 0.5)); Accessible.name: "Dim strength"; onMoved: root.change("dim_strength", Math.round(value * 100) / 100) } }
            WRow { key: "dim_special"; title: "Dim special workspaces"; description: "How much the scratchpad workspace dims the desktop."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("dim_special", 0.2)); Accessible.name: "Dim special workspaces"; onMoved: root.change("dim_special", Math.round(value * 100) / 100) } }
            WRow { key: "dim_around"; title: "Dim around floating"; description: "How strongly a dim-around window darkens the rest."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("dim_around", 0.4)); Accessible.name: "Dim around floating"; onMoved: root.change("dim_around", Math.round(value * 100) / 100) } }
            WRow { key: "dim_modal"; title: "Dim modal dialogs"; description: "Darken the parent while a modal dialog is open."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Dim modal dialogs"; checked: root.v("dim_modal", false) === true; onToggled: value => root.change("dim_modal", value) } }
        }

        WCell {
            heading: "Blur"; caption: "Frosted glass behind translucent windows and the shell."
            WRow { key: "blur_enabled"; title: "Enabled"; description: "Blur behind translucent windows and the shell."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Blur enabled"; checked: root.v("blur_enabled", true) === true; onToggled: value => root.change("blur_enabled", value) } }
            WRow { key: "blur_size"; title: "Size"; description: "How far each pass spreads; pair with passes."
                StationSlider { Layout.fillWidth: true; from: 1; to: 30; stepSize: 1; value: Number(root.v("blur_size", 6)); Accessible.name: "Blur size"; onMoved: root.change("blur_size", Math.round(value)) } }
            WRow { key: "blur_passes"; title: "Passes"; description: "Times the blur repeats; more is stronger but costs GPU time."
                StationSlider { Layout.fillWidth: true; from: 1; to: 8; stepSize: 1; value: Number(root.v("blur_passes", 1)); Accessible.name: "Blur passes"; onMoved: root.change("blur_passes", Math.round(value)) } }
            WRow { key: "blur_xray"; title: "X-ray (blur shows the wallpaper)"; description: "Ignores windows beneath when blurring; lighter on the GPU."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Blur x-ray"; checked: root.v("blur_xray", false) === true; onToggled: value => root.change("blur_xray", value) } }
            WRow { key: "blur_vibrancy"; title: "Vibrancy"; description: "Boosts colour saturation seen through the blur."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("blur_vibrancy", 0)); Accessible.name: "Blur vibrancy"; onMoved: root.change("blur_vibrancy", Math.round(value * 100) / 100) } }
            WRow { key: "blur_vibrancy_darkness"; title: "Vibrancy darkness"; description: "How much vibrancy affects the dark parts of the blur."
                StationSlider { Layout.fillWidth: true; from: 0; to: 3; stepSize: 0.1; value: Number(root.v("blur_vibrancy_darkness", 0)); Accessible.name: "Blur vibrancy darkness"; onMoved: root.change("blur_vibrancy_darkness", Math.round(value * 10) / 10) } }
            WRow { key: "blur_noise"; title: "Noise"; description: "Grain over blurred areas; hides gradient banding."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.01; value: Number(root.v("blur_noise", 0)); Accessible.name: "Blur noise"; onMoved: root.change("blur_noise", Math.round(value * 100) / 100) } }
            WRow { key: "blur_contrast"; title: "Contrast"; description: "Contrast of the blurred backdrop."
                StationSlider { Layout.fillWidth: true; from: 0; to: 2; stepSize: 0.05; value: Number(root.v("blur_contrast", 1)); Accessible.name: "Blur contrast"; onMoved: root.change("blur_contrast", Math.round(value * 100) / 100) } }
            WRow { key: "blur_brightness"; title: "Brightness"; description: "Brightness of the blurred backdrop."
                StationSlider { Layout.fillWidth: true; from: 0; to: 2; stepSize: 0.05; value: Number(root.v("blur_brightness", 1)); Accessible.name: "Blur brightness"; onMoved: root.change("blur_brightness", Math.round(value * 100) / 100) } }
            WRow { key: "blur_special"; title: "Blur special workspace"; description: "Also blur behind the special (scratchpad) workspace."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Blur special workspace"; checked: root.v("blur_special", false) === true; onToggled: value => root.change("blur_special", value) } }
            WRow { key: "blur_popups"; title: "Blur popups"; description: "Blur behind popups and menus, not just windows."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Blur popups"; checked: root.v("blur_popups", false) === true; onToggled: value => root.change("blur_popups", value) } }
            WRow { key: "blur_ignore_opacity"; title: "Blur ignores opacity"; description: "Blur the backdrop even under fully transparent regions."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Blur ignores opacity"; checked: root.v("blur_ignore_opacity", false) === true; onToggled: value => root.change("blur_ignore_opacity", value) } }
            WRow { key: "blur_new_optimizations"; title: "Blur optimizations"; description: "Cache blur for speed; off only if you see artifacts."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Blur optimizations"; checked: root.v("blur_new_optimizations", true) === true; onToggled: value => root.change("blur_new_optimizations", value) } }
        }

        WCell {
            heading: "Shadows"; caption: "The soft drop shadow under every window."
            WRow { key: "shadow_enabled"; title: "Window shadows"; description: "A soft drop shadow under every window."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Window shadows"; checked: root.v("shadow_enabled", true) === true; onToggled: value => root.change("shadow_enabled", value) } }
            WRow { key: "shadow_range"; title: "Range"; description: "How far the shadow spreads from the window."
                StationSlider { Layout.fillWidth: true; from: 1; to: 100; stepSize: 1; value: Number(root.v("shadow_range", 4)); Accessible.name: "Shadow range"; onMoved: root.change("shadow_range", Math.round(value)) } }
            WRow { key: "shadow_offset_x"; title: "Horizontal offset"; description: "Shifts the shadow sideways, as if lit from one side."
                StationSlider { Layout.fillWidth: true; from: -50; to: 50; stepSize: 1; value: Number(root.v("shadow_offset_x", 0)); Accessible.name: "Shadow horizontal offset"; onMoved: root.change("shadow_offset_x", Math.round(value)) } }
            WRow { key: "shadow_offset_y"; title: "Vertical offset"; description: "Shifts the shadow up or down; positive is below."
                StationSlider { Layout.fillWidth: true; from: -50; to: 50; stepSize: 1; value: Number(root.v("shadow_offset_y", 0)); Accessible.name: "Shadow vertical offset"; onMoved: root.change("shadow_offset_y", Math.round(value)) } }
            WRow { key: "shadow_render_power"; title: "Sharpness"; description: "Higher pulls the shadow in tight; lower leaves a wide haze."
                StationSlider { Layout.fillWidth: true; from: 1; to: 4; stepSize: 1; value: Number(root.v("shadow_render_power", 3)); Accessible.name: "Shadow sharpness"; onMoved: root.change("shadow_render_power", Math.round(value)) } }
            WRow { key: "shadow_sharp"; title: "Sharp shadow"; description: "Draw the shadow with hard edges instead of a soft falloff."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Sharp shadow"; checked: root.v("shadow_sharp", false) === true; onToggled: value => root.change("shadow_sharp", value) } }
            WRow { key: "shadow_scale"; title: "Scale"; description: "Scale of the drop shadow; 1 matches the window."
                StationSlider { Layout.fillWidth: true; from: 0; to: 1; stepSize: 0.05; value: Number(root.v("shadow_scale", 1)); Accessible.name: "Shadow scale"; onMoved: root.change("shadow_scale", Math.round(value * 100) / 100) } }
            WRow { key: "shadow_color"; title: "Shadow colour"; description: "The shadow's tint, a hex colour, or eight-digit AARRGGBB (alpha first)."
                StationField { Layout.fillWidth: true; text: String(root.v("shadow_color", "")); placeholderText: String(Theme.strataFoundation); Accessible.name: "Shadow colour"; onCommit: root.change("shadow_color", text) } }
        }

        WCell {
            heading: "Glow"; caption: "A coloured halo cast behind every window."
            WRow { key: "glow_enabled"; title: "Glow behind windows"; description: "A coloured halo behind every window."
                StationToggle { Layout.fillWidth: true; accessibleLabel: "Glow behind windows"; checked: root.v("glow_enabled", false) === true; onToggled: value => root.change("glow_enabled", value) } }
            WRow { key: "glow_range"; title: "Range"; description: "How far the halo reaches past the window edge."
                StationSlider { Layout.fillWidth: true; from: 1; to: 50; stepSize: 1; value: Number(root.v("glow_range", 4)); Accessible.name: "Glow range"; onMoved: root.change("glow_range", Math.round(value)) } }
            WRow { key: "glow_render_power"; title: "Sharpness"; description: "Higher pulls the glow in tight."
                StationSlider { Layout.fillWidth: true; from: 1; to: 4; stepSize: 1; value: Number(root.v("glow_render_power", 3)); Accessible.name: "Glow sharpness"; onMoved: root.change("glow_render_power", Math.round(value)) } }
            WRow { key: "glow_color"; title: "Colour"; description: "The halo's tint, a hex colour, or eight-digit AARRGGBB (alpha first)."
                StationField { Layout.fillWidth: true; text: String(root.v("glow_color", "")); placeholderText: String(Theme.strataAccent); Accessible.name: "Glow colour"; onCommit: root.change("glow_color", text) } }
        }

        SettingsSection {
            heading: "Live workspaces"; caption: "Switch to a workspace below. Layout rules continue to belong to your Hyprland configuration."
            Layout.fillWidth: true; Layout.columnSpan: 2; Layout.minimumWidth: 0
            Flow {
                Layout.fillWidth: true; spacing: 8
                Repeater {
                    model: Hyprland.workspaces.values
                    StrataButton { required property var modelData; text: modelData.name || String(modelData.id); checked: modelData.active; onClicked: modelData.activate() }
                }
            }
            GlowText { visible: !Hyprland.workspaces.values.length; text: "Hyprland has not reported any workspaces."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            // Reset lives at the page's end (Apply and Discard are in the
            // sticky bar). Two presses confirm; CEDAR-owned options only.
            RowLayout {
                objectName: "windowsResetRow"
                Layout.fillWidth: true; spacing: 8
                StrataButton { text: root.resetConfirm ? "Confirm reset":"Reset Windows"; accent: root.resetConfirm ? Theme.amber:Theme.teal; onClicked: { if (root.resetConfirm) { DesktopSettings.apply({action: "reset-windows"}); root.resetConfirm = false; } else root.resetConfirm = true; } }
                StrataButton { visible: root.resetConfirm; text: "Cancel"; onClicked: root.resetConfirm=false }
                GlowText { visible: root.resetConfirm; text: "Restores every CEDAR-owned window option to its default."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }
}
