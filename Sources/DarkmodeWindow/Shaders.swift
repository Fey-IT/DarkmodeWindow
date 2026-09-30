import Foundation

/// Must match `Params` in the Metal source below (all 32-bit floats).
struct ShaderParams {
    var brightness: Float = 1.0
    /// OKLab lightness of the new background (≈ #161616, Material dark surface).
    var bgL: Float = 0.20
    /// OKLab lightness of former black text (≈ #DEDEDE, no pure white).
    var fgL: Float = 0.90
    /// < 1 lifts mid tones so colored text keeps enough contrast on the dark background.
    var curve: Float = 0.75
    /// Slight desaturation, saturated colors glare on dark backgrounds.
    var chromaScale: Float = 0.9
    var adaptive: Float = 1.0
    /// Mip levels of the paper mask: ~16 pt and ~32 pt neighborhoods.
    var lodSmall: Float = 4.0
    var lodLarge: Float = 6.0
    /// Mip level (~2 pt) used to erode the bright mask, so thin white strokes are not paper.
    var lodErode: Float = 2.0
    /// Mip level (~8 pt) of the frame used to detect colored surfaces (buttons, bars, photos).
    var lodColor: Float = 4.0
    /// Distance in pixels (~5 pt) at which a dark pixel must see light on opposite sides to count as ink.
    var inkOffset: Float = 10
}

/// Compiled at runtime (no Xcode / offline metal compiler available).
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };

struct Params {
    float brightness;
    float bgL;
    float fgL;
    float curve;
    float chromaScale;
    float adaptive;
    float lodSmall;
    float lodLarge;
    float lodErode;
    float lodColor;
    float inkOffset;
};

vertex VOut vmain(uint vid [[vertex_id]]) {
    const float2 p[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    VOut o;
    o.pos = float4(p[vid], 0, 1);
    o.uv = float2((p[vid].x + 1) * 0.5, 1 - (p[vid].y + 1) * 0.5);
    return o;
}

static float3 srgbToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

static float3 linearToSrgb(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

static float3 linearToOklab(float3 c) {
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    l = pow(max(l, 0.0), 1.0 / 3.0);
    m = pow(max(m, 0.0), 1.0 / 3.0);
    s = pow(max(s, 0.0), 1.0 / 3.0);
    return float3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                  1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                  0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

static float3 oklabToLinear(float3 c) {
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l; m = m * m * m; s = s * s * s;
    return float3( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

// Reduce chroma until the color fits into sRGB, keeping lightness and hue.
static float3 gamutFit(float3 lab) {
    float3 rgb = oklabToLinear(lab);
    for (int i = 0; i < 8; i++) {
        if (all(rgb >= -0.001) && all(rgb <= 1.001)) { break; }
        lab.yz *= 0.8;
        rgb = oklabToLinear(lab);
    }
    return rgb;
}

// Pass 1: marks bright pixels (near-white / light pastel).
fragment float fbright(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float L = linearToOklab(srgbToLinear(tex.sample(s, in.uv).rgb)).x;
    return smoothstep(0.82, 0.92, L);
}

// Pass 2: "paper" = bright pixels whose ~2 pt surrounding is bright too. White text or icons on
// colored buttons / dark UI are too thin to count. Mipmapped afterwards, its coarse levels give
// the fraction of paper in a neighborhood.
fragment float fpaper(VOut in [[stage_in]], texture2d<float> bright [[texture(0)]],
                      constant Params& p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    return smoothstep(0.85, 0.97, bright.sample(s, in.uv, level(p.lodErode)).r);
}

// Light on two opposite sides at `offset` pixels along `axis` (1,0 = left+right, 0,1 = above+below).
static float opposingLight(texture2d<float> bright, sampler s, float2 uv, float2 axis, float offset, float lod) {
    float2 d = axis * offset / float2(bright.get_width(), bright.get_height());
    return min(bright.sample(s, uv - d, level(lod)).r, bright.sample(s, uv + d, level(lod)).r);
}

fragment float4 fmain(VOut in [[stage_in]],
                      texture2d<float> tex [[texture(0)]],
                      texture2d<float> mask [[texture(1)]],
                      texture2d<float> bright [[texture(2)]],
                      constant Params& p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float3 lab = linearToOklab(srgbToLinear(tex.sample(s, in.uv).rgb));

    // Hue-preserving lightness inversion: white -> dark gray, black -> light gray.
    float d = 1.0 - clamp(lab.x, 0.0, 1.0);
    float3 dark = float3(p.bgL + (p.fgL - p.bgL) * pow(d, p.curve), lab.yz * p.chromaScale);

    // Adaptive mode: the decision is made per region (~24 pt), never per pixel, so glyphs are
    // always converted as a whole and stay crisp. Regions with light "paper" are inverted; dark UI
    // and the interior of photos have none and stay as they are. Paper itself is always darkened.
    float t = 1.0;
    if (p.adaptive > 0.5) {
        float region = mask.sample(s, in.uv, level(p.lodLarge)).r;
        float paperSelf = mask.sample(s, in.uv, level(0.0)).r;
        // Dark pixels are only ink (to be lightened) if there is light on two opposite sides
        // (left+right or above+below) – true for text strokes, false for the edge of a wide dark
        // area next to a slide (e.g. the Meet/Teams background), which has light on one side only.
        // Text always has light above and below its line, and usually left and right of a stroke.
        // Several distances cover body text (dense) up to large bold headlines.
        float2 h = float2(1, 0), v = float2(0, 1);
        float o = p.inkOffset;  // ~5 pt in pixels
        float light = 0.0;
        for (int i = 1; i <= 3; i++) {
            light = max(light, opposingLight(bright, s, in.uv, h, o * 0.5 * float(i), p.lodErode - 0.5));
        }
        for (int i = 1; i <= 8; i++) {
            light = max(light, opposingLight(bright, s, in.uv, v, o * 0.5 * float(i), p.lodErode - 0.5));
        }
        float ink = smoothstep(0.10, 0.30, light);
        float gate = max(ink, smoothstep(0.30, 0.50, lab.x));
        t = max(smoothstep(0.02, 0.12, region) * gate, paperSelf);
    }

    float3 outLab = mix(lab, dark, t);
    outLab.x *= p.brightness;
    return float4(linearToSrgb(gamutFit(outLab)), 1.0);
}
"""
