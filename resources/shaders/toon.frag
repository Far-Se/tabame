#version 460 core
#include <flutter/runtime_effect.glsl>

// Borderlands-inspired print pass: cel bands, bold ink, stepped lighting, and halftone shadows.
// Keep the shared CrtSurface uniform layout, even for this static effect.
uniform vec2 uSize;
uniform float uTime;
uniform float uMotion;
uniform vec3 uBackground;
uniform vec3 uAccent;
uniform sampler2D uScreen;
out vec4 fragColor;

float luminance(vec3 color) {
  return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 sampleScreen(vec2 uv) {
  // Captures include an opaque background, including beneath translucent UI.
  return texture(uScreen, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 size = max(uSize, vec2(1.0));
  vec2 uv = pixel / size;
  // A wider footprint gives silhouettes a visible printed contour.
  vec2 texel = 1.5 / size;
  vec3 source = sampleScreen(uv);
  float luma = luminance(source);
  float nw = luminance(sampleScreen(uv + texel * vec2(-1.0, -1.0)));
  float n  = luminance(sampleScreen(uv + texel * vec2( 0.0, -1.0)));
  float ne = luminance(sampleScreen(uv + texel * vec2( 1.0, -1.0)));
  float w  = luminance(sampleScreen(uv + texel * vec2(-1.0,  0.0)));
  float e  = luminance(sampleScreen(uv + texel * vec2( 1.0,  0.0)));
  float sw = luminance(sampleScreen(uv + texel * vec2(-1.0,  1.0)));
  float s  = luminance(sampleScreen(uv + texel * vec2( 0.0,  1.0)));
  float se = luminance(sampleScreen(uv + texel * vec2( 1.0,  1.0)));

  vec2 sobel = vec2(-nw - 2.0 * w - sw + ne + 2.0 * e + se,
                   -nw - 2.0 * n - ne + sw + 2.0 * s + se) * 0.25;
  float edge = smoothstep(0.025, 0.13, length(sobel));
  float low = min(luma, min(min(min(nw, n), min(ne, w)), min(min(e, sw), min(s, se))));
  float high = max(luma, max(max(max(nw, n), max(ne, w)), max(max(e, sw), max(s, se))));
  float span = high - low;
  float position = (luma - low) / max(span, 0.001);

  // Protect the light side AND its antialiased coverage, including dim labels.
  // A full two-sided Sobel mask turns small glyphs into black strokes.
  float detail = smoothstep(0.035, 0.12, span);
  float lightSide = smoothstep(0.02, 0.16, position) * detail;
  float readable = max(lightSide, smoothstep(0.40, 0.72, luma));

  // Flat UI has no normals or scene lighting to quantize. Add a directional
  // light field to its surfaces, then cut it into three hard cel-light bands.
  // This makes the shading visible even on a solid-color launcher background.
  float lightField = 1.0 - dot(uv, vec2(0.62, 0.38));
  float middle = smoothstep(0.34, 0.344, lightField);
  float lit = smoothstep(0.70, 0.704, lightField);
  float surfaceMask = (1.0 - smoothstep(0.30, 0.60, luma))
      * (1.0 - readable);
  float celLuma = floor(luma * 4.0 + 0.5) / 4.0;
  vec3 chroma = (source - vec3(luma)) * 1.20;
  vec3 comic = vec3(max(celLuma, 0.16)) + chroma;

  // Ochre highlights and cool charcoal shadows, with enough separation for
  // the ink to read. The palette still follows the configured accent color.
  vec3 shadowTint = mix(uBackground, vec3(0.10, 0.14, 0.19), 0.55);
  vec3 lightTint = mix(vec3(0.62, 0.52, 0.36), uAccent, 0.25);
  vec3 celSurface = mix(shadowTint, lightTint, 0.18 + middle * 0.20 + lit * 0.24);
  // Retain source panel/selection color differences inside each light band.
  celSurface += (source - uBackground) * 0.65;
  comic = mix(comic, celSurface, surfaceMask);

  // Clearly visible printed dots in midtones, cross-hatching in shadows.
  // Both patterns stay anchored to the UI and disappear over glyph coverage.
  float printMask = (1.0 - readable) * (1.0 - detail);
  vec2 cell = mod(pixel, 8.0) - 4.0;
  float radius = 1.15 + (1.0 - middle) * 0.60;
  float dotInk = 1.0 - smoothstep(radius - 0.40, radius + 0.40, length(cell));
  float diagonal = abs(fract((pixel.x + pixel.y) / 11.0) - 0.5) * 11.0;
  float crossDiagonal = abs(fract((pixel.x - pixel.y) / 11.0) - 0.5) * 11.0;
  float hatch = 1.0 - smoothstep(0.40, 1.20, diagonal);
  float crossHatch = 1.0 - smoothstep(0.40, 1.20, crossDiagonal);
  float printInk = dotInk * (0.26 - lit * 0.12)
      + hatch * (1.0 - lit) * 0.18 + crossHatch * (1.0 - middle) * 0.14;
  comic *= 1.0 - printInk * printMask;

  // Strong dark-side contours stand out against the lifted cel surfaces.
  float ink = edge * (1.0 - lightSide) * (1.0 - readable);
  comic = mix(comic, vec3(0.018, 0.021, 0.027), ink * 0.96);

  // Restore source coverage last: small labels never receive ink or dots.
  comic = mix(comic, source, readable);
  // Keep 70% of the processed look: 30% less cel-shading intensity.
  comic = mix(source, comic, 0.70);
  fragColor = vec4(clamp(comic, vec3(0.0), vec3(1.0)), 1.0);
}
