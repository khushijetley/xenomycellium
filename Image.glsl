/*
IMAGE — Final Composite Render
 Composites all simulation layers into the final bioluminescent alien aesthetic.

 Render layers (back to front):
   1. Background  — dead planet surface, faintly textured by the nutrient field
   2. Toxic glow  — Gray-Scott V zones rendered as a dim amber haze
   3. Mycelium    — pheromone trails rendered as bioluminescent cyan/green
   4. Bloom       — radial glow pass gives an HDR light-spill feel
   5. Chromatic aberration — for an alien-optics look
   6. Vignette + film grain — depth, atmosphere, organic texture
   7. Zoom        — spacebar magnifies toward the mouse position
   8. Minimap HUD — bottom-right overview shown only when zoomed
   9. Cursor ring — single pulsing ring; green when clicking, white when idle

 iChannel0 = BufferB  (Gray-Scott U, V)
 iChannel1 = BufferC  (pheromone trail map)
 iChannel2 = Keyboard (Misc → Keyboard in Shadertoy channel picker)

INTERACTIONS:
   LEFT-CLICK / drag → inject nutrient at cursor; agents swarm to that point.
                       Cursor ring turns bright GREEN while held.
   SPACE (hold)      → zoom 3.5× into the mouse position (or screen centre).
                       Minimap appears bottom-right; crosshair marks focus.
                       Release space to zoom back out.
 */

// Colour palette 
#define COL_BG        vec3(0.01, 0.015, 0.025)   
#define COL_MYCEL_LO  vec3(0.00, 0.35,  0.25)    
#define COL_MYCEL_HI  vec3(0.15, 1.00,  0.65)    
#define COL_TOXIC_HI  vec3(0.45, 0.18,  0.00)    
#define COL_CORE      vec3(0.85, 1.00,  0.95)    

// Bloom 
#define BLOOM_SAMPLES   12
#define BLOOM_RADIUS    6.0
#define BLOOM_STRENGTH  1.4

// Zoom 
#define ZOOM_FACTOR  3.5    // magnification when spacebar is held

// Cursor 
#define CURSOR_RADIUS   35.0   // must match MOUSE_RADIUS in BufferB

// Returns pheromone trail value at uv 
float getTrail(vec2 uv) {
    return texture(iChannel1, uv).r;
}

// Returns Gray-Scott toxin (V channel) at uv 
float getToxin(vec2 uv) {
    return texture(iChannel0, uv).g;
}

// Returns Gray-Scott nutrient (U channel) at uv 
float getNutrient(vec2 uv) {
    return texture(iChannel0, uv).r;
}

// Returns 1.0 if the given key is currently held, else 0.0.
float keyDown(int keycode) {
    return texelFetch(iChannel2, ivec2(keycode, 0), 0).r;
}

// Per-pixel animated noise to break up colour banding and add organic texture.
// uv: screen UV. seed: animated value for per-frame variation.
float screenNoise(vec2 uv, float seed) {
    return fract(sin(dot(uv * iResolution.xy + seed,
                         vec2(12.9898, 78.233))) * 43758.5453);
}

// Radial bloom: samples trail values in a ring around uv to simulate
// uv: centre UV. radius: ring size in pixels. samples: angular tap count.
float radialBloom(vec2 uv, float radius, int samples) {
    float acc        = 0.0;
    float step_angle = 6.2831853 / float(samples);
    for (int i = 0; i < samples; i++) {
        float a      = float(i) * step_angle;
        vec2  offset = vec2(cos(a), sin(a)) * (radius / iResolution.xy);
        acc += getTrail(uv + offset);
    }
    return acc / float(samples);
}

