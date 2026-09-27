#include <flutter/runtime_effect.glsl>

// Float layout shared with _LiquidGlassPainter: 18 floats, no image samplers.
uniform vec2 uSize;          // 0..1: logical pixels
uniform vec2 uLight;         // 2..3: finite pointer response, -0.5..0.5
uniform float uRadius;       // 4: resolved launcher corner radius
uniform float uCorner;       // 5: round / squircle / bevel
uniform float uKind;         // 6: frame / search / selection
uniform float uOpacity;      // 7: existing native glass panel opacity
uniform vec3 uBackground;    // 8..10
uniform vec3 uForeground;    // 11..13
uniform vec3 uAccent;        // 14..16
uniform float uDark;         // 17: brightness resolved from the user's surface

out vec4 fragColor;

float square(float value) {
    return value * value;
}

// The zero contours match LauncherCorners' round, exponent-4 squircle, and
// straight bevel. Flutter supplies the final antialiased clip for every shape.
float lensDistance(vec2 p) {
    vec2 halfSize = uSize * 0.5;
    float r = clamp(uRadius, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - (halfSize - vec2(r));
    if (uCorner > 1.5) {
        return max(max(q.x, q.y) - r, (q.x + q.y - r) * 0.70710678);
    }
    vec2 outside = max(q, 0.0);
    if (uCorner > 0.5 && r > 0.0) {
        vec2 v = outside / max(r, 0.001);
        vec2 squared = v * v;
        float norm = pow(max(dot(squared, squared), 0.00000001), 0.25);
        return (norm - 1.0) * r + min(max(q.x, q.y), 0.0);
    }
    return length(outside) + min(max(q.x, q.y), 0.0) - r;
}

// A soft, palette-derived environment. Refraction samples this function at
// displaced coordinates; it does not capture desktop, preview, or text pixels.
vec3 environment(vec2 uv) {
    float ribbonY = 0.34 + 0.16 * sin(uv.x * 5.2 - 0.7);
    float ribbon = exp(-square((uv.y - ribbonY) * 6.0));
    vec2 poolOffset = (uv - vec2(0.91, 0.94)) * vec2(1.1, 1.5);
    float pool = exp(-dot(poolOffset, poolOffset) * 4.5);
    float light = exp(-dot(uv - vec2(0.18, 0.05), uv - vec2(0.18, 0.05)) * 6.0);
    vec3 color = mix(uBackground, uAccent, ribbon * 0.13 + pool * 0.17);
    return mix(color, vec3(1.0), light * mix(0.42, 0.055, uDark));
}

void main() {
    vec2 pixel = FlutterFragCoord().xy;
    vec2 uv = pixel / max(uSize, vec2(1.0));
    vec2 p = pixel - uSize * 0.5;
    float depth = max(0.0, -lensDistance(p));
    vec2 gradient = vec2(
        lensDistance(p + vec2(0.5, 0.0)) - lensDistance(p - vec2(0.5, 0.0)),
        lensDistance(p + vec2(0.0, 0.5)) - lensDistance(p - vec2(0.0, 0.5))
    );
    vec2 normal = gradient / max(length(gradient), 0.0001);
    float raised = step(0.5, uKind);
    float selected = step(1.5, uKind);
    float width = max(2.0, min(mix(18.0, 10.0, raised), min(uSize.x, uSize.y) * 0.22));
    float slope = 1.0 - smoothstep(0.0, width, depth);

    // A convex edge bends the environment inward. Separate RGB travel gives
    // restrained dispersion at the rim, with no rainbow across the text.
    vec2 bend = normal * slope * slope * mix(24.0, 15.0, raised) / max(uSize, vec2(1.0));
    vec2 parallax = uLight * 0.025;
    vec3 refracted = vec3(
        environment(uv - bend * 1.045 + parallax).r,
        environment(uv - bend + parallax).g,
        environment(uv - bend * 0.955 + parallax).b
    );
    vec3 frost = mix(uBackground, uAccent, selected * mix(0.09, 0.15, uDark));
    vec3 color = mix(frost, refracted, mix(0.38, 0.60, raised) + slope * 0.20);

    vec2 lightDirection = normalize(vec2(-0.65, -0.85) + uLight * 0.75);
    float facing = dot(normal, lightDirection);
    float rim = exp(-depth * 1.55);
    float innerEdge = exp(-abs(depth - 2.0) * 1.65);
    float fresnel = pow(slope, 3.0);
    float glint = pow(max(facing, 0.0), 5.0);
    float opposing = pow(max(-facing, 0.0), 4.0);
    float caustic = exp(-square((depth - width * 0.68) / 2.2));
    color *= 1.0 - innerEdge * mix(0.10, 0.16, uDark);
    color = mix(color, uForeground, innerEdge * 0.018);
    color = mix(color, vec3(1.0), rim * (0.24 + glint * 0.58 + opposing * 0.19));
    color += fresnel * glint * mix(0.14, 0.10, uDark);
    color = mix(color, mix(uAccent, vec3(1.0), 0.72), caustic * opposing * 0.12);

    // A quiet diagonal reflection gives broad lenses volume between the rims.
    float sheen = exp(-square((uv.x * 0.28 + uv.y - 0.12 - uLight.x * 0.035) * 6.5));
    color = mix(color, vec3(1.0), sheen * mix(0.10, 0.035, uDark) * raised);
    float grain = fract(sin(dot(pixel, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    color += grain / 510.0;

    // Preserve the compositor's user opacity while retaining a visible edge.
    float alpha = clamp(uOpacity + rim * (1.0 - uOpacity) * 0.65, 0.0, 1.0);
    fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
}
