#version 440

// The Strata field: the bar's plate and the drop growing out of it as one
// signed distance field (components/StrataBarFrame.qml draws the part inside
// the bar's window, components/DropFrame.qml the part below it, from the same
// geometry). Both are chamfered boxes joined by a circular smooth-minimum, so
// the drop's body, which begins inside the plate, swells out of the bar's
// lower edge through tangent fillets from its first pixel, and the grow
// curve's overshoot stretches that swell. Fill, Grain and Living Edge are
// isolines of the field. The drop may be squashed by a 2x2 deform about the
// join; the bar never deforms. After the blob renderer of caelestia-dots/shell
// (plugin/src/Caelestia/Blobs/shaders/blob.frag at b51fdb35, GPL-3.0; see
// docs/LICENSES.md); sdBox and the smooth-minimum are Inigo Quilez's standard
// forms (MIT); the chamfers, the paint band and the composition are CEDAR's.
//
// Rebuild the shipped strata.frag.qsb with Qt 6.11's qsb (qt6-shadertools):
//   /usr/lib/qt6/bin/qsb --glsl "300 es,330,150,120" --hlsl 50 --msl 12 -o strata.frag.qsb strata.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // item size in px
    vec4 barRect;     // cx, cy, hw, hh of the bar's plate, item px
    vec4 barCuts;     // chamfer per corner: tr, br, bl, tl
    vec4 dropRect;    // cx, cy, hw, hh of the undeformed drop (hw 0 = none)
    vec4 dropCuts;
    vec4 invDeform;   // inverse of the drop's 2x2 deform: m00, m10, m01, m11
    vec2 origin;      // the deform's fixed point (the join)
    float minEig;     // smallest eigenvalue of the deform, keeps the metric
    float smoothing;  // k: the fillet radius of the join
    float side;       // 0 = reach axis is y (bar above), 1 = x (bar left)
    float paintFrom;  // this instance paints the band paintFrom..paintTo on
    float paintTo;    //   the reach axis (item px); the other window the rest
    vec2 seatGap;     // bar's top edge is left unstroked between these x (item px)
    vec4 fill;
    vec4 edge;        // contour colour on the drop (brightens while lit)
    vec4 restEdge;    // contour colour on the bar
    vec4 grain;
    float edgeWidth;
    float grainInset;
    float grainAlpha;
};

float sdChamferBox(vec2 p, vec2 hs, vec4 c) {
    float cc = (p.x > 0.0) ? ((p.y > 0.0) ? c.y : c.x) : ((p.y > 0.0) ? c.z : c.w);
    vec2 q = abs(p) - hs;
    float box = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
    float cham = (q.x + q.y + cc) * 0.70710678;
    return max(box, cham);
}

float smin(float a, float b, float k) {
    return max(k, min(a, b)) - length(max(vec2(k) - vec2(a, b), vec2(0.0)));
}

void main() {
    vec2 pixel = qt_TexCoord0 * size;
    float reachCoord = side > 0.5 ? pixel.x : pixel.y;
    if (reachCoord < paintFrom || reachCoord >= paintTo)
        discard;

    float dBar = sdChamferBox(pixel - barRect.xy, barRect.zw, barCuts);

    float dDrop = 1e5;
    if (dropRect.z > 0.0) {
        mat2 inv = mat2(invDeform.xy, invDeform.zw);
        vec2 p = origin + inv * (pixel - origin);
        dDrop = sdChamferBox(p - dropRect.xy, dropRect.zw, dropCuts) * max(minEig, 0.01);
    }

    float k = max(smoothing, 0.5);
    float d = smin(dBar, dDrop, k);

    float cover = clamp(0.5 - d, 0.0, 1.0);

    // The drop's share of a pixel: 1 where the drop is nearer, 0 where the
    // bar is. Colours the contour and confines the Grain to the drop.
    float dropShare = clamp(0.5 + (dBar - dDrop) / k, 0.0, 1.0);

    // The bar's top edge stays unstroked beneath the Core's seat.
    float seat = (side < 0.5 && pixel.x > seatGap.x && pixel.x < seatGap.y && pixel.y < barRect.y) ? 0.0 : 1.0;

    float edgeLine = (1.0 - clamp(abs(d) - edgeWidth * 0.5 + 0.5, 0.0, 1.0)) * seat;
    float grainLine = (1.0 - clamp(abs(d + grainInset), 0.0, 1.0)) * dropShare * grainAlpha;
    vec4 lineColour = mix(restEdge, edge, dropShare);

    // Source-over: Foundation, Grain, Living Edge. Qt hands colours premultiplied.
    vec4 col = fill * cover;
    vec4 g = grain * grainLine;
    col = g + col * (1.0 - g.a);
    vec4 e = lineColour * edgeLine;
    col = e + col * (1.0 - e.a);

    fragColor = col * qt_Opacity;
}
