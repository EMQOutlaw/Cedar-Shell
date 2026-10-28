.pragma library

// Strata: where a surface that grows out of the bar sits. Pure arithmetic
// over logical pixels, so the drop's geometry is decided once per open,
// retarget or resize and then only interpolated. The controller feeds it
// the bar's width (the drop's window spans the bar), the control's screen
// rect when there is one, the panel's wanted size and the monitor's edge
// inset; it returns the rect the renderer animates to.

// The panel's x inside the drop window: centred on its control, else on the
// screen, and never closer than `edge` to either side.
function panelX(barWidth, anchor, width, sideInset, edge) {
    const centre = anchor && isFinite(anchor.x) && isFinite(anchor.width) && anchor.width > 0 ? anchor.x + anchor.width / 2 - (sideInset || 0) : barWidth / 2;
    return Math.round(Math.max(edge, Math.min(centre - width / 2, barWidth - width - edge)));
}

// Clamp a wanted width to the bar with the edge kept free on both sides.
function panelWidth(barWidth, wanted, edge) { return Math.max(0, Math.min(barWidth - 2 * edge, wanted)); }

// Clamp a wanted height to what fits under the bar.
function panelHeight(available, wanted, minimum) { return Math.max(minimum, Math.min(available, wanted)); }

// The target rect for a topic: {x, width, height, origin} where origin is the
// panel-local x of the control's centre (for the tie line), or -1.
function target(input) {
    const edge = input.edge === undefined ? 12 : input.edge;
    const width = panelWidth(input.barWidth, input.wantedWidth, edge);
    const x = panelX(input.barWidth, input.anchor, width, input.sideInset, edge);
    const height = panelHeight(input.availableHeight, input.wantedHeight, input.minimumHeight === undefined ? 160 : input.minimumHeight);
    const origin = input.anchor && input.anchor.width > 0 ? input.anchor.x + input.anchor.width / 2 - (input.sideInset || 0) - x : -1;
    return { x: x, width: width, height: height, origin: origin };
}

// Does the next surface share the current one's origin region? Then the
// surface morphs in place; otherwise it folds back into the bar and grows
// again from the new control, because the two are different objects.
function sharesOrigin(current, next, tolerance) {
    if (!current || !next) return false;
    const tol = tolerance === undefined ? 48 : tolerance;
    const a = current.origin >= 0 ? current.x + current.origin : current.x + current.width / 2;
    const b = next.origin >= 0 ? next.x + next.origin : next.x + next.width / 2;
    return Math.abs(a - b) <= tol;
}

// One number for the whole transition: how far the geometry has travelled
// from `from` to `to`, by height, for content gating.
function progress(from, to, current) {
    if (!from || !to || to.height === from.height) return 1;
    return Math.max(0, Math.min(1, (current - from.height) / (to.height - from.height)));
}

// Where the Core pill's window sits on its output: {left, top, width,
// maxHeight} in logical pixels. Under the top bar the pill is integrated:
// centred on the monitor at the bar frame's inset. Beside the Understory
// (left) bar it floats: centred in the usable area that remains once the bar
// and its margin are reserved, at the same inset from the top edge. Pure
// arithmetic so the window only assigns the result.
function corePlacement(input) {
    const num = (v, fallback) => (Number.isFinite(v) && v > 0 ? v : fallback);
    const screenWidth = num(input.screenWidth, 1920);
    const screenHeight = num(input.screenHeight, 1080);
    const barHeight = num(input.barHeight, 44);
    const inset = Number.isFinite(input.barInset) ? Math.max(0, input.barInset) : 5;
    const margin = input.barDetached ? num(input.barMargin, 0) : 0;
    const vertical = !!input.barVertical;
    const wanted = Math.round(num(input.wantedWidth, 620));
    // Height: what remains under the bar (none when it is on the left) minus
    // 60 px of breathing room, floored at 200 — but a tiny output never
    // promises more than it has, and the box ends inside the output.
    const available = Math.max(1, Math.round(screenHeight - (vertical ? 0 : barHeight)));
    let maxHeight = available > 60 ? Math.max(Math.min(200, available), available - 60) : available;
    // The pill's own resting height, used only to centre the window's top
    // edge vertically; the hub still expands downward from there within
    // maxHeight.
    const restingHeight = num(input.restingHeight, 40);
    let left, width, top;
    if (vertical) {
        // Floating: docked just beside the bar with a small gutter, and
        // vertically centred on the output rather than pinned to the top.
        // A bar wider than the output leaves no usable area; the pill then
        // stays at the right edge, never past it.
        const reserved = num(input.barWidth, 0) + margin;
        const usable = Math.max(0, screenWidth - reserved);
        const gutter = usable > 16 ? 4 : 0;
        width = Math.max(1, Math.min(wanted, Math.round(usable - gutter)));
        left = Math.round(reserved + gutter);
        top = Math.round((screenHeight - restingHeight) / 2);
    } else {
        // Integrated: the historical geometry, exactly: min(620, monitor) centred.
        width = Math.max(1, Math.min(wanted, Math.round(screenWidth)));
        left = Math.round((screenWidth - width) / 2);
        top = margin + inset;
    }
    left = Math.max(0, Math.min(left, Math.round(screenWidth) - width));
    top = Math.max(0, Math.min(top, Math.round(screenHeight) - 1));
    maxHeight = Math.max(1, Math.min(maxHeight, Math.round(screenHeight) - top));
    return { left: left, top: top, width: width, maxHeight: maxHeight };
}
