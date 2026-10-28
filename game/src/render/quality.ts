/**
 * Graphics presets. LOW is tuned for the target laptop (Ryzen 5 7520U / Radeon 610M, 720p, 30 FPS goal);
 * it keeps the crimson identity (emissive eyes, materials, reflections) and trims cost elsewhere.
 * Values are starting points to be tuned from benchmark results, not verified guarantees.
 */
export type Quality = 'low' | 'medium' | 'high' | 'ultra';

export interface Preset {
  /** internal render height in pixels (window is upscaled); 0 = native */
  renderHeight: number;
  maxPixelRatio: number;
  shadows: boolean;
  shadowMap: number;
  /** half-size of the moon's shadow frustum (m) */
  shadowRange: number;
  softShadows: boolean;
  /** camera far plane / fog density */
  drawDistance: number;
  fogDensity: number;
  /** street-light pool size (constant per preset so shaders never recompile mid-game) */
  dynamicLights: number;
  envIntensity: number;
  bloom: boolean;
  rain: number;
  anisotropy: number;
  /** multiplies LOD switch distances (lower = earlier switch to cheaper meshes) */
  lodScale: number;
  /** cheapest hero LOD allowed up close: LOW uses the CR-X9 laptop LOD (LOD1) even in third person */
  heroMinLod: number;
  /** MSAA can only change on reload */
  antialias: boolean;
}

export const PRESETS: Record<Quality, Preset> = {
  low: {
    renderHeight: 720, maxPixelRatio: 1, shadows: true, shadowMap: 1024, shadowRange: 16, softShadows: false,
    drawDistance: 220, fogDensity: 0.016, dynamicLights: 3, envIntensity: 0.8, bloom: false, rain: 0.3,
    anisotropy: 2, lodScale: 0.6, heroMinLod: 1, antialias: false,
  },
  medium: {
    renderHeight: 900, maxPixelRatio: 1, shadows: true, shadowMap: 1536, shadowRange: 26, softShadows: true,
    drawDistance: 350, fogDensity: 0.013, dynamicLights: 6, envIntensity: 1, bloom: false, rain: 0.6,
    anisotropy: 4, lodScale: 0.85, heroMinLod: 0, antialias: true,
  },
  high: {
    renderHeight: 0, maxPixelRatio: 1.25, shadows: true, shadowMap: 2048, shadowRange: 34, softShadows: true,
    drawDistance: 600, fogDensity: 0.011, dynamicLights: 10, envIntensity: 1.2, bloom: true, rain: 1,
    anisotropy: 8, lodScale: 1, heroMinLod: 0, antialias: true,
  },
  ultra: {
    renderHeight: 0, maxPixelRatio: 2, shadows: true, shadowMap: 4096, shadowRange: 45, softShadows: true,
    drawDistance: 900, fogDensity: 0.009, dynamicLights: 12, envIntensity: 1.3, bloom: true, rain: 1,
    anisotropy: 16, lodScale: 1.4, heroMinLod: 0, antialias: true,
  },
};

export const QUALITY_ORDER: Quality[] = ['low', 'medium', 'high', 'ultra'];

/** Integrated / low-power GPUs default to LOW; everything else to HIGH. */
export function detectDefaultQuality(gl: WebGLRenderingContext | WebGL2RenderingContext): { quality: Quality; gpu: string } {
  let gpu = 'unknown';
  try {
    const ext = gl.getExtension('WEBGL_debug_renderer_info');
    gpu = String(ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER));
  } catch {
    /* privacy-restricted browsers */
  }
  const integrated = /610M|Radeon\(TM\) Graphics|Radeon Graphics|Vega \d|Intel|UHD|Iris|Mali|Adreno|Apple GPU|SwiftShader|llvmpipe/i.test(gpu);
  return { quality: integrated ? 'low' : 'high', gpu };
}
