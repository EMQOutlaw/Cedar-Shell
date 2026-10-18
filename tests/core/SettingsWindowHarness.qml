import QtQuick
import QtQuick.Window
import Quickshell
import "../.."
import "../../services"
import "../../modules"

// Settings window furniture: open/close, lock, reopen, advanced routes,
// search, and size persistence through the real SettingsService + FloatingWindow
// path. This exercises the actual modules/Settings.qml window in offscreen mode.
ShellRoot {
    Settings { id: settingsWindow }
    function check(ok, label) { if (!ok) { console.error("FAIL: " + label); Qt.exit(1); } }
    Timer { id: finish; interval: 200; onTriggered: Qt.quit() }
    Timer {
        id: rendered; interval: 100
        onTriggered: {
            check(settingsWindow.visible && settingsWindow.width >= SettingsService.minimumWidth,
                  "the real floating window is visible after event delivery");
            // implicitSize is an initial hint for FloatingWindow. Resize its
            // real QWindow to simulate the compositor delivering a resize.
            const nativeWindow = settingsWindow.contentItem.Window.window;
            check(nativeWindow !== null, "the floating window has a native QWindow");
            nativeWindow.width = 1100; nativeWindow.height = 760;
            resized.start();
        }
    }
    Timer {
        id: resized; interval: 600
        onTriggered: {
            check(SettingsService.windowSize.width === 1100 && SettingsService.windowSize.height === 760,
                  "actual window resize is persisted after settling: " + settingsWindow.width + "x" + settingsWindow.height + " saved " + JSON.stringify(SettingsService.windowSize));
            SettingsService.closeApp();
            reopened.start();
        }
    }
    Timer {
        id: reopened; interval: 100
        onTriggered: {
            check(!settingsWindow.visible, "service close hides the actual window");
            ShellState.open("settings");
            relocked.start();
        }
    }
    Timer {
        id: relocked; interval: 100
        onTriggered: {
            check(settingsWindow.visible && settingsWindow.width === 1100 && settingsWindow.height === 760,
                  "actual window reopens at remembered size");
            ShellState.locked = true;
            hidden.start();
        }
    }
    Timer {
        id: hidden; interval: 100
        onTriggered: {
            check(!settingsWindow.visible && !SettingsService.windowOpen, "lock hides the actual window");
            console.log("PASS: Settings floating window routes, resize persistence, reopen, lock and search");
            finish.start();
        }
    }

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

        ShellState.open("settings");
        rendered.start();
    }
}
