#version 460 core
#include <flutter/runtime_effect.glsl>

// Tightly packed floats, matching _LampPainter:
// size (2), light (2), day (1), dark (1), pool (3), shadow (3), lip (3).
uniform vec2 uSize;
uniform vec2 uLight;
uniform float uDay;
uniform float uDark;
uniform vec3 uPool;
uniform vec3 uShadow;
uniform vec3 uLip;

out vec4 fragColor;

void main() {
    vec2 pixel = FlutterFragCoord().xy;
    vec2 size = max(uSize, vec2(1.0));
    vec2 uv = pixel / size;

    // The pool stays wide enough that a row of titles is one contrast.
    // uDay is 1 in the mid-afternoon and 0 in the middle of the night.
    vec2 center = vec2(0.50 + uLight.x * 0.045, 0.46 + uLight.y * 0.03);
    vec2 p = uv - center;
    p.x *= 0.62;
    float falloff = length(p) / mix(0.96, 1.12, uDay);
    float core = 1.0 - smoothstep(0.50, 0.92, falloff);

    vec3 evening = mix(uPool, uLip, 0.12 * (1.0 - uDay));
    vec3 color = mix(uShadow, evening, core);

    // The shade is above the panel. Only the top edge catches it, so the
    // warm band never crosses a window title.
    float shade = 1.0 - smoothstep(0.0, 0.055, uv.y);
    color = mix(color, uLip, shade * mix(0.30, 0.78, 1.0 - uDay));

    vec3 cool = uShadow * vec3(0.96, 0.98, 1.05);
    color = mix(color, cool, (1.0 - core) * uDay * (1.0 - uDark) * 0.55);

    float grain = fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715))));
    color += (grain - 0.5) * mix(0.016, 0.004, core);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
