import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import "modules"
import "services"

ShellRoot {
    LazyLoader {
        active: Config.externalSession
        component: SessionIntegration {}
    }
    IpcHandler {
        target: "media"
        function toggle(): void {
            Media.toggle();
        }
        function next(): void {
            Media.next();
        }
        function previous(): void {
            Media.previous();
        }
        function pause(): void {
            for (const p of Media.players)
                if (p.isPlaying && p.canPause)
                    p.pause();
        }
    }
    IpcHandler {
        target: "core"
        function toggle(): void {
            CoreService.toggle();
        }
        function show(): void {
            CoreService.expand();
        }
        function hide(): void {
            CoreService.collapse();
        }
        function publish(payload: string): string {
            if (payload.length > 16384)
                return "Payload exceeds 16 KiB.";
            return CoreService.external(payload);
        }
        function withdraw(source: string, id: string): string {
            return CoreService.withdraw(source, id);
        }
        function timer(seconds: int, label: string): string {
            return CoreService.timer.start(seconds, label) ? "ok" : "Use 1–86400 seconds.";
        }
    }
    CedarCore {}
    // The session's polkit authentication agent: the prompt exists only while
    // a request is open. Registration itself lives in the Permission service.
    LazyLoader {
        active: Permission.enabled && Permission.active
        PermissionPrompt {}
    }
    // CEDAR Shield: a first-party application window over the Shield service,
    // created when opened and released when closed.
    LazyLoader {
        active: Config.stage >= 3 && Shield.windowOpen
        ShieldApp {}
    }
    // One Canopy on its chosen output. Output changes replace the host safely.
    Variants {
        reloadableId: "cedar-canopy-host"
        model: Canopy.screen ? [Canopy.screen] : []
        CanopyWindow {}
    }
    IpcHandler {
        target: "canopy"
        function show(topic: string): void {
            Canopy.open(topic);
        }
        // `qs ipc call canopy show …` never reaches the shell: the CLI reads
        // `show` as its own `ipc show` subcommand. `open` is the usable spelling.
        function open(topic: string): void {
            Canopy.open(topic);
        }
        function hide(): void {
            Canopy.close();
        }
        function toggle(): void {
            if (Canopy.shown)
                Canopy.close();
            else
                Canopy.context();
        }
    }
    property var forestService: Forest
    property var clipboardService: Clipboard
    // Disable hot reload while locked: never replace the authentication engine.
    settings.watchFiles: !Config.managedSession && !ShellState.locked
    IpcHandler {
        target: "wallpapers"
        function toggle(): void {
            if (Config.stage >= 3)
                ShellState.toggle("wallpapers");
        }
    }
    IpcHandler {
        target: "themes"
        function toggle(): void {
            if (Config.stage >= 3)
                ShellState.toggle("themes");
        }
    }
    IpcHandler {
        target: "control"
        function toggle(): void {
            if (Config.stage >= 3)
                Canopy.toggleQuick();
        }
    }
    IpcHandler {
        target: "hud"
        function toggle(): void {
            if (Config.stage < 2)
                return;
            if (Config.saved.canopyEnabled)
                Canopy.toggleTopic("station");
            else
                ShellState.toggle("hud");
        }
    }
    // Shield: `shield refresh|status`; the page itself is `settings show shield`.
    IpcHandler {
        target: "permission"
        function status(): string { return JSON.stringify({ enabled: Permission.enabled, registered: Permission.registered, active: Permission.active }); }
    }
    IpcHandler {
        target: "shield"
        function open(): void { if (Config.stage >= 3) Shield.openApp(); }
        function close(): void { Shield.closeApp(); }
        function toggle(): void { if (Config.stage >= 3) Shield.toggleApp(); }
        function refresh(): void { if (Config.stage >= 3) Shield.refresh(); }
        function status(): string { return JSON.stringify({ ready: Shield.ready, posture: Shield.posture, headline: Shield.headline, subline: Shield.subline, windowOpen: Shield.windowOpen, busy: Shield.busy, error: Shield.error, protections: Shield.protections.map(p => ({ id: p.id, state: p.state, value: p.value, detail: p.detail })) }); }
    }
    // Gaming Mode: `gaming toggle|activate|deactivate|status` (Super+G).
    IpcHandler {
        target: "gaming"
        function toggle(): void { if (Config.stage >= 3) Gaming.toggle(); }
        function activate(): void { if (Config.stage >= 3) Gaming.activate("manual"); }
        function deactivate(): void { if (Config.stage >= 3) Gaming.deactivate(); }
        function status(): string { return JSON.stringify({ active: Gaming.active, busy: Gaming.busy, summary: Gaming.summary, steps: Gaming.steps, trigger: Gaming.trigger }); }
    }
    IpcHandler {
        target: "settings"
        function toggle(): void {
            if (Config.stage >= 3)
                ShellState.toggle("settings");
        }
        // `settings set barStyle islands`: scriptable edits of presentation
        // settings. Command, network, location and lock settings are refused
        // here (Config.ipcProtected); the file and the Settings panel own them.
        function set(key: string, value: string): string {
            return Config.ipcSet(key, value);
        }
        function get(key: string): string {
            return Config.ipcGet(key);
        }
        // `settings show shield`: open Settings on a page (ids from SettingsSchema.pages).
        function show(page: string): void {
            if (Config.stage < 3 || ShellState.locked) return;
            ShellState.settingsPage = page;
            if (ShellState.panel === "settings") ShellState.close();
            ShellState.open("settings");
        }
    }
    // Go menu: `menu toggle <route>` opens a menu id or alias (root, apps, system,
    // capture…); `menu summon <json>` takes Omarchy's payloads, including the
    // select/input prompts relayed by scripts/shim/omarchy-shell.
    IpcHandler {
        target: "menu"
        function toggle(route: string): void {
            if (Config.stage < 3)
                return;
            if (route === "apps" && Config.saved.canopyEnabled)
                Canopy.toggleTopic("go");
            else
                Go.toggle(route);
        }
        function summon(payload: string): void {
            if (Config.stage >= 3 && !ShellState.locked)
                Go.summon(payload);
        }
        function refresh(): void {
            Go.refresh();
        }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (Config.stage >= 3)
                Go.toggle("root");
        }
    }
    IpcHandler {
        target: "notifications"
        function dismissOne(): void {
            if (!ShellState.locked && NoticeStore.live.length)
                NoticeStore.dismiss(NoticeStore.live[NoticeStore.live.length - 1].id);
        }
        function dismissAll(): void {
            if (!ShellState.locked)
                for (const n of NoticeStore.live.slice()) NoticeStore.dismiss(n.id);
        }
        function invokeLast(): void {
            if (ShellState.locked) return;
            const n = NoticeStore.live[NoticeStore.live.length - 1];
            const action = n?.actions?.find(a => a.identifier === "default") || n?.actions?.[0];
            if (action) action.invoke();
        }
        function toggle(): void {
            if (Config.stage >= 3) {
                if (Config.saved.canopyEnabled) {
                    if (Canopy.shown && Canopy.topic === "notifications")
                        Canopy.close();
                    else
                        Canopy.open("notifications");
                } else
                    ShellState.toggle("history");
            }
        }
    }
    IpcHandler {
        target: "power"
        function toggle(): void {
            if (Config.stage >= 3)
                ShellState.toggle("power");
        }
    }
    IpcHandler {
        target: "lock"
        function lock(): void {
            if (Config.stage >= 3 && !Config.testMode)
                ShellState.lock(false);
        }
        // Open the existing real-PAM test window without requesting a session lock.
        function testAuthentication(): void {
            if (Config.stage >= 3 && !Config.testMode && !ShellState.locked && !Config.externalSession) {
                ShellState.close();
                ShellState.authTest = true;
            }
        }
    }
    IpcHandler {
        target: "osd"
        function fromOmarchy(payload: string): void {
            if (ShellState.locked || payload.length > 4096) return;
            try {
                const p = JSON.parse(payload);
                if (String(p.icon || "").startsWith("volume-")) { Audio.show(); return; }
                const value = Number(p.value), max = Number(p.max);
                ShellState.osd(p.icon === "brightness" ? "BRIGHTNESS" : String(p.message || p.icon || "STATUS").slice(0, 100),
                    isFinite(value) && isFinite(max) && max > 0 ? Math.max(0, Math.min(1, value / max)) : 0,
                    String(p.progressText || p.message || "").slice(0, 100));
            } catch (_) {}
        }
        function volume(delta: int): void {
            Audio.change(delta);
        }
        function mute(): void {
            Audio.toggleMute();
        }
        function brightness(delta: int): void {
            Brightness.change(delta);
        }
        function showVolume(): void {
            Audio.show();
        }
        function showBrightness(): void {
            Brightness.show();
        }
    }
    IpcHandler {
        target: "shell"
        function close(): void {
            ShellState.close();
        }
        function isLocked(): bool {
            return ShellState.locked;
        }
        function sessionInfo(): string {
            return JSON.stringify({generation: Quickshell.env("CEDAR_SESSION_GENERATION"), externalLock: Config.externalSession, trailwatch: Config.trailwatchLock, locked: ShellState.locked, lockReady: ShellState.nativeLockReady, lockSecure: ShellState.lockSecure, securedUnlocks: ShellState.securedUnlocks, authTests: ShellState.authTests, screenCount: Quickshell.screens.length, stage: Config.stage});
        }
        function stop(): void {
            if (!ShellState.locked)
                Qt.quit();
        }
    }
    LazyLoader {
        active: Config.stage >= 3 && !Config.testMode
        component: NotificationServer {}
    }
    LazyLoader {
        active: Config.stage >= 3 && !Config.externalSession
        component: LockScreen {}
    }
    // Omarchy's bridge answers `omarchy-shell lock status` from this file while
    // Trailwatch is the locker, so idle, lid, sleep and keyboard requests reach it.
    LazyLoader {
        active: Config.stage >= 3 && Config.trailwatchLock && !Config.testMode
        component: LockStatePublisher {}
    }
    Variants {
        model: Quickshell.screens
        Scope {
            required property var modelData
            Bar {
                output: modelData
            }
            LazyLoader {
                active: Config.stage >= 3 && !Config.testMode && !Config.externalBackground
                component: Background {
                    output: modelData
                }
            }
            LazyLoader {
                active: Config.stage >= 2
                component: Hud {
                    output: modelData
                }
            }
            LazyLoader {
                active: Config.stage >= 3
                component: Scope {
                    Menu {
                        output: modelData
                    }
                    Settings {
                        output: modelData
                    }
                    ControlCenter {
                        output: modelData
                    }
                    Notifications {
                        output: modelData
                    }
                    Osd {
                        output: modelData
                    }
                    PowerMenu {
                        output: modelData
                    }
                    Themes {
                        output: modelData
                    }
                    WallpaperPicker {
                        output: modelData
                    }
                }
            }
        }
    }
}
