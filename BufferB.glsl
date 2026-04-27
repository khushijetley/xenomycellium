/*
 BUFFER B — Gray-Scott Reaction-Diffusion Environment
 Stores two chemicals: U (channel R) and V (channel G).
 U = nutrient (agents are attracted to high-U zones).
 V = reactant / "toxin" (agents tend to avoid high-V zones).
 The Gray-Scott equations drive the system toward self-organising coral / maze / 
 spot patterns that shift the navigable terrain over time.
 
 MOUSE INTERACTION (left-click only):
    LEFT-CLICK / DRAG → injects a nutrient burst (high U, low V) at the
                        cursor. Agents in BufferA sense this and swarm toward it,
                        growing new mycelial branches in that direction.

 iChannel0 = BufferB (self — previous frame state)
 
 References:
 Karl Sims Gray-Scott guide: https://www.karlsims.com/rd.html
 */

// Gray-Scott chemical parameters 
// These values produce a coral/maze pattern — good alien terrain aesthetics.
// Experiment: F=0.037, K=0.060 → spots; F=0.025, K=0.055 → large blobs.
#define FEED_RATE   0.0545    // rate at which U is continuously replenished
#define KILL_RATE   0.0620    // rate at which V is removed from the system
#define DIFF_U      0.2100    // diffusion coefficient for U (spreads quickly)
#define DIFF_V      0.1050    // diffusion coefficient for V (spreads half as fast)
#define DT          1.0       // time step size per frame

//  Mouse injection parameters 
#define MOUSE_RADIUS      35.0   // pixel radius of the nutrient injection zone
#define NUTRIENT_STRENGTH 0.95   // U value to drive toward at injection site

// Samples the RD buffer at fragCoord + offset with toroidal wrapping.
// offset: pixel-space offset from current fragment.
// Returns vec2(U, V) at that location.
vec2 sampleRD(vec2 fragCoord, vec2 offset) {
    vec2 uv = (fragCoord + offset) / iResolution.xy;
    uv = fract(uv);   // wrap — world is toroidal so no edge artifacts
    return texture(iChannel0, uv).rg;
}

// Soft circular falloff centred at center with given radius.
float softCircle(vec2 pos, vec2 center, float radius) {
    float d = length(pos - center);
    return 1.0 - smoothstep(radius * 0.4, radius, d);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {

    // Initialise on frame 0
    // Fill with U=1 (nutrient everywhere), V=0 (no reaction yet),
    // then seed a small central blob of V to kick off the Gray-Scott reaction.
    if (iFrame == 0) {
        vec2  center = iResolution.xy * 0.5;
        float dist   = length(fragCoord - center);

        float u = 1.0;
        float v = 0.0;

        // Central seed blob — without this nothing ever reacts
        if (dist < iResolution.x * 0.04) {
            v = 0.9;
            u = 0.5;
        }

        // Scatter a few extra random nucleation points for richer pattern variety
        vec2  p     = fragCoord / iResolution.xy;
        float seed1 = step(0.998, fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5));
        if (seed1 > 0.5) { v = 0.8; u = 0.4; }

        fragColor = vec4(u, v, 0.0, 1.0);
        return;
    }

    // Read current chemical values for this cell 
    vec2  uv_self = sampleRD(fragCoord, vec2(0.0));
    float U       = uv_self.r;
    float V       = uv_self.g;

    // Discrete Laplacian (5-point stencil) 
    // Laplacian(f) ≈ f(N) + f(S) + f(E) + f(W) - 4*f(centre)
    vec2 lap = -4.0 * uv_self
             + sampleRD(fragCoord, vec2( 1.0,  0.0))
             + sampleRD(fragCoord, vec2(-1.0,  0.0))
             + sampleRD(fragCoord, vec2( 0.0,  1.0))
             + sampleRD(fragCoord, vec2( 0.0, -1.0));

    // Gray-Scott reaction-diffusion equations 
    // dU/dt = Du·∇²U  -  U·V²  +  F·(1 - U)
    // dV/dt = Dv·∇²V  +  U·V²  -  (F + K)·V
    // The U·V² term is autocatalytic: V eats U to produce more V.
    float reaction = U * V * V;

    float dU = DIFF_U * lap.r  -  reaction  +  FEED_RATE * (1.0 - U);
    float dV = DIFF_V * lap.g  +  reaction  -  (FEED_RATE + KILL_RATE) * V;

    // Euler-integrate one step, clamp to physically valid range [0, 1]
    float newU = clamp(U + dU * DT, 0.0, 1.0);
    float newV = clamp(V + dV * DT, 0.0, 1.0);

    // Left-click mouse injection 
    if (iMouse.z > 0.0) {
        float influence = softCircle(fragCoord, iMouse.xy, MOUSE_RADIUS);
        if (influence > 0.0) {
            // Push U toward NUTRIENT_STRENGTH and V toward 0 in the injection zone
            newU = mix(newU, NUTRIENT_STRENGTH, influence * 0.85);
            newV = mix(newV, 0.0,               influence * 0.70);
        }
    }

    fragColor = vec4(newU, newV, 0.0, 1.0);
}
