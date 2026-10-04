import Quickshell
import "../../services"

// Match a native window only to the exact same output during reload. A display
// change creates one new host instead of migrating a visible layer window.
Variants {
    reloadableId: "cedar-core-host"
    model: CoreService.enabled && CoreService.hostScreen ? [CoreService.hostScreen] : []
}
