import QtQuick
import ".."

// The sheet title in the paper header. It reads as printed text and edits in
// place when clicked (or on F2): Enter or clicking away keeps the edit, Escape
// restores the title.
//
// Derived from Field Notes by OldJobobo (MIT, see licenses/Field-Notes-MIT.txt).
Item {
    id: root

    property string text: ""
    property string placeholder: "UNTITLED"
    property bool editing: false
    // While exporting, hover outlines and tooltips stay off the image.
    property bool quiet: false
    property QtObject theme
    signal committed(string text)
    signal finished()

    function startEditing() {
        if (editing)
            return
        input.text = root.text
        editing = true
        input.forceActiveFocus()
        input.selectAll()
    }

    function finish(keep) {
        if (!editing)
            return
        editing = false
        if (keep)
            committed(input.text)
        finished()
    }

    implicitHeight: 30

    Accessible.role: Accessible.EditableText
    Accessible.name: "Sheet title: " + (root.text || "untitled") + ". Rename (F2)"

    Rectangle {
        x: -6
        width: parent.width + 12
        height: parent.height
        radius: 4
        color: root.editing ? Qt.alpha(Theme.white, .15) : Theme.transparent
        border.width: 1
        border.color: root.editing ? Qt.alpha(root.theme.ink, .6) : mouse.containsMouse && !root.quiet ? root.theme.printInk : Theme.transparent
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: !root.editing
        text: root.text || root.placeholder
        color: root.text ? root.theme.ink : root.theme.printFaint
        elide: Text.ElideRight
        font.family: Theme.dataFont
        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 2.6
        font.capitalization: Font.AllUppercase
        textFormat: Text.PlainText
    }

    TextInput {
        id: input

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: root.editing
        clip: true
        maximumLength: 60
        color: root.theme.ink
        selectionColor: root.theme.selection
        selectedTextColor: root.theme.paper
        font.family: Theme.dataFont
        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 2.6
        font.capitalization: Font.AllUppercase

        Keys.onReturnPressed: root.finish(true)
        Keys.onEnterPressed: root.finish(true)
        Keys.onEscapePressed: root.finish(false)
        onActiveFocusChanged: {
            if (!activeFocus)
                root.finish(true)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: root.placeholder
            color: root.theme.printFaint
            font: input.font
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: !root.editing
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onClicked: root.startEditing()
    }

    NotesTooltip {
        theme: root.theme
        text: "Rename sheet"
        shortcut: "F2"
        side: "bottom"
        x: 0
        hovered: mouse.containsMouse && !root.editing && !root.quiet
    }
}
