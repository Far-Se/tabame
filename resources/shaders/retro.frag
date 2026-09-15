#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uMotion;
uniform vec3 uBackground;
uniform vec3 uAccent;
uniform float uPixelSize;
uniform sampler2D uScreen;
out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 barrel(vec2 p) {
  float radius = dot(p, p);
  float curve = 1.0 + 0.018 * radius;
  p *= curve;
  p.x += sin(p.y * 11.0 + uTime * 1.6) * 0.0009 * uMotion;
  return p;
}

vec2 pixelUv(vec2 uv) {
  vec2 grid = max(uSize / max(uPixelSize, 1.0), vec2(1.0));
  return (floor(uv * grid) + 0.5) / grid;
}

vec3 sampleScreen(vec2 uv) {
  return texture(uScreen, clamp(pixelUv(uv), vec2(0.0), vec2(1.0))).rgb;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 p = pixel / uSize * 2.0 - 1.0;
  vec2 warped = barrel(p);
  vec2 uv = warped * 0.5 + 0.5;
  float inside = step(-1.0, warped.x) * step(warped.x, 1.0) * step(-1.0, warped.y) * step(warped.y, 1.0);
  float frame = floor(uTime * 24.0);

  // Sample the three phosphor channels from the same pixel block with a tiny
  // horizontal offset. It reads as color fringing without smearing text.
  float fringe = 0.0009;
  vec3 color = sampleScreen(uv);
  color.r = sampleScreen(uv + vec2(fringe, 0.0)).r;
  color.b = sampleScreen(uv - vec2(fringe, 0.0)).b;

  // A tight four-neighbor bloom keeps bright arcade accents alive after the
  // image has been reduced to its deliberately small pixel grid.
  vec2 block = max(vec2(uPixelSize) / uSize, vec2(1.0) / uSize);
  vec3 bloom = sampleScreen(uv + vec2(block.x, 0.0));
  bloom += sampleScreen(uv - vec2(block.x, 0.0));
  bloom += sampleScreen(uv + vec2(0.0, block.y));
  bloom += sampleScreen(uv - vec2(0.0, block.y));
  color += max(bloom * 0.25 - vec3(0.16), vec3(0.0)) * 0.16;

  // Early game screens used a small, hard palette. Keep source colors intact
  // while nudging them toward that stepped look.
  vec3 stepped = floor(color * 26.0 + 0.5) / 26.0;
  color = mix(color, stepped, 0.12);

  float scanline = 0.95 + 0.05 * cos(pixel.y * 3.14159265);
  float grille = 0.99 + 0.01 * cos(pixel.x * 2.0943951);
  float vignette = 1.0 - 0.22 * pow(clamp(dot(p, p) * 0.5, 0.0, 1.0), 1.35);
  float staticNoise = hash(floor(pixel / max(uPixelSize, 1.0)) + frame * uMotion);
  float sweep = exp(-pow((uv.y - fract(uTime * 0.065)) * 28.0, 2.0));

  color *= scanline * grille * vignette;
  color += (staticNoise - 0.5) * 0.008 * uMotion;
  color += uAccent * 0.007 * sweep * uMotion;
  // Preserve a light cabinet edge for the light arcade palette.
  float backgroundLuma = dot(uBackground, vec3(0.2126, 0.7152, 0.0722));
  float edgeShade = mix(0.42, 0.88, smoothstep(0.35, 0.75, backgroundLuma));
  fragColor = vec4(mix(uBackground * edgeShade, clamp(color, 0.0, 1.0), inside), 1.0);
}
