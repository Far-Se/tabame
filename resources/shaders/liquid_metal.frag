#version 460 core
#include <flutter/runtime_effect.glsl>

// Float slots: size 0..1, time 2, pointer 3..4, active 5, mode 6.
uniform vec2 uSize;
uniform float uTime;
uniform vec2 uPointer;
uniform float uActive;
uniform float uMode;
out vec4 fragColor;

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 uv = pixel / uSize;
  vec2 p = (pixel - 0.5 * uSize) / max(uSize.x, uSize.y);
  vec2 mouse = (uPointer - 0.5 * uSize) / max(uSize.x, uSize.y);
  float t = uTime;
  float radius = length(p - mouse);
  float ripple = sin(radius * 34.0 - t * 2.0) * exp(-radius * 7.0) * uActive;
  float fold = p.x * 3.4 + p.y * 1.8
      + sin(p.y * 5.0 + t * 0.35) * 0.62
      + sin(p.x * 4.0 - t * 0.25) * 0.32 + ripple * 0.12;
  float reflection = pow(0.5 + 0.5 * sin(fold * 5.0), 14.0);
  float broad = 0.5 + 0.5 * sin(fold * 2.0 - 0.6);
  float brushed = sin(pixel.y * 2.4 + sin(pixel.x * 0.013)) * 0.003;
  vec3 graphite = vec3(0.064, 0.070, 0.079);
  vec3 silver = vec3(0.73, 0.71, 0.66);

  // Mode 0 is the deep frame, 1 is a raised surface, 2 is a fine
  // translucent reflection over existing controls and preview content.
  if (uMode > 1.5) {
    float alpha = 0.012 + reflection * 0.045;
    fragColor = vec4(silver * alpha, alpha);
  } else {
    float edge = min(min(pixel.x, uSize.x - pixel.x), min(pixel.y, uSize.y - pixel.y));
    float rim = 1.0 - smoothstep(0.0, 1.4, edge);
    float intensity = mix(0.15, 0.24, uMode) + uActive * 0.08;
    vec3 color = graphite + vec3(broad * 0.028 + brushed);
    color += silver * reflection * intensity;
    color += silver * rim * (0.16 + broad * 0.22);
    color += vec3(0.027, 0.025, 0.021) * uActive;
    // Keep the reading area dark; reflected metal gathers at the perimeter.
    float centerShade = smoothstep(0.05, 0.4, abs(uv.x - 0.5));
    color = mix(color * 0.80, color, centerShade);
    fragColor = vec4(color, 1.0);
  }
}
