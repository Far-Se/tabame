#version 460 core
#include <flutter/runtime_effect.glsl>

// Same first seven float slots as Liquid Metal; corner radius is slot 7.
uniform vec2 uSize;
uniform float uTime;
uniform vec2 uPointer;
uniform float uActive;
uniform float uMode;
uniform float uRadius;
uniform vec3 uBackground;
uniform vec3 uForeground;
uniform vec3 uAccent;
out vec4 fragColor;

float roundBox(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 spectrum(float phase) {
  return 0.55 + 0.45 * cos(phase + vec3(0.0, 2.1, 4.2));
}

float luminance(vec3 color) {
  return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 uv = pixel / uSize;
  vec2 p = (pixel - uSize * 0.5) / max(uSize.x, uSize.y);
  vec2 mouse = (uPointer - uSize * 0.5) / max(uSize.x, uSize.y);
  float t = uTime * 0.13;
  float pointerLens = exp(-length(p - mouse) * 5.5) * uActive;
  float lens = length((p - vec2(0.22 * sin(t), -0.14)) * vec2(1.0, 1.6));
  float bend = lens * 9.0 + p.x * 2.3 + sin(p.y * 5.0 + t) * 0.5 - pointerLens * 0.38;
  float caustic = pow(0.5 + 0.5 * cos(bend - t), 24.0);
  float secondary = pow(0.5 + 0.5 * cos(bend * 1.35 + t + 1.6), 32.0);
  vec3 dispersion = spectrum(bend * 1.2 + t);
  float r = min(uRadius, min(uSize.x, uSize.y) * 0.5);
  float distanceToEdge = -roundBox(pixel - uSize * 0.5, uSize * 0.5, r);
  float rim = 1.0 - smoothstep(0.3, 2.8, distanceToEdge);
  float bevel = exp(-max(distanceToEdge, 0.0) * 0.20);
  float glint = pow(0.5 + 0.5 * sin(uv.x * 4.0 - uv.y * 3.0 + t), 8.0);
  vec3 prism = spectrum(uv.x * 5.0 + uv.y * 3.0 + t * 0.7);
  float dark = 1.0 - smoothstep(0.28, 0.62, luminance(uBackground));
  vec3 fieldBase = mix(mix(uBackground, vec3(1.0), 0.20), mix(uBackground, uForeground, 0.24), dark);
  vec3 glassBase = mix(mix(uBackground, vec3(1.0), 0.72), mix(uBackground, uForeground, 0.48), dark);

  if (uMode < 0.5) {
    // An illuminated optical field behind the clear panes. Dispersion is
    // procedural: it does not sample or distort desktop/preview content.
    vec3 color = mix(fieldBase, mix(fieldBase, vec3(1.0), 0.12), uv.y);
    color += (dispersion - 0.55) * (caustic * 0.18 + secondary * 0.07);
    color += vec3(caustic * 0.065 + pointerLens * 0.025);
    color += (uAccent - uBackground) * pointerLens * 0.035;
    color += (prism - 0.45) * rim * 0.20;
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
  } else if (uMode < 1.5) {
    // Translucent frosted interior, a dispersive bevel, and a traveling glint.
    vec3 color = glassBase;
    color += (prism - 0.60) * bevel * (0.16 + uActive * 0.13);
    color -= vec3(0.12, 0.09, 0.04) * uActive * 0.20;
    color += vec3(glint * rim * 0.15);
    color += (dispersion - 0.5) * caustic * 0.04;
    float alpha = clamp(0.42 + uActive * 0.20 + bevel * 0.22, 0.0, 0.92);
    fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
  } else {
    float alpha = (caustic * 0.018 + rim * (0.08 + glint * 0.12));
    fragColor = vec4(mix(uForeground, prism, 0.30) * alpha, alpha);
  }
}
