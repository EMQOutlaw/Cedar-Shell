pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
    readonly property var content: JSON.parse(source.text())
    function passage() { return content.john.verses.map(v => v.reference + "\n" + v.text).join("\n\n") + "\n\n" + content.john.reference + "\n" + content.john.translation; }
    FileView { id: source; path: Qt.resolvedUrl("data/branding.json"); blockLoading: true }
}