// Applies a zoom transform to a screen UV.
// uv: original [0,1] screen UV. focus: pixel-space zoom point.
// zoomLevel: values >1.0 magnify the area around focus.
vec2 applyZoom(vec2 uv, vec2 focus, float zoomLevel) {
    vec2 focusUV = focus / iResolution.xy;
    // Pull the UV toward the focus point proportionally to zoom
    return focusUV + (uv - focusUV) / zoomLevel;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;   // normalised screen UV [0, 1]

    // SPACEBAR ZOOM
    float spaceHeld = keyDown(32);   // 1.0 when held, 0.0 when released

    // Active zoom level: ZOOM_FACTOR while space is down, 1.0 (no zoom) otherwise
    float zoomLevel = mix(1.0, ZOOM_FACTOR, spaceHeld);

    // Zoom toward mouse if it is on screen, otherwise centre of screen
    vec2 zoomFocus = (iMouse.x > 1.0) ? iMouse.xy : iResolution.xy * 0.5;
    vec2 rawSimUV = applyZoom(uv, zoomFocus, zoomLevel);
    vec2 simUV    = clamp(rawSimUV, 0.001, 0.999);   

    // READ SIMULATION DATA THROUGH ZOOMED UV
    float trail    = getTrail(simUV);
    float toxin    = getToxin(simUV);
    float nutrient = getNutrient(simUV);

    // Two normalised trail thresholds for colour mapping
    float t_norm = clamp(trail / 8.0, 0.0, 1.0);   
    float t_core = clamp(trail / 3.0, 0.0, 1.0);   

    // BACKGROUND — dead planet surface
    // Faint nutrient topology gives the impression of underground terrain
    float terrain = nutrient * 0.06;
    vec3  bg      = COL_BG + vec3(terrain * 0.8, terrain * 0.5, terrain * 0.2);

    // TOXIC ZONE GLOW
    // High-V regions glow amber — hostile, inhospitable areas of the world
    vec3 toxic_layer = mix(vec3(0.0), COL_TOXIC_HI, pow(toxin, 1.5) * 0.35);

    // MYCELIUM TRAILS
    // Dim teal → vivid cyan-green → near-white at the densest cores
    vec3  mycel_color = mix(COL_MYCEL_LO, COL_MYCEL_HI, t_norm);
    mycel_color       = mix(mycel_color,  COL_CORE,      t_core * t_core);
    float mycel_alpha = pow(t_norm, 0.55);

    // BLOOM
    // Scale bloom radius down when zoomed 
    float bloom_val = radialBloom(simUV, BLOOM_RADIUS / zoomLevel, BLOOM_SAMPLES);
    vec3  bloom_col = mix(COL_MYCEL_LO, COL_MYCEL_HI, bloom_val / 8.0) * BLOOM_STRENGTH;

    // CHROMATIC ABERRATION
    float ca      = 0.0015 / zoomLevel;
    float trail_r = getTrail(simUV + vec2( ca, 0.0));
    float trail_b = getTrail(simUV + vec2(-ca, 0.0));
    mycel_color.r = mix(mycel_color.r, COL_MYCEL_HI.r * trail_r / 8.0, 0.4);
    mycel_color.b = mix(mycel_color.b, COL_MYCEL_HI.b * trail_b / 8.0, 0.4);

    // COMPOSITE ALL LAYERS
    vec3 color = bg;
    color += toxic_layer;
    color  = mix(color, mycel_color, mycel_alpha * 0.95);
    color += bloom_col * 0.18;

    // VIGNETTE 
    vec2  vig_uv  = uv * (1.0 - uv.yx);
    float vignette = clamp(pow(vig_uv.x * vig_uv.y * 18.0, 0.35), 0.0, 1.0);
    color *= mix(0.25, 1.0, vignette);

    // FILM GRAIN
    color += screenNoise(uv, iTime) * 0.035 - 0.017;

    // DARK BORDER for pixels outside simulation bounds when zoomed
    float oob = step(0.001, max(
        max(-rawSimUV.x, rawSimUV.x - 0.999),
        max(-rawSimUV.y, rawSimUV.y - 0.999)
    ));
    color *= 1.0 - oob * 0.92;

    // MINIMAP HUD — only visible when spacebar is held
    if (spaceHeld > 0.5) {
        vec2 mmOrigin = vec2(0.865, 0.04);   // bottom-right anchor (UV)
        vec2 mmSize   = vec2(0.115, 0.115 * (iResolution.x / iResolution.y));

        vec2 inMM = step(mmOrigin, uv) * step(uv, mmOrigin + mmSize);
        if (inMM.x * inMM.y > 0.5) {
            // Remap UV to local minimap coordinates [0,1]
            vec2  mmUV     = (uv - mmOrigin) / mmSize;
            float mm_trail = getTrail(mmUV);
            float mm_norm  = clamp(mm_trail / 8.0, 0.0, 1.0);

            color = mix(COL_BG * 0.4,
                        mix(COL_MYCEL_LO, COL_MYCEL_HI, mm_norm) * 0.65,
                        mm_norm);

            // Viewport rectangle: the region currently displayed at full size
            vec2  vpCenter  = zoomFocus / iResolution.xy;
            vec2  vpHalf    = vec2(0.5) / zoomLevel;
            vec2  vpMin     = vpCenter - vpHalf;
            vec2  vpMax     = vpCenter + vpHalf;

            // Faint tint inside the viewport box
            vec2  inVP = step(vpMin, mmUV) * step(mmUV, vpMax);
            color += vec3(0.05, 0.5, 0.25) * inVP.x * inVP.y * 0.20;

            // Bright border around the viewport box
            float edgeDist = min(
                min(abs(mmUV.x - vpMin.x), abs(mmUV.x - vpMax.x)),
                min(abs(mmUV.y - vpMin.y), abs(mmUV.y - vpMax.y))
            );
            color += vec3(0.1, 1.0, 0.5) * smoothstep(0.025, 0.0, edgeDist) * 0.7;
        }

        // Thin border line around the whole minimap box
        vec2  bd     = abs(uv - (mmOrigin + mmSize * 0.5)) - mmSize * 0.5;
        float border = smoothstep(0.003, 0.0, max(bd.x, bd.y) + 0.002)
                     - smoothstep(0.0, -0.0015, max(bd.x, bd.y));
        color += vec3(0.1, 0.75, 0.45) * border * 0.55;

        // Thin green bar across the top-left of the screen — "zoom active" indicator
        float bar = smoothstep(0.0025, 0.0, abs(uv.y - 0.976))
                  * step(uv.x, 0.14) * step(0.01, uv.x);
        color += vec3(0.05, 1.0, 0.45) * bar * 0.55;
    }

    // TONE MAP + GAMMA CORRECTION
    color = color / (color + 0.7);                    
    color = pow(max(color, 0.0), vec3(1.0 / 2.1));   

    // CURSOR OVERLAY
    if (iMouse.x > 1.0) {
        float dtm = length(fragCoord - iMouse.xy);

        // Primary ring: gently pulses to feel alive and biological
        float pulse = 0.87 + 0.13 * sin(iTime * 5.5);
        float ring  = smoothstep(1.8, 0.0, abs(dtm - CURSOR_RADIUS * pulse));

        // Secondary outer ring: expands into view only while the button is held,
        float ring2  = smoothstep(2.5, 0.0, abs(dtm - CURSOR_RADIUS * 1.4));
        ring2       *= step(0.5, iMouse.z);   // only show when left button is down

        // Small bright dot at the exact cursor centre for precision
        float dot_c = smoothstep(2.5, 0.0, dtm);

        // Cursor is GREEN when actively injecting, cool white when just hovering
        vec3 cur_col = (iMouse.z > 0.5)
            ? vec3(0.05, 1.00, 0.45)   
            : vec3(0.35, 0.40, 0.50);  

        // Additive blend
        color += cur_col * ring  * 0.80;
        color += cur_col * ring2 * 0.32;
        color += cur_col * dot_c * 0.90;

        // Crosshair around the focus point to aid precision
        if (spaceHeld > 0.5) {
            float rh = smoothstep(1.5, 0.0, abs(fragCoord.y - iMouse.y))
                     * step(abs(fragCoord.x - iMouse.x), CURSOR_RADIUS * 1.9)
                     * (1.0 - step(abs(fragCoord.x - iMouse.x), CURSOR_RADIUS * 0.35));
            float rv = smoothstep(1.5, 0.0, abs(fragCoord.x - iMouse.x))
                     * step(abs(fragCoord.y - iMouse.y), CURSOR_RADIUS * 1.9)
                     * (1.0 - step(abs(fragCoord.y - iMouse.y), CURSOR_RADIUS * 0.35));
            color += vec3(0.1, 0.9, 0.5) * (rh + rv) * 0.28;
        }
    }

    fragColor = vec4(color, 1.0);
}
