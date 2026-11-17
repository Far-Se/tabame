#version 460 core
#include <flutter/runtime_effect.glsl>

// LodestonePainter float order:
// size (2), pole (2), stone center/half-size (4), pull (1), swing (1),
// time (1), pitch (1), dark (1), foreground (3), accent (3). No samplers.
//
// A staggered lattice of compass needles. With no selection they rest pointing
// east. A selection is a lodestone: every needle turns to its pole, and the
// ones close to the stone pick up the accent. Output is premultiplied and
// transparent between needles, so the frame's own fill shows through.
uniform vec2 uSize;
uniform vec2 uPole;
uniform vec4 uStone;
uniform float uPull;
uniform float uSwing;
uniform float uTime;
uniform float uPitch;
uniform float uDark;
uniform vec3 uForeground;
uniform vec3 uAccent;

out vec4 fragColor;

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    float pitch = max(uPitch, 6.0);

    // One needle per cell; odd rows sit half a pitch over.
    float row = floor(p.y / pitch);
    float shift = mod(row, 2.0) * 0.5 * pitch;
    float col = floor((p.x + shift) / pitch);
    vec2 center = vec2((col + 0.5) * pitch - shift, (row + 0.5) * pitch);
    float seed = hash(vec2(col, row));

    vec2 toPole = uPole - center;
    float reach = length(toPole);
    vec2 aim = toPole / max(reach, 0.001);

    // The small bias keeps needles due east of the pole from collapsing while
    // the pull fades in.
    vec2 heading = normalize(mix(vec2(1.0, 0.0), aim, uPull) + vec2(0.0, 0.0008));

    // A moved stone rings the field once: a wave leaves the pole and dies out.
    float ring = uSwing * 0.42 * (0.25 + 0.75 * exp(-reach / 170.0))
        * sin(uTime * 26.0 - reach * 0.045 + seed * 0.9);
    float cs = cos(ring);
    float sn = sin(ring);
    heading = vec2(heading.x * cs - heading.y * sn, heading.x * sn + heading.y * cs);

    vec2 q = p - center;
    float along = dot(q, heading);
    float across = dot(q, vec2(-heading.y, heading.x));

    // Distance from this needle's pivot to the selected row.
    vec2 box = abs(center - uStone.xy) - uStone.zw;
    float outside = length(max(box, 0.0)) + min(max(box.x, box.y), 0.0);

    float halo = exp(-max(outside, 0.0) / (pitch * 1.5));
    float burst = exp(-reach / (pitch * 5.0));
    float charge = uPull * clamp(max(halo, burst), 0.0, 1.0);

    float halfLength = pitch * mix(0.27, 0.36, charge) * (0.9 + 0.2 * seed);
    float halfWidth = mix(0.5, 0.8, charge);
    float dist = length(vec2(max(abs(along) - halfLength, 0.0), across)) - halfWidth;
    float mask = 1.0 - smoothstep(-0.5, 0.5, dist);

    // The end facing the pole is the bright one. At rest needles are even.
    float taper = mix(0.35, 1.0, smoothstep(-halfLength, halfLength, along));
    taper = mix(1.0, taper, uPull);

    float rest = mix(0.115, 0.095, uDark);
    float lit = mix(0.50, 0.60, uDark);
    float alpha = mix(rest, lit, pow(charge, 1.15)) * taper * mask;

    // The stone itself stays clear. The row paints its own plate there, and
    // testing the pivot keeps needles whole instead of cutting them.
    float clear = smoothstep(-1.0, pitch * 0.35, outside);
    alpha *= mix(1.0, clear, uPull);

    // Needles whose pivot is too close to the edge fade out whole, so the
    // boundary never slices one.
    float edge = min(min(center.x, uSize.x - center.x), min(center.y, uSize.y - center.y));
    alpha *= smoothstep(0.0, pitch * 0.5, edge);

    vec3 ink = mix(uForeground, uAccent, smoothstep(0.08, 0.55, charge));
    fragColor = vec4(ink * alpha, alpha);
}
