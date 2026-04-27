/*
 BUFFER C — Pheromone Trail Map
 This is the "shared memory" through which agents communicate indirectly
 (stigmergy). Each frame:
   1. Evaporate existing trails (multiply by decay factor)
   2. Diffuse trails slightly (smooth/blur them)
   3. Each agent deposits pheromone at its current position

 The result is a dynamic map of where agents have been recently.
 Agents in BufferA read this to steer toward high-density paths.

 iChannel0 = BufferC (self, previous frame)
 iChannel1 = BufferA (agent state — read positions to deposit)
 */

// Trail dynamics parameters 
#define EVAPORATION    0.97      // fraction of trail remaining each frame (0.97 = slow fade)
#define DIFFUSION_W    0.15      // how much to blur trails laterally each frame
#define DEPOSIT        4.0       // pheromone added per agent occupying this cell
#define AGENT_RADIUS   1.5       // pixel radius within which an agent deposits to this cell

// Reads trail value from previous frame at an offset (toroidal).
float readTrail(vec2 fragCoord, vec2 offset) {
    vec2 uv = fract((fragCoord + offset) / iResolution.xy);
    return texture(iChannel0, uv).r;
}

// Reads agent state from BufferA.
// Returns vec4(pos.x, pos.y, angle, alive).
vec4 readAgent(vec2 agentCoord) {
    vec2 uv = agentCoord / iResolution.xy;
    return texture(iChannel1, uv);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {

    // Initialize: empty trail map on frame 0 
    if (iFrame == 0) {
        fragColor = vec4(0.0);
        return;
    }

    // Diffuse existing trail 
    // 3x3 box blur weighted by DIFFUSION_W for neighbors
    // Center gets weight (1 - 8*DIFFUSION_W/9), neighbors share DIFFUSION_W
    float trail = readTrail(fragCoord, vec2( 0.0,  0.0)) * (1.0 - DIFFUSION_W);
    trail += readTrail(fragCoord, vec2( 1.0,  0.0)) * (DIFFUSION_W / 8.0);
    trail += readTrail(fragCoord, vec2(-1.0,  0.0)) * (DIFFUSION_W / 8.0);
    trail += readTrail(fragCoord, vec2( 0.0,  1.0)) * (DIFFUSION_W / 8.0);
    trail += readTrail(fragCoord, vec2( 0.0, -1.0)) * (DIFFUSION_W / 8.0);
    trail += readTrail(fragCoord, vec2( 1.0,  1.0)) * (DIFFUSION_W / 8.0);
    trail += readTrail(fragCoord, vec2(-1.0,  1.0)) * (DIFFUSION_W / 8.0);
    trail += readTrail(fragCoord, vec2( 1.0, -1.0)) * (DIFFUSION_W / 8.0);
    trail += readTrail(fragCoord, vec2(-1.0, -1.0)) * (DIFFUSION_W / 8.0);

    // Evaporate 
    trail *= EVAPORATION;

    // Agent deposit 
    // This is O(k^2) per pixel where k = search radius in texels, kept small for perf.
    int search = 2;   // check a (2*search+1)^2 block of agent texels around fragCoord
    float deposit_here = 0.0;

    for (int dy = -search; dy <= search; dy++) {
        for (int dx = -search; dx <= search; dx++) {
            // The agent texel to check
            vec2 agentTexel = fragCoord + vec2(float(dx), float(dy));
            vec4 ag = readAgent(agentTexel);

            // Only living agents deposit (alive flag = ag.w)
            if (ag.w > 0.5) {
                // ag.xy is the agent's world position
                float dist = length(ag.xy - fragCoord);
                // Deposit if agent is within AGENT_RADIUS of this trail cell
                if (dist < AGENT_RADIUS) {
                    // Soft falloff: closer agent = more deposit
                    deposit_here += DEPOSIT * (1.0 - dist / AGENT_RADIUS);
                }
            }
        }
    }

    trail += deposit_here;

    // Clamp trail to a reasonable max to prevent saturation
    trail = min(trail, 12.0);

    fragColor = vec4(trail, 0.0, 0.0, 1.0);
}
