.pragma library

// Pure logical-coordinate reference; not a native popup/window implementation.
// Adapt into the project's QML JavaScript conventions only after integration review.
function fitPopup(anchor, desired, work, preferred, margin, gap) {
    preferred = preferred === undefined ? "bottom" : preferred;
    margin = margin === undefined ? 12 : margin;
    gap = gap === undefined ? 8 : gap;
    const sides = ["bottom", "top", "right", "left"];
    const numbers = [anchor.x, anchor.y, anchor.width, anchor.height,
        desired.width, desired.height, work.x, work.y, work.width, work.height,
        margin, gap];
    if (!numbers.every(Number.isFinite) || !sides.includes(preferred)
        || anchor.width < 0 || anchor.height < 0
        || desired.width <= 0 || desired.height <= 0
        || work.width <= 0 || work.height <= 0 || margin < 0 || gap < 0) {
        throw new Error("Invalid popup placement geometry");
    }
    // A very small work area cannot retain the requested outer margin.
    const inset = Math.min(margin, work.width / 4, work.height / 4);
    const left = work.x + inset, top = work.y + inset;
    const right = work.x + work.width - inset;
    const bottom = work.y + work.height - inset;
    const width = Math.min(desired.width, right - left);
    const height = Math.min(desired.height, bottom - top);
    const cx = anchor.x + anchor.width / 2;
    const cy = anchor.y + anchor.height / 2;
    const placements = {
        bottom: { x: cx - width / 2, y: anchor.y + anchor.height + gap },
        top: { x: cx - width / 2, y: anchor.y - gap - height },
        right: { x: anchor.x + anchor.width + gap, y: cy - height / 2 },
        left: { x: anchor.x - gap - width, y: cy - height / 2 }
    };
    const opposite = { bottom: "top", top: "bottom", right: "left", left: "right" };
    const order = [preferred, opposite[preferred]];
    for (const side of sides) if (!order.includes(side)) order.push(side);
    let chosen = order[0], bestArea = -1;
    for (const side of order) {
        const p = placements[side];
        const visibleWidth = Math.max(0, Math.min(p.x + width, right) - Math.max(p.x, left));
        const visibleHeight = Math.max(0, Math.min(p.y + height, bottom) - Math.max(p.y, top));
        const area = visibleWidth * visibleHeight;
        if (area > bestArea) { chosen = side; bestArea = area; }
        if (p.x >= left && p.y >= top && p.x + width <= right && p.y + height <= bottom) {
            chosen = side;
            break;
        }
    }
    const p = placements[chosen];
    return {
        x: Math.max(left, Math.min(p.x, right - width)),
        y: Math.max(top, Math.min(p.y, bottom - height)),
        width: width, height: height, preferredSide: chosen,
        sizeConstrained: width < desired.width || height < desired.height,
        effectiveMargin: inset
    };
}

if (typeof module !== "undefined") module.exports = { fitPopup };
