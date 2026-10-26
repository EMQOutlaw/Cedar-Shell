.pragma library

// These descriptors render the controls AND build the search index.
var pages = [
 {id:"overview",label:"Overview",icon:"⌂",description:"Your environment. Your flow."},
 {id:"appearance",label:"Appearance",icon:"◐",description:"Shape your environment."},
 {id:"bar",label:"Shell & Bar",icon:"━",description:"Customize your command center."},
 {id:"animations",label:"Animations & Effects",icon:"◌",description:"Bring your environment to life."},
 {id:"desktop",label:"Wallpapers & Screensavers",icon:"▧",description:"Set the mood."},
 {id:"displays",label:"Displays",icon:"▣",description:"Configure your visual workspace."},
 {id:"windows",label:"Windows & Workspaces",icon:"▦",description:"The layout and organization of your desktop."},
 {id:"input",label:"Input & Keybinds",icon:"⌨",description:"Make every interaction feel right."},
 {id:"notifications",label:"Notifications & Signals",icon:"◈",description:"Choose what deserves your attention."},
 {id:"audio",label:"Audio & Media",icon:"♫",description:"Outputs, microphones, routing and audio scenes."},
 {id:"apps",label:"Applications & Integrations",icon:"◇",description:"Connect your everyday tools."},
 {id:"profiles",label:"Desktop Profiles",icon:"△",description:"Optimize CEDAR for your workflow."},
 {id:"power",label:"Power & Idle",icon:"⏻",description:"Balance energy, performance and inactivity."},
 {id:"connections",label:"Network & Bluetooth",icon:"⌁",description:"Your connections, in one place."},
 {id:"privacy",label:"Privacy & Shield",icon:"⬡",description:"Understand and control your protections."},
 {id:"security",label:"Lock Screen & Security",icon:"▢",description:"Privacy and controls while the desktop is locked."},
 {id:"system",label:"Updates & Recovery",icon:"↻",description:"Review updates, diagnose problems and recover safely."},
 {id:"nursery",label:"Nursery",icon:"❀",description:"Companion services planted into the shell — CEDAR Ai first. Off until you say otherwise."},
 {id:"advanced",label:"Advanced",icon:"⌘",description:"Desktop setup and specialized CEDAR controls."},
 {id:"about",label:"About CEDAR",icon:"✧",description:"Contextual Environment & Desktop Automation Runtime."},
 // Existing deep links remain stable. Their owners are available as section tabs.
 {id:"keybinds",label:"Keybinds",icon:"⌘",rail:false,description:"Search, record and manage your shortcuts."},
 {id:"core",label:"Dynamic Island",icon:"◈",rail:false,description:"CEDAR Core: a quiet awareness center."},
 {id:"application-theming",label:"Application Theming",icon:"◐",rail:false,advanced:true,description:"Native application palettes, ownership and recovery."},
 {id:"setup",label:"Desktop Setup",icon:"◇",rail:false,advanced:true,description:"Desktop ownership, applications and recovery."},
 {id:"time",label:"Time & Date",icon:"◷",rail:false,description:"A familiar clock across every CEDAR surface."},
 {id:"notes",label:"Field Notes",icon:"✎",rail:false,description:"Your floating notebook, sketches and text."},
 {id:"dictation",label:"Dictation",icon:"●",rail:false,description:"Voxtype voice typing and microphone preferences."}
];
var menu = [
 {id:"environment",label:"Environment",description:"The shape and character of your desktop.",pages:["overview","appearance","bar","animations","desktop","displays","windows","core"]},
 {id:"interaction",label:"Interaction",description:"Input, attention and everyday tools.",pages:["input","keybinds","notifications","audio","apps","application-theming","dictation","time","notes"]},
 {id:"system",label:"System",description:"Profiles, power, connections and protection.",pages:["profiles","power","connections","privacy","security"]},
 {id:"management",label:"Management",description:"Updates, recovery and advanced setup.",pages:["system","nursery","advanced","setup","about"]}
];
function menuOf(id) {
    for (var i = 0; i < menu.length; ++i) if (menu[i].pages.indexOf(id) !== -1) return menu[i].id;
    return "";
}
function groupOf(id) {
    for (var i = 0; i < menu.length; ++i) if (menu[i].pages.indexOf(id) !== -1) return menu[i].label;
    return "CEDAR";
}
function indexOf(id) { return String(Math.max(1,pages.findIndex(p=>p.id===id)+1)).padStart(2,"0"); }
// Rows the Simple view folds away. Everything else is basic; the "Advanced"
// group is advanced wherever it appears. A row's own `level` wins.
var advancedKeys = ["remoteArtwork","lockMediaDetails","lockAgendaDetails","whisperDevices","whisperQuiet","whisperBattery","forestEchoes","canopyPeek","audioSpectrum","editor","terminal","browser","files","coreScreenshots","coreConnections","coreWorkspaces","coreKeyboard","coreClipboard","coreTemperatureLimit","coreDiskLimit","panelRadius","panelOpacity","effectIntensity","barPulse","barKinetic","latitude","longitude","gamingBlur","gamingAnimations","gamingAutoGameMode","focusTrails","focusAllowedApps","notesFadeToolbar","notesSmoothing","notesExportDir"];
function levelOf(field) {
    if (!field) return "basic";
    if (field.level === "advanced" || field.level === "basic") return field.level;
    return field.group === "Advanced" || advancedKeys.indexOf(field.key) !== -1 ? "advanced" : "basic";
}
function visibleFields(page, level) {
    return fields.filter(function(f) { return f.page === page && (level === "advanced" || levelOf(f) === "basic"); });
}
// The page a key lives on: a preference, a page's own control (extras) or an input row.
function pageOf(key) {
    var all = fields.concat(extras);
    for (var i = 0; i < all.length; ++i) if (all[i].key === key) return all[i].page;
    for (var j = 0; j < inputFields.length; ++j) if (inputFields[j].key === key) return "input";
    return "";
}
// Does a value fit its descriptor? Empty string means yes; otherwise the
// reason. Keys the schema does not describe are left to Config's type check.
function validate(key, value) {
    var field = null;
    for (var i = 0; i < fields.length; ++i) if (fields[i].key === key) { field = fields[i]; break; }
    if (!field) return "";
    if (field.type === "toggle") return typeof value === "boolean" ? "" : "expected true or false";
    if (field.type === "slider" || field.type === "number") {
        if (typeof value !== "number" || !isFinite(value)) return "expected a number";
        if (field.min !== undefined && value < field.min) return "below the minimum of " + field.min;
        if (field.max !== undefined && value > field.max) return "above the maximum of " + field.max;
        return "";
    }
    if (field.type === "choice") {
        for (var k = 0; k < field.options.length; ++k) if (field.options[k].value === value) return "";
        return "not one of the choices: " + field.options.map(function(o) { return o.value; }).join(", ");
    }
    if (field.type === "text" || field.type === "font") return typeof value === "string" ? "" : "expected text";
    return "";
}
var fields = [
 {page:"overview",group:"View",key:"settingsLevel",label:"Settings depth",description:"Simple shows what most people change. Advanced shows every page and every row.",type:"choice",options:[{value:"simple",label:"Simple"},{value:"advanced",label:"Advanced"}],defaultValue:"simple",aliases:"advanced mode expert basic level show all"},
 {page:"privacy",group:"Privacy",key:"localOnly",label:"Local-only mode",description:"Block CEDAR external weather, location, calendar and artwork requests.",type:"toggle",defaultValue:true},
 {page:"privacy",group:"Privacy",key:"weatherEnabled",label:"Weather access",description:"Allow Open-Meteo forecasts, IP-based location and explicitly requested city search when local-only is off.",type:"toggle",defaultValue:false},
 {page:"privacy",group:"Privacy",key:"remoteArtwork",label:"Remote artwork",description:"Allow media artwork hosts when local-only is off.",type:"toggle",defaultValue:false},
 {page:"security",group:"Trailwatch privacy",key:"lockPrivacy",label:"Privacy while locked",description:"Hide media, event, reminder and device names. Notification contents never appear on Trailwatch.",type:"toggle",defaultValue:true},
 {page:"security",group:"Trailwatch privacy",key:"lockMediaDetails",label:"Show media details",description:"Show track and artist when lockscreen privacy is off.",type:"toggle",defaultValue:false},
 {page:"security",group:"Trailwatch privacy",key:"lockAgendaDetails",label:"Show agenda details",description:"Show event and reminder titles when lockscreen privacy is off.",type:"toggle",defaultValue:false},
 {page:"security",group:"Trailwatch controls",key:"lockMediaControls",label:"Media controls while locked",description:"Allow playback and volume adjustment without unlocking.",type:"toggle",defaultValue:false},
 {page:"core",group:"Whisper types",key:"whisperDevices",label:"Connected device observations",description:"A quiet reminder about a connected Bluetooth audio output after long inactivity.",type:"toggle",defaultValue:true},
{"page": "core", "group": "Canopy", "key": "canopyEnabled", "label": "Canopy", "description": "Panels descend beneath the bar. Applications always drops from its own button.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Canopy", "key": "canopyPeek", "label": "Peek", "description": "Hover or focus a bar control for a compact preview.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Forest", "key": "forestPulse", "label": "Pulse", "description": "Subtle illumination follows real activity and semantic Forest State.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Forest", "key": "forestEchoes", "label": "Echoes", "description": "After a signal recedes, Core\u2019s line lingers faintly for a few seconds.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Forest", "key": "forestWhispers", "label": "Whispers", "description": "Quiet observations; at least ten minutes apart and six hours per type.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Whisper types", "key": "whisperQuiet", "label": "Quiet observations", "description": "An observation after twenty minutes idle.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Whisper types", "key": "whisperBattery", "label": "Battery observations", "description": "An observation when charging reaches 90%.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Privacy", "key": "forestTrails", "label": "Trails", "description": "Opt-in, session-only application identity and CEDAR navigation. Cleared on lock.", "type": "toggle", "defaultValue": false},
{"page": "core", "group": "Privacy", "key": "clipboardHistory", "label": "Clipboard history", "description": "Opt-in session history, cleared on lock. Unmarked secrets may be captured.", "type": "toggle", "defaultValue": false},
{"page": "core", "group": "Instruments", "key": "audioSpectrum", "label": "Audio spectrum", "description": "Real CAVA playback spectrum, only while Audio Canopy is open.", "type": "toggle", "defaultValue": false},
 {page:"apps",group:"Quick launch",key:"editor",label:"Editor command",description:"Launch command. Empty finds your default text editor.",type:"text",defaultValue:"",placeholder:"zeditor"},
{"page": "core", "group": "Core", "key": "coreEnabled", "label": "CEDAR Core", "description": "Show one contextual surface at the center of the preferred display’s bar.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreVolume", "label": "Volume & brightness", "description": "Use Core for live sliders. The existing OSD remains available when Core is hidden.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreMedia", "label": "Media", "description": "Track changes and playback controls from MPRIS.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreNotifications", "label": "Notifications", "description": "Notifications unfold from the Core pill and gather in Signals. Off: they appear as cards at the top right instead.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreScreenshots", "label": "Screenshot actions", "description": "Show Open, Copy and Reveal for saved Omarchy screenshot notifications.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreConnections", "label": "Connections", "description": "Bluetooth changes in Core; network and VPN changes on the network button.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreDictation", "label": "Dictation", "description": "The pill becomes the microphone's filament while Voxtype listens, carries a light while it transcribes, and keeps a Signals row with Stop and Cancel. The bar button and keybinds work either way.", "type": "toggle", "defaultValue": true, "aliases": "voxtype voice speech"},
{"page": "core", "group": "Activities", "key": "corePower", "label": "Power", "description": "Battery warnings, power connection and system profile changes.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "corePrivacy", "label": "Privacy indicators", "description": "Active PipeWire links from identifiable microphones and cameras. Direct hardware access outside PipeWire is not monitored.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreWorkspaces", "label": "Workspace changes", "description": "Brief feedback when the focused workspace changes.", "type": "toggle", "defaultValue": false},
{"page": "core", "group": "Activities", "key": "coreKeyboard", "label": "Lock keys", "description": "Caps Lock and Num Lock changes when Linux exposes keyboard LEDs.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Activities", "key": "coreClipboard", "label": "Copy feedback", "description": "A quiet “Copied” signal. Clipboard text and images are never displayed.", "type": "toggle", "defaultValue": false},
{"page": "core", "group": "Warnings", "key": "coreWarnings", "label": "System warnings", "description": "Reported temperature and disk-use warnings with recovery thresholds.", "type": "toggle", "defaultValue": true},
{"page": "core", "group": "Warnings", "key": "coreTemperatureLimit", "label": "Temperature warning", "description": "Temperature sensor threshold; the warning clears 5°C below this value.", "type": "slider", "defaultValue": 90, "min": 65, "max": 110, "step": 1, "unit": "°C"},
{"page": "core", "group": "Warnings", "key": "coreDiskLimit", "label": "Storage warning", "description": "Warn when the monitored filesystem reaches this percentage used.", "type": "slider", "defaultValue": 95, "min": 80, "max": 99, "step": 1, "unit": "%"},
 {page:"appearance",group:"Typography",key:"interfaceFont",label:"Interface font",description:"Display typography for CEDAR headings.",type:"font",defaultValue:"Rajdhani",aliases:"typeface label"},
 {page:"appearance",group:"Typography",key:"dataFont",label:"Data font",description:"Monospace typography for controls and information.",type:"font",defaultValue:"JetBrainsMono Nerd Font",aliases:"monospace telemetry"},
 {page:"appearance",group:"Typography",key:"fontScale",label:"Text scale",description:"Size of shared interface text and controls.",type:"slider",min:.85,max:1.3,step:.05,unit:"%",factor:100,defaultValue:1},
 {page:"appearance",group:"Interface",key:"panelRadius",label:"Panel corners",description:"Corner radius for Settings, Canopy, and Field Station.",type:"slider",min:0,max:28,step:1,unit:" px",defaultValue:16,aliases:"rounded radius"},
 {page:"appearance",group:"Interface",key:"panelOpacity",label:"Panel opacity",description:"Background opacity of the main CEDAR panels.",type:"slider",min:.88,max:1,step:.01,factor:100,unit:"%",defaultValue:.97,aliases:"transparency glass"},
 {page:"animations",group:"Bar effects",key:"motionPreset",label:"Motion preset",description:"How much the bar moves: Calm keeps transitions subtle, Balanced is the CEDAR experience, Expressive makes traces brighter and transitions richer, Off keeps the bar static.",type:"choice",options:[{value:"calm",label:"Calm"},{value:"balanced",label:"Balanced"},{value:"expressive",label:"Expressive"},{value:"off",label:"Off"}],defaultValue:"balanced",aliases:"animation effects"},
 {page:"animations",group:"Bar effects",key:"effectIntensity",label:"Effect intensity",description:"Brightness and reach of the Heartwood rings, Rootline traces and edge light.",type:"slider",min:.3,max:1.5,step:.1,unit:"%",factor:100,defaultValue:1},
 {page:"animations",group:"Bar effects",key:"barHeartwood",label:"Heartwood",description:"The cedar cross-section instrument in the Core pill: it turns on hover, runs a light on click, separates when a panel unfolds, and reads Gaming Mode, Focus and Shield.",type:"toggle",defaultValue:true},
 {page:"animations",group:"Bar effects",key:"barRootlines",label:"Rootlines",description:"Thin branching paths in the bar that light briefly when a panel opens, a profile changes or Shield's posture moves.",type:"toggle",defaultValue:true},
 {page:"animations",group:"Bar effects",key:"barKinetic",label:"Kinetic Type",description:"Status words, tile values and titles move when their meaning changes.",type:"toggle",defaultValue:true},
 {page:"animations",group:"Bar effects",key:"barWhispers",label:"Whispers in the bar",description:"The bar's text region shows profile, Focus and Shield messages as they happen, and a curated line when no window has a title.",type:"toggle",defaultValue:true},
 {page:"animations",group:"Bar effects",key:"barPulse",label:"Canopy Pulse",description:"Thin strokes in the bar that follow real audio levels while something plays (CAVA over PipeWire). Off by default; analysis runs only while shown.",type:"toggle",defaultValue:false},
 {page:"animations",group:"Motion & light",key:"ambientIntensity",label:"Ambient illumination",description:"Subtle forest light in the main panels. Set to zero to hide drifting spores and edge illumination.",type:"slider",min:0,max:1,step:.05,factor:100,unit:"%",defaultValue:.45,aliases:"glow spores particles"},
 {page:"animations",group:"Motion & light",key:"reducedMotion",label:"Reduced Motion",description:"Stop decorative spores, orbiting accents, and breathing light.",type:"toggle",defaultValue:false,aliases:"animation accessibility motion"},
 {page:"desktop",group:"Background",key:"wallpaperMode",label:"Wallpaper fit",description:"How an image fills each display.",type:"choice",options:[{value:"crop",label:"Fill screen"},{value:"fit",label:"Fit image"},{value:"stretch",label:"Stretch"}],defaultValue:"crop",aliases:"background mode"},
 {page:"desktop",group:"Background",key:"wallpaperFolder",label:"Wallpaper folder",description:"A folder of your own images, searched with its subfolders. Empty shows only CEDAR’s bundled backgrounds and ~/.config/cedar/wallpapers.",type:"text",defaultValue:"",placeholder:"~/Pictures/Wallpapers/CEDAR",aliases:"background images directory pictures"},
 {page:"desktop",group:"Background",key:"desktopSignature",label:"CEDAR signature",description:"Show the small CEDAR identity on the desktop.",type:"toggle",defaultValue:true,aliases:"background branding text"},
 {page:"apps",group:"Quick launch",key:"terminal",label:"Terminal",description:"Launch command. Empty finds your installed terminal; arguments are separated by spaces.",type:"text",defaultValue:"",placeholder:"kitty"},
 {page:"apps",group:"Quick launch",key:"browser",label:"Browser",description:"Launch command. Empty uses your default browser.",type:"text",defaultValue:"",placeholder:"xdg-open https://duckduckgo.com"},
 {page:"apps",group:"Quick launch",key:"files",label:"Files",description:"Launch command. Empty opens your home folder.",type:"text",defaultValue:"",placeholder:"xdg-open ~"},
 {page:"apps",group:"Launcher search",key:"searchEngine",label:"Web search engine",description:"Where the Applications drop sends a search you type. Opens in your default browser.",type:"choice",options:[{value:"brave",label:"Brave Search"},{value:"duckduckgo",label:"DuckDuckGo"},{value:"startpage",label:"Startpage"},{value:"kagi",label:"Kagi"},{value:"google",label:"Google"}],defaultValue:"brave",aliases:"search web brave duckduckgo calculator"},
 {page:"desktop",group:"Field Station weather",key:"weatherAutomatic",label:"Automatic weather location",description:"Find an approximate city from your public IP whenever weather is on and no saved location overrides it. Turn off to use only a chosen city.",type:"toggle",defaultValue:true,aliases:"weather automatic detect IP city location"},
 {page:"desktop",group:"Field Station weather",key:"locationName",label:"Saved location name",description:"A name for the place shown in Field Station.",type:"text",defaultValue:"",placeholder:"Your ridge",aliases:"weather city"},
 {page:"desktop",group:"Field Station weather",key:"latitude",label:"Latitude",description:"Optional manual override. City search fills this automatically.",type:"text",defaultValue:"",placeholder:"36.2",aliases:"weather location"},
 {page:"desktop",group:"Field Station weather",key:"longitude",label:"Longitude",description:"Optional manual override. Clear both coordinates to return to automatic location.",type:"text",defaultValue:"",placeholder:"-81.7",aliases:"weather location"},
 {page:"desktop",group:"Field Station weather",key:"temperatureUnit",label:"Temperature unit",description:"Weather temperature in Field Station.",type:"choice",options:[{value:"fahrenheit",label:"Fahrenheit · °F"},{value:"celsius",label:"Celsius · °C"}],defaultValue:"fahrenheit"},
 {page:"desktop",group:"Advanced",key:"diskPath",label:"Storage reading",description:"Path used for Field Station’s disk-usage reading. Empty uses your home folder.",type:"text",defaultValue:"",aliases:"disk telemetry"},
 {page:"bar",group:"Placement",key:"barPlacement",label:"Bar placement",description:"Along the top as the Strata bar with the Core pill, or down the left edge as the slim Understory bar: Heartwood, workspaces, the focused window, status and the clock in one column, with the full rail growing from it. The Core pill rests while the bar is on the left.",type:"choice",options:[{value:"top",label:"Top"},{value:"understory",label:"Left rail"}],defaultValue:"top",aliases:"vertical sidebar left understory caelestia"},
 {page:"bar",group:"Geometry",key:"barHeight",label:"Bar height",description:"Overall height of the top bar.",type:"slider",min:40,max:72,step:2,unit:" px",defaultValue:44},
 {page:"bar",group:"Appearance",key:"barOpacity",label:"Bar opacity",description:"Background opacity for the Strata bar.",type:"slider",min:.1,max:1,step:.01,factor:100,unit:"%",defaultValue:.94,aliases:"transparency"},
 {page:"notifications",group:"Popups",key:"notificationsEnabled",label:"Notification popups",description:"Let notifications unfold from the Core pill (or show as cards when Core is off). History continues to record messages.",type:"toggle",defaultValue:true,aliases:"enable disable alerts"},
 {page:"notifications",group:"Popups",key:"doNotDisturb",label:"Do Not Disturb",description:"Quiet ordinary popups. Critical alerts still appear when popups are enabled.",type:"toggle",defaultValue:false,aliases:"dnd silence focus"},
 {page:"notifications",group:"Focus",key:"focusDnd",label:"Hold notifications",description:"Turn Do Not Disturb on for the session; critical alerts and excepted apps still show.",type:"toggle",defaultValue:true,aliases:"focus session dnd"},
 {page:"notifications",group:"Focus",key:"focusWhispers",label:"Silence Whispers",description:"No ambient observations during a session.",type:"toggle",defaultValue:true},
 {page:"notifications",group:"Focus",key:"focusQuiet",label:"Quiet the desktop",description:"Ambient effects off and Performance mode on while a session runs; everything returns after.",type:"toggle",defaultValue:true},
 {page:"notifications",group:"Focus",key:"focusTrails",label:"Pause activity trails",description:"Record nothing you open during a session.",type:"toggle",defaultValue:false},
 {page:"notifications",group:"Focus",key:"focusAllowedApps",label:"Exceptions",description:"Applications whose notifications still show during Focus, by announced name, comma-separated.",type:"text",defaultValue:"",placeholder:"Signal, Thunderbird"},
 {page:"notifications",group:"Focus",key:"focusMinutes",label:"Default length",description:"The session length Focus starts with.",type:"choice",options:[{value:15,label:"15 min"},{value:25,label:"25 min"},{value:50,label:"50 min"},{value:90,label:"90 min"}],defaultValue:25},
 {page:"notifications",group:"Popups",key:"notificationSeconds",label:"Default popup duration",description:"Used when an application does not request its own timeout. Critical alerts remain until dismissed.",type:"slider",min:3,max:20,step:1,unit:" sec",defaultValue:7,aliases:"timeout time"},
 {page:"power",group:"Performance mode",key:"performanceMode",label:"Performance mode",description:"Run only the basics: no breathing light, spores, entrance sweeps, spectrum or ambient telemetry. Automatic turns it on while the power-saver profile is active or a fullscreen window (a game) has focus.",type:"choice",options:[{value:"auto",label:"Automatic"},{value:"on",label:"Always on"},{value:"off",label:"Off"}],defaultValue:"auto",aliases:"battery saver game mode gaming animations flair lean"},
 {page:"power",group:"Gaming Mode",key:"gamingDnd",label:"Do not disturb",description:"Hold notification popups while a game runs; critical alerts still show.",type:"toggle",defaultValue:true,aliases:"game gaming mode notifications"},
 {page:"power",group:"Gaming Mode",key:"gamingIdle",label:"Stay awake",description:"Hold off the idle lock and sleep while Gaming Mode is on (a logind inhibitor plus CEDAR's own lock timer).",type:"toggle",defaultValue:true,aliases:"game gaming mode idle lock sleep"},
 {page:"power",group:"Gaming Mode",key:"gamingPower",label:"Performance power profile",description:"Switch the system power profile to performance for the game and back afterwards.",type:"toggle",defaultValue:true,aliases:"game gaming mode power profile"},
 {page:"power",group:"Gaming Mode",key:"gamingBlur",label:"Turn off compositor blur",description:"Set Hyprland's blur off at runtime while a game runs, restored when you leave. No config file is touched.",type:"toggle",defaultValue:true,aliases:"game gaming mode hyprland blur"},
 {page:"power",group:"Gaming Mode",key:"gamingAnimations",label:"Turn off window animations",description:"Also stop Hyprland's window and workspace animations while a game runs.",type:"toggle",defaultValue:false,aliases:"game gaming mode hyprland animations"},
 {page:"power",group:"Gaming Mode",key:"gamingAutoGameMode",label:"Follow GameMode",description:"When Feral GameMode registers a game, enter Gaming Mode; leave when the last game exits. Needs GameMode installed.",type:"toggle",defaultValue:true,aliases:"game gaming mode feral gamemode automatic"},
 {page:"power",group:"Session lock",key:"idleLockSeconds",label:"Lock after inactivity",description:"Seconds before CEDAR locks the session. Zero disables automatic locking; idle inhibitors are respected.",type:"number",min:0,max:86400,defaultValue:600,aliases:"idle screen timeout security"},
 {page:"power",group:"Advanced",key:"brightnessDevice",label:"Backlight device",description:"Empty uses brightnessctl’s default device.",type:"text",defaultValue:"",aliases:"brightness laptop"},
 {page:"time",group:"Clock",key:"clock24",label:"24-hour clock",description:"Off uses a 12-hour clock with AM / PM. Updates every CEDAR clock.",type:"toggle",defaultValue:true,aliases:"12hr 24hr twelve hour twenty four time format"},
 {page:"time",group:"Date",key:"dateStyle",label:"Date format",description:"Choose the order of month, day, and year.",type:"choice",options:[{value:"month-first",label:"Month first"},{value:"day-first",label:"Day first"},{value:"iso",label:"Year first · ISO"}],defaultValue:"month-first",aliases:"calendar"},
 {page:"time",group:"Date",key:"showWeekday",label:"Show weekday",description:"Include the day name beside the date.",type:"toggle",defaultValue:true},
 {page:"time",group:"Top bar",key:"barShowDate",label:"Show date in the bar",description:"Off leaves a time-only bar clock.",type:"toggle",defaultValue:true},
 {page:"notes",group:"Paper",key:"notesTilt",label:"Tilted paper",description:"Rest the sheet at a slight angle, like paper on a desk.",type:"toggle",defaultValue:true,aliases:"angle rotate straight"},
 {page:"notes",group:"Paper",key:"notesToolbar",label:"Toolbar side",description:"Which side of the paper the tools dock to. Dragging the toolbar by its grip moves it too.",type:"choice",options:[{value:"left",label:"Left"},{value:"top",label:"Top"},{value:"bottom",label:"Bottom"},{value:"right",label:"Right"}],defaultValue:"right",aliases:"dock tools position"},
 {page:"notes",group:"Paper",key:"notesFadeToolbar",label:"Fade toolbar",description:"Fade the tools away while you work in another window. They return when the notes have focus or you point at them.",type:"toggle",defaultValue:true},
 {page:"notes",group:"Drawing",key:"notesSmoothing",label:"Mouse smoothing",description:"Steadies strokes from a mouse or touchpad; sharp corners and stroke ends stay put. Pen tablets are left exactly as drawn.",type:"choice",options:[{value:"off",label:"Off"},{value:"light",label:"Light"},{value:"medium",label:"Medium"},{value:"strong",label:"Strong"}],defaultValue:"medium",aliases:"steady wobble pen"},
 {page:"notes",group:"Drawing",key:"notesEraser",label:"Eraser size",description:"The eraser ring cuts strokes at its edge and removes any note it touches.",type:"choice",options:[{value:"small",label:"Small"},{value:"medium",label:"Medium"},{value:"large",label:"Large"}],defaultValue:"medium"},
 {page:"notes",group:"Export",key:"notesClipboard",label:"Ctrl+C copies",description:"Ctrl+Shift+C copies the other one. Both save the sheet as a PNG first.",type:"choice",options:[{value:"path",label:"File path"},{value:"image",label:"Image"}],defaultValue:"path",aliases:"copy clipboard png export"},
 {page:"notes",group:"Export",key:"notesExportDir",label:"Export folder",description:"Where copied sheets are saved, one new PNG per copy. Empty uses ~/Pictures/field-notes; ~ is your home folder.",type:"text",defaultValue:"",placeholder:"~/Pictures/field-notes",aliases:"save directory pictures"}
];
var modules = [
 {key:"identity",label:"CEDAR / Field Station"}, {key:"go",label:"Applications"}, {key:"workspaces",label:"Workspaces"},
 {key:"activeWindow",label:"Active window"}, {key:"tray",label:"System tray"}, {key:"network",label:"Connections"},
 {key:"audio",label:"Audio (Strata layout)",strataOnly:true},
  {key:"battery",label:"Battery"}, {key:"notifications",label:"Notifications"},
  {key:"clock",label:"Clock"}, {key:"notes",label:"Field Notes"}, {key:"dictation",label:"Dictation (when Voxtype is installed)"}
];
function search(entries, text) {
    var words=text.toLowerCase().trim().split(/\s+/).filter(Boolean);
    if (!words.length) return [];
    return entries.filter(function(e) {
        var hay=[e.label,e.description,e.page,e.category,e.group,e.aliases].join(" ").toLowerCase();
        return words.every(function(w){return hay.indexOf(w)!==-1;});
    }).sort(function(a,b){
        var exactA=a.label.toLowerCase().indexOf(text.toLowerCase())===0 ? 0:1;
        var exactB=b.label.toLowerCase().indexOf(text.toLowerCase())===0 ? 0:1;
        return exactA-exactB || a.label.localeCompare(b.label);
    }).slice(0,40);
}
var extras = [
 {page:"appearance",key:"theme",label:"Theme",description:"Choose from installed desktop themes.",aliases:"colors palette"},
 {page:"desktop",key:"wallpaper",label:"Wallpaper",description:"Preview and change your desktop background."},
 {page:"bar",key:"modules",label:"Bar modules",description:"Choose which controls appear in the top bar."},
 {page:"bar",key:"understory",label:"Understory",description:"The rail of controls that grows from the bar's left end, and its shortcut.",aliases:"sidebar rail control center keybind shortcut"},
 {page:"displays",key:"vrr",label:"Variable Refresh Rate",description:"Adaptive sync policy for compatible displays.",aliases:"VRR freesync gsync"},
 {page:"displays",key:"mainDisplay",label:"Main display",description:"Preferred output for CEDAR and the system startup screen.",aliases:"primary DP-2 monitor"},
 {page:"displays",key:"arrangement",label:"Display arrangement",description:"Drag your monitors into position.",aliases:"position monitor"},
 {page:"displays",key:"displayMode",label:"Resolution and refresh rate",description:"Choose a mode reported by your display.",aliases:"hz scale rotation"},
 {page:"audio",key:"output",label:"Output device",description:"Choose your speakers or headphones.",aliases:"sound volume"},
 {page:"audio",key:"microphone",label:"Microphone",description:"Recording device, input volume, and mute."},
 {page:"audio",key:"streams",label:"Application volume",description:"Volume for active playback and recording streams."},
 {page:"connections",key:"wifi",label:"Wi-Fi and VPN",description:"Wireless networks and saved connections.",aliases:"internet network"},
 {page:"connections",key:"hotspot",label:"Hotspot",description:"Share this computer\u2019s connection over Wi-Fi.",aliases:"tether share access point"},
 {page:"displays",key:"mirror",label:"Mirror displays",description:"Show the same picture on more than one screen.",aliases:"duplicate clone projector"},
 {page:"displays",key:"profiles",label:"Saved display layouts",description:"Save an arrangement and test it again later.",aliases:"profile preset docking"},
 {page:"displays",key:"detect",label:"Detect displays",description:"Read connected monitors again.",aliases:"scan monitor refresh"},
 {page:"keybinds",key:"customBinds",label:"Your custom shortcuts",description:"Shortcuts you added in CEDAR.",aliases:"bind keyboard shortcut add"},
 {page:"input",key:"repeatTest",label:"Try key repeat",description:"Hold a key to feel the applied repeat rate and delay.",aliases:"typing"},
 {page:"connections",key:"bluetooth",label:"Bluetooth",description:"Discover, pair, and manage nearby devices."},
 {page:"power",key:"powerProfile",label:"System power profile",description:"Choose from profiles supported by this computer.",aliases:"performance balanced battery saver"},
 {page:"power",key:"brightness",label:"Brightness",description:"Adjust a supported backlight."},
 {page:"power",key:"authentication",label:"Test authentication",description:"Test local password authentication without locking the session.",aliases:"lock password pam"}
];
var inputFields = [
 {group:"Keyboard",key:"kb_layout",label:"Keyboard layouts",description:"Comma-separated XKB layouts, such as us,de.",type:"text",placeholder:"us"},
 {group:"Keyboard",key:"kb_variant",label:"Keyboard variants",description:"Variant names in the same order as your layouts.",type:"text",placeholder:"intl"},
 {group:"Keyboard",key:"repeat_rate",label:"Repeat rate",description:"Repeated characters per second (1–100).",type:"number"},
 {group:"Keyboard",key:"repeat_delay",label:"Repeat delay",description:"Milliseconds before a held key starts repeating (100–2000).",type:"number"},
 {group:"Keyboard",key:"numlock_by_default",label:"NumLock at startup",description:"Enable the numeric keypad when the keyboard initializes.",type:"toggle"},
 {group:"Mouse",key:"sensitivity",label:"Pointer sensitivity",description:"Pointer speed from −1 to 1; zero is the device default.",type:"number"},
 {group:"Mouse",key:"natural_scroll",label:"Natural scrolling",description:"Reverse the scrolling direction so content follows your fingers.",type:"toggle",aliases:"mouse scroll direction"},
 {group:"Mouse",key:"accel_profile",label:"Acceleration profile",description:"Adaptive follows movement speed; flat uses a constant response.",type:"choice",options:["adaptive","flat",""]},
 {group:"Touchpad",key:"touchpad:tap-to-click",label:"Tap to click",description:"Tap the touchpad surface to click.",type:"toggle"},
 {group:"Touchpad",key:"touchpad:natural_scroll",label:"Touchpad natural scrolling",description:"Move content in the direction of your fingers.",type:"toggle"},
 {group:"Touchpad",key:"touchpad:disable_while_typing",label:"Disable while typing",description:"Reduce accidental pointer movement while using the keyboard.",type:"toggle"},
 {group:"Touchpad",key:"touchpad:scroll_factor",label:"Touchpad scroll speed",description:"Scroll multiplier between 0.1 and 5.",type:"number"}
];
