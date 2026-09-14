#version 460 core
#include <flutter/runtime_effect.glsl>

// _ThermalPainter writes 80 floats in this order. Bounds are panel-local
// center/half-size; state is temperature/diffusion width. No texture captures.
uniform vec2 uSize;
uniform vec4 uSelection;
uniform vec2 uSelectionState;
uniform vec4 uHover;
uniform vec2 uHoverState;
uniform vec4 uRow0;
uniform vec2 uRow0State;
uniform vec4 uRow1;
uniform vec2 uRow1State;
uniform vec4 uRow2;
uniform vec2 uRow2State;
uniform vec4 uTouch0;
uniform vec2 uTouch0State;
uniform vec4 uTouch1;
uniform vec2 uTouch1State;
uniform vec4 uTouch2;
uniform vec2 uTouch2State;
uniform vec4 uType0;
uniform vec2 uType0State;
uniform vec4 uType1;
uniform vec2 uType1State;
uniform vec4 uType2;
uniform vec2 uType2State;
uniform vec4 uClick0;
uniform vec2 uClick0State;
uniform vec4 uClick1;
uniform vec2 uClick1State;
out vec4 fragColor;

float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float heatSource(vec2 p, vec4 bounds, vec2 state, vec2 warp) {
  if (state.x < 0.0001) return 0.0;
  float radius = min(5.0, min(bounds.z, bounds.w));
  vec2 q = abs(p - bounds.xy + warp) - bounds.zw + radius;
  float distance = max(0.0, length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius);
  float spread = max(state.y, 1.0);
  return state.x * exp(-distance * distance / (spread * spread));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  // Stationary mineral structure: heat follows the surface instead of making
  // the stone itself flow. Several spatial scales break up perfect heat rings.
  float strata = noise(p * vec2(0.017, 0.031));
  float stone = noise(p * 0.055 + strata * 2.1);
  float grain = hash(floor(p * 1.25));
  vec2 warp = vec2(strata - 0.5, stone - 0.5) * 8.0;

  float heat = heatSource(p, uSelection, uSelectionState, warp);
  heat += heatSource(p, uHover, uHoverState, warp);
  heat += heatSource(p, uRow0, uRow0State, warp);
  heat += heatSource(p, uRow1, uRow1State, warp);
  heat += heatSource(p, uRow2, uRow2State, warp);
  heat += heatSource(p, uTouch0, uTouch0State, warp);
  heat += heatSource(p, uTouch1, uTouch1State, warp);
  heat += heatSource(p, uTouch2, uTouch2State, warp);
  heat += heatSource(p, uType0, uType0State, warp);
  heat += heatSource(p, uType1, uType1State, warp);
  heat += heatSource(p, uType2, uType2State, warp);
  heat += heatSource(p, uClick0, uClick0State, warp);
  heat += heatSource(p, uClick1, uClick1State, warp);
  heat *= 0.9 + stone * 0.2;
  float temperature = 1.0 - exp(-heat * 1.25);

  vec3 mineral = vec3(0.0784, 0.0941, 0.1098);
  mineral += (strata - 0.5) * vec3(0.014, 0.017, 0.018);
  mineral += (grain - 0.5) * 0.013;
  // A faint fractured seam remains visible while the panel is completely cold.
  float seam = 1.0 - smoothstep(0.008, 0.032, abs(stone - 0.48));
  mineral -= seam * 0.009;

  vec3 slate = vec3(0.185, 0.204, 0.214);
  vec3 rust = vec3(0.34, 0.143, 0.086);
  vec3 amber = vec3(0.445, 0.250, 0.095);
  vec3 color = mix(mineral, slate, smoothstep(0.0, 0.23, temperature));
  color = mix(color, rust, smoothstep(0.18, 0.58, temperature));
  color = mix(color, amber, smoothstep(0.56, 0.94, temperature));

  // Low-contrast isotherms make diffusion and cooling readable as material,
  // without turning the panel into a rainbow thermal-camera overlay.
  float contourPhase = temperature * 7.0 + (stone - 0.5) * 0.22;
  float contourDistance = abs(fract(contourPhase) - 0.5);
  float contour = 1.0 - smoothstep(0.035, 0.095, contourDistance);
  float contourVisibility = smoothstep(0.07, 0.24, temperature) * (1.0 - smoothstep(0.8, 1.0, temperature));
  color += contour * contourVisibility * vec3(0.021, 0.012, 0.004);
  color += (grain - 0.5) * temperature * 0.011;

  float edge = min(min(p.x, uSize.x - p.x), min(p.y, uSize.y - p.y));
  color *= 0.94 + 0.06 * smoothstep(0.0, 18.0, edge);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
