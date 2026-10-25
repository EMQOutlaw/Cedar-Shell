import Quickshell
import "../.."
import "../../services"

// Match a native window only to the exact same output during reload. A display
// change creates one new host instead of migrating a visible layer window.
// The pill is Strata (top-bar) only: when the bar is Understory (left), the
// owner wants no Core pill at all, not even floating.
Variants {
    reloadableId: "cedar-core-host"
    model: CoreService.enabled && CoreService.hostScreen && !Config.barVertical ? [CoreService.hostScreen] : []
}
