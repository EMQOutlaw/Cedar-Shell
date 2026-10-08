.pragma library

// Kinetic Type policy: what may move when a label's meaning changes. Pure,
// so the label components only animate what this allows.
//
// A character relay keeps the glyphs that stayed and moves the ones that
// changed. It is only safe for text whose code points are single graphemes
// drawn left to right in a simple script: printable ASCII plus Latin-1
// letters. Anything else (combining marks, emoji, RTL, CJK, long strings)
// gets a whole-label transition, which is always correct.

var simple = /^[\x20-\x7EÀ-ɏ]*$/;

// Code points, not UTF-16 units; a surrogate pair stays one unit.
function points(text) { return Array.from(String(text || "")); }

// Whether a character relay may run on this change.
function relayable(from, to, maximum) {
    const a = String(from || ""), b = String(to || "");
    if (a === b || !a || !b) return false;
    if (!simple.test(a) || !simple.test(b)) return false;
    const n = Math.max(points(a).length, points(b).length);
    return n <= (maximum === undefined ? 16 : maximum);
}

// The relay plan: the shared prefix and suffix stay still; the middle of the
// old text leaves and the middle of the new text arrives.
function relay(from, to) {
    const a = points(from), b = points(to);
    let prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix]) prefix++;
    let suffix = 0;
    while (suffix < a.length - prefix && suffix < b.length - prefix && a[a.length - 1 - suffix] === b[b.length - 1 - suffix]) suffix++;
    return {
        prefix: a.slice(0, prefix).join(""),
        suffix: b.slice(b.length - suffix).join(""),
        leaving: a.slice(prefix, a.length - suffix).join(""),
        arriving: b.slice(prefix, b.length - suffix).join("")
    };
}

// Which transition to run for a change, given the requested style.
//   "relay"   character relay when safe, else "resolve"
//   "resolve" vertical resolution (out up, in from below)
//   "fade"    whole-label crossfade
//   "none"    static update
function choose(style, from, to, maximum, reducedMotion) {
    if (reducedMotion || style === "none") return "none";
    if (String(from || "") === String(to || "")) return "none";
    if (style === "relay") return relayable(from, to, maximum) ? "relay" : "resolve";
    if (style === "reveal") return simple.test(String(to || "")) && points(to).length <= Math.max(maximum, 48) ? "reveal" : "fade";
    if (style === "resolve" || style === "fade") return style;
    return "fade";
}

// Semantic compression: the longest variant that fits. `measure` returns a
// variant's width; variants are ordered longest first.
function fit(variants, available, measure) {
    const rows = (variants || []).filter(v => typeof v === "string");
    for (let i = 0; i < rows.length; i++) if (measure(rows[i]) <= available) return rows[i];
    return rows.length ? rows[rows.length - 1] : "";
}

// A rate limit for numbers and clocks: a change arriving within `window` ms
// of the previous one is shown statically.
function allowed(lastChangeAt, now, window) { return now - lastChangeAt >= (window === undefined ? 800 : window); }
