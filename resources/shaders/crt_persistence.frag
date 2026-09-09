#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uDecay;
uniform sampler2D uCurrent;
uniform sampler2D uHistory;
out vec4 fragColor;

// Frame-rate independent phosphor persistence, before optical distortion.
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 current = texture(uCurrent, uv).rgb;
  vec3 history = texture(uHistory, uv).rgb;
  fragColor = vec4(max(current, history * uDecay), 1.0);
}
