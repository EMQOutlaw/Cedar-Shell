import QtQuick
import Quickshell
import "../.."
import "../../services"

// Settings window furniture: open/close, lock, reopen, advanced routes,
// search, and size persistence through the real SettingsService + FloatingWindow
// path. This exercises the actual modules/Settings.qml window in offscreen mode.
ShellRoot {
    function check(ok, label) { if (!ok) { console.error("FAIL: " + label); Qt.exit(1); } }
    Timer { id: finish; interval: 200; onTriggered: Qt.quit() }

    Component.onCompleted: {
        const s = SettingsService;

        check(!s.windowOpen && s.open === false, "starts closed");
        check(s.windowSize.width >= s.minimumWidth && s.windowSize.height >= s.minimumHeight,
              "default size respects minimum");

        ShellState.settingsPage = "appearance";
        ShellState.open("settings");
        check(s.windowOpen && s.page === "appearance", "open navigates to requested page");

        check(s.rememberWindow(1000, 700), "settled size is remembered");
        check(s.windowSize.width === 1000 && s.windowSize.height === 700, "windowSize updates");

        s.closeApp();
        check(!s.windowOpen && !s.open, "close hides window");

        ShellState.open("settings");
        check(s.windowOpen && s.page === "appearance", "reopen restores page");
        check(s.windowSize.width === 1000 && s.windowSize.height === 700, "reopen restores size");

        s.setLevel("advanced");
        check(s.advanced && s.menu.some(m => m.pages.some(p => p.id === "application-theming")),
              "Advanced shows application-theming page");
        check(s.navigate("application-theming", ""), "can navigate to advanced page");

        ShellState.locked = true;
        check(!s.windowOpen && !s.open, "lock hides window");
        ShellState.settingsPage = "power"; ShellState.open("settings");
        check(!s.windowOpen, "nothing opens while locked");
        ShellState.locked = false;

        s.setLevel("simple");
        s.navigate("appearance", "");
        const found = s.search("24-hour");
        check(found.length > 0 && found[0].key === "clock24", "search indexes preferences");
        s.navigate("time", "");
        check(s.back(), "history back works");
        check(s.page === "appearance", "back returns to previous page");

        console.log("PASS: Settings floating window routes, size persistence, reopen, lock and search");
        finish.start();
    }
}
