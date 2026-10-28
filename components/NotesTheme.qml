import QtQuick
import ".."

// Field Notes in CEDAR's tokens. The toolbar, tooltips and header print read
// Theme like every other surface; the paper keeps its own paper-coloured
// tokens (Theme.paper and friends) so a sheet always looks like paper under
// the dark shell. Nothing here is a literal: change the palette, and the
// notes follow.
//
// Derived from Field Notes by OldJobobo (MIT, see licenses/Field-Notes-MIT.txt).
QtObject {
    readonly property bool nerdIcons: Theme.nerdFont

    // Chrome: the tool island and its buttons.
    readonly property color text: Theme.text
    readonly property color accent: Theme.teal
    readonly property color danger: Theme.ember
    readonly property color background: Theme.glass
    readonly property color border: Qt.alpha(Theme.teal, .28)
    readonly property int radius: Theme.controlRadius
    readonly property int cut: Theme.chamfer

    readonly property color icon: Theme.muted
    readonly property color hoverIcon: Theme.text
    readonly property color selectedIcon: Theme.teal
    readonly property color hoverFill: Qt.alpha(Theme.teal, .08)
    readonly property color pressedFill: Qt.alpha(Theme.teal, .18)
    readonly property color selectedFill: Qt.alpha(Theme.teal, .14)
    readonly property color dangerFill: Qt.alpha(Theme.ember, .18)
    readonly property color hoverBorder: Qt.alpha(Theme.teal, .25)
    readonly property int hoverBorderWidth: 1
    readonly property color selectedBorder: Qt.alpha(Theme.teal, .45)
    readonly property int selectedBorderWidth: 1
    readonly property color selectedDangerIcon: Theme.ember
    readonly property color divider: Qt.alpha(Theme.text, .16)
    readonly property color subtle: Theme.muted
    readonly property color focusRing: Theme.teal

    // Tooltips: the same dark chip the bar uses, with a keycap.
    readonly property color tooltipBackground: Qt.alpha(Theme.background, .97)
    readonly property color tooltipText: Theme.text
    readonly property color tooltipBorder: Qt.alpha(Theme.teal, .35)
    readonly property color keycapFill: Qt.alpha(Theme.teal, .07)
    readonly property color keycapBorder: Qt.alpha(Theme.teal, .32)

    // Shadows under the paper and the island. Pure black at an alpha, never a hue.
    readonly property color shadow: Qt.rgba(0, 0, 0, .42)
    readonly property color shadowSoft: Qt.rgba(0, 0, 0, .18)

    // The paper: cream sheet, graphite ink, blue-grey ruling, a red margin.
    readonly property color paper: Theme.paper
    readonly property color paperEdge: Theme.paperEdge
    readonly property color paperUnder: Theme.paperUnder
    readonly property color ink: Theme.ink
    // The printed header and footer: ink at half strength.
    readonly property color printInk: Qt.alpha(Theme.ink, .5)
    readonly property color printFaint: Qt.alpha(Theme.ink, .35)
    readonly property color selection: Theme.inkSelection
    readonly property color minorGrid: Theme.rule
    readonly property color majorGrid: Theme.ruleMajor
    readonly property color marginRule: Theme.marginRule
    readonly property color headerWash: Qt.alpha(Theme.white, .09)
    readonly property color headerRule: Qt.alpha(Theme.ink, .22)
    readonly property color noteEditing: Qt.alpha(Theme.paper, .9)
    readonly property color noteEditingBorder: Qt.alpha(Theme.inkSelection, .8)
    readonly property color noteSelected: Qt.alpha(Theme.inkSelection, .2)
    readonly property color noteSelectedBorder: Qt.alpha(Theme.inkSelection, .6)
}
