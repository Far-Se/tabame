#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uMotion;
uniform vec3 uBackground;
uniform vec3 uAccent;
uniform sampler2D uScreen;
out vec4 fragColor;

float noise(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
vec3 phosphor(vec2 uv) {
  vec3 source = texture(uScreen, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
  // Preserve Launcher Colors and icon hues through the optical pass.
  return source;
}
void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 p = pixel / uSize * 2.0 - 1.0;
  // Keep this mapping in sync with _RenderCrt.hitTestChildren.
  vec2 uv = (p * (1.0 + 0.018 * dot(p, p)) + 1.0) * 0.5;
  float frame = floor(uTime * 30.0);

  // Gentle continuous drift: at most 0.08 logical pixels, over 5–11 seconds.
  float jitter = (noise(vec2(frame, 19.0)) - 0.5) * 0.05;
  // float jitter = sin(uTime * 0.6) * 0.055 + sin(uTime * 1.2) * 0.025;

  uv.x += jitter * uMotion / uSize.x;
  vec2 stepUV = vec2(1.6) / uSize;
  vec3 color = phosphor(uv);
  vec3 bloom = phosphor(uv + vec2(stepUV.x, 0.0));
  bloom += phosphor(uv - vec2(stepUV.x, 0.0));
  bloom += phosphor(uv + vec2(0.0, stepUV.y));
  bloom += phosphor(uv - vec2(0.0, stepUV.y));
  bloom += phosphor(uv + stepUV * 2.0) * 0.5;
  bloom += phosphor(uv - stepUV * 2.0) * 0.5;
  color += max(bloom / 5.0 - vec3(0.13), vec3(0.0)) * 0.22;
  float scan = 0.94 + 0.06 * cos(pixel.y * 2.0943951);
  float grille = 0.98 + 0.02 * cos(pixel.x * 2.0943951);
  float vignette = 1.0 - 0.19 * pow(clamp(dot(p, p) * 0.5, 0.0, 1.0), 1.4);
  color *= scan * grille * vignette;
  color += (noise(floor(pixel) + frame * uMotion) - 0.5) * 0.023;
  float sweep = exp(-pow((uv.y - fract(uTime * 0.075)) * 24.0, 2.0));
  color += uAccent * 0.009 * sweep * uMotion;
  float edge = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
  fragColor = vec4(mix(uBackground * 0.45, clamp(color, 0.0, 1.0), edge), 1.0);
}
