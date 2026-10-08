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
