#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uMotion;
uniform vec3 uBackground;
uniform vec3 uAccent;
uniform float uPixelSize;
uniform sampler2D uScreen;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float pixelSize = max(uPixelSize, 1.0);
  vec2 uv = (floor(p / pixelSize) + 0.5) * pixelSize / uSize;
  vec4 source = texture(uScreen, clamp(uv, vec2(0.0), vec2(1.0)));
  // A console palette and a faint pixel lattice preserve compact UI lettering.
  vec3 palette = floor(source.rgb * 31.0 + 0.5) / 31.0;
  vec3 color = mix(source.rgb, palette, 0.28);
  float lattice = 0.985 + 0.015 * cos(p.y * 3.14159265);
  color *= lattice;
  // Gold blocks shimmer in discrete animation frames, like cartridge sprites.
  float gold = step(0.65, source.r) * step(0.35, source.g) * (1.0 - step(0.4, source.b));
  float phase = floor(uTime * 5.0);
  float sparkle = step(0.94, fract((floor(p.x / 3.0) + floor(p.y / 3.0) + phase) / 19.0));
  color += mix(uAccent, vec3(1.0, 0.91, 0.62), 0.85) * gold * sparkle * 0.065 * uMotion;
  color = mix(uBackground, color, source.a);
  fragColor = vec4(clamp(color, 0.0, 1.0), source.a);
}
