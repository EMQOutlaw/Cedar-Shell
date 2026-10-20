pragma Singleton
import QtQuick
import Quickshell
import ".."
Singleton {
    property int testLaunches: 0
    function launch() {
        if (ShellState.locked) return;
        if (Config.testMode) { testLaunches++; return; }
        Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/task_manager.py")]);
    }
}
