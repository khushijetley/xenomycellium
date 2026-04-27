/*
Title: Xenomycelium: Alien Mycelium Colonizing a Dead World
 
INTERACTIONS:
    - LEFT-CLICK / DRAG  → injects a nutrient burst (high U, low V) at the
    cursor. Agents in BufferA sense this and swarm toward it,
    growing new mycelial branches in that direction.
      
    - Interesting parameters to tweak (in BufferA):
        SENSE_ANGLE     — wider angles create bushier, less directed networks
        SENSE_DIST      — longer sensing creates longer bridge arcs
        TURN_SPEED      — higher values cause tighter spirals
        DEPOSIT_AMOUNT  — more deposit = thicker, brighter trails
        
    - In BufferB:
        FEED_RATE / KILL_RATE — changes Gray-Scott pattern (try F=0.055, K=0.062)

DESCRIPTION:
    Xenomycelium is a coupled multi-agent system in which a population of Physarum-
    inspired agents colonizes a chemically dynamic environment governed by a Gray-
    Scott reaction-diffusion (RD) model. The agents follow a stigmergic communication 
    strategy adapted from Jones (2010): each agent deposits a chemical trail 
    (pheromone) into a shared texture, senses that trail at three forward-pointing 
    locations, and steers toward the highest combined score of trail density and local 
    nutrient availability. The RD environment continuously produces self-organizing 
    chemical patterns: spots, labyrinths, and coral-like structures, depending on the 
    feed and kill parameters (Pearson, 1993), which modulate the navigability of the 
    terrain. Agents perform chemotaxis by weighing their steering decisions against 
    the Gray-Scott U field, preferring high-nutrient zones and routing around low-U 
    regions. The result is an emergent bioluminescent network whose topology is jointly 
    determined by agent behaviour and the shifting chemical landscape beneath it.
 
    A significant technical challenge arose from coupling the two systems: because the 
    RD field and the pheromone trail map both evolve on the same spatial grid, early 
    implementations produced runaway positive feedback in which heavy pheromone deposits 
    artificially suppressed the Gray-Scott V reactant, collapsing the RD pattern into a 
    uniform equilibrium within a few hundred frames. This was resolved by strictly 
    decoupling the two fields into separate render buffers: Buffer B for the RD chemicals 
    and Buffer C for the trail map, and ensuring that agents read from both fields 
    independently without writing back to the RD buffer during the trail update step. 
    Pheromone information, therefore, informs agent steering without directly interfering 
    with the chemical dynamics, preserving the integrity of the Gray-Scott equations 
    while still allowing indirect interaction through agent position (Sims, n.d.). 
    Claude was used narrowly during development for debugging purposes only, specifically, 
    to identify a UV wrapping error in the toroidal Laplacian stencil that was producing 
    visible boundary artifacts along the edges of Buffer B. All system design, and creative 
    choices were made independently.
 
    Over longer simulation runs, the system exhibits several compelling emergent behaviours. 
    Initially, agents form thin exploratory tendrils radiating outward from the spawn ring; 
    these gradually reinforce into stable high-density highways as stigmergic feedback 
    amplifies frequently-travelled paths (Jones, 2010). As the RD terrain shifts, some 
    highways are undercut by expanding chemical zones, triggering rerouting events in which 
    the network partially dissolves and reconverges along new corridors, a dynamic reminiscent
    of the adaptive transport behaviour observed in biological Physarum polycephalum 
    (Tero et al., 2010). Future extensions could include agent specialization (scout vs. 
    worker populations with differentiated sensing parameters), a third signalling chemical to 
    simulate action-potential propagation along established hyphae, or a 3D raymarched volume 
    for full spatial immersion.

TECHNICAL REALIZATION:
    BufferA: Agent state. Each texel encodes one agent as (pos.x, pos.y, angle, alive). Agents 
             sense three directions by sampling BufferC (trails) and BufferB (RD nutrient field), 
             then steer toward the highest combined score each frame.
    BufferB: Gray-Scott RD. Two-chemical system (U, V) with discrete Laplacian diffusion on a
             toroidal grid. Produces self-organizing terrain patterns that shift continuously over 
             time.
    BufferC: Pheromone trail map. Agents deposit here; trails diffuse and evaporate each frame. 
             This is the shared stigmergic memory.
    Image:   Composites all layers with bloom, chromatic aberration, vignette, film grain, zoom 
             transform, minimap HUD, and bioluminescent colour grading.


REFERENCES:
    - Jones, J. (2010). Characteristics of pattern formation and evolution in approximations of 
      Physarum transport networks. Artificial Life, 16(2), 127–153. https://doi.org/10.1162/artl.
      2010.16.2.16202
    - Pearson, J. E. (1993). Complex patterns in a simple system. Science, 261(5118), 189–192. 
      https://doi.org/10.1126/science.261.5118.189
    - Sims, K. (n.d.). Reaction-diffusion tutorial. Karl Sims. https://www.karlsims.com/rd.html
    - Tero, A., Takagi, S., Saigusa, T., Ito, K., Bebber, D. P., Fricker, M. D., Yumiki, K., 
      Kobayashi, R., & Nakagaki, T. (2010). Rules for biologically inspired adaptive network design. 
      Science, 327(5964), 439–442. https://doi.org/10.1126/science.1177894


FUTURE EXTENSIONS:
    - Agent specialisation: scout vs. worker populations with different sensing radii, turn speeds, 
      and deposit amounts
    - Third signalling chemical to simulate action-potential propagation along established mycelial 
      highways
    - Adaptive spawn rate: more agents recruited when trail density is low

 */

// BUFFER A — Agent State
// Each texel = one agent: (pos.x, pos.y, angle, alive)
// Resolution determines agent count (width * height agents total)

// --- Tuneable parameters ---
#define NUM_AGENTS       (iResolution.x * iResolution.y)
#define SENSE_ANGLE      0.45       // radians: angle offset for side sensors
#define SENSE_DIST       9.0        // pixels: how far ahead agents sense
#define TURN_SPEED       0.4        // how sharply agents steer each frame
#define DEPOSIT_AMOUNT   4.0        // pheromone deposited per agent per frame
#define AGENT_SPEED      1.3        // pixels moved per frame
#define SPAWN_RADIUS     0.12       // fraction of screen width for initial spawn ring

// --- Hash / random utilities ---

// Returns a pseudo-random float in [0,1] from a 2D seed.
// Used to initialize agent positions and angles.
float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

// Returns a pseudo-random float in [0,1] from a scalar seed.
float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453);
}

// Returns pheromone strength at that location.
float sampleTrail(vec2 pos) {
    // Wrap position to toroidal space so agents don't get stuck at borders
    vec2 uv = mod(pos, iResolution.xy) / iResolution.xy;
    return texture(iChannel1, uv).r;  // iChannel1 = BufferC (trail map)
}

// Samples the Gray-Scott U field (BufferB channel R) at world position pos.
// Lower U = more "toxic" — agents prefer to avoid low-U regions.
float sampleToxicity(vec2 pos) {
    vec2 uv = mod(pos, iResolution.xy) / iResolution.xy;
    return texture(iChannel0, uv).r;  // iChannel0 = BufferB (RD field)
}

// Computes the combined attraction score at a given world position.
// Agents steer toward high pheromone AND high U (low toxicity).
// trail_weight blends trail following vs chemotaxis.
float senseScore(vec2 pos) {
    float trail    = sampleTrail(pos);
    float u_field  = sampleToxicity(pos);
    return trail * 2.5 + u_field * 0.6;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {

    // --- Initialization on first frame ---
    // On frame 0, assign each pixel a fresh agent with random position on a ring
    if (iFrame == 0) {
        // Use fragCoord as a unique seed per agent
        float seed = hash21(fragCoord + 0.5);
        float seed2 = hash21(fragCoord * 1.7 + 13.1);

        // Spawn agents in a ring around screen center for nice symmetric start
        float angle_spawn = seed * 6.2831853;   // full circle
        float radius      = iResolution.x * SPAWN_RADIUS * (0.7 + 0.3 * seed2);
        vec2  center      = iResolution.xy * 0.5;
        vec2  pos         = center + vec2(cos(angle_spawn), sin(angle_spawn)) * radius;

        // Agent faces inward (toward center) + small random jitter for symmetry breaking
        float facing = angle_spawn + 3.14159 + (seed - 0.5) * 0.8;

        // Pack agent state into RGBA: (pos.x, pos.y, angle, alive=1.0)
        fragColor = vec4(pos.x, pos.y, facing, 1.0);
        return;
    }

    // Each subsequent frame: update agent state
    // Read current agent state for this pixel
    vec4  agent  = texture(iChannel2, fragCoord / iResolution.xy); // iChannel2 = BufferA self
    vec2  pos    = agent.xy;
    float angle  = agent.z;
    float alive  = agent.w;

    // Dead agents stay dead (w=0 means inactive)
    if (alive < 0.5) {
        fragColor = agent;
        return;
    }

    // Sense three directions: left, center, right
    vec2 dir_center = vec2(cos(angle),                sin(angle));
    vec2 dir_left   = vec2(cos(angle + SENSE_ANGLE),  sin(angle + SENSE_ANGLE));
    vec2 dir_right  = vec2(cos(angle - SENSE_ANGLE),  sin(angle - SENSE_ANGLE));

    // Sample attraction score at each sensor position
    float score_center = senseScore(pos + dir_center * SENSE_DIST);
    float score_left   = senseScore(pos + dir_left   * SENSE_DIST);
    float score_right  = senseScore(pos + dir_right  * SENSE_DIST);

    // Steer based on sensor comparison
    // If center is best: keep going straight
    // If left is best: turn left
    // If right is best: turn right
    // If left==right: add tiny random jitter to break symmetry
    float jitter = (hash11(angle + float(iFrame) * 0.01 + pos.x * 0.001) - 0.5) * 0.15;

    if (score_center >= score_left && score_center >= score_right) {
        // Straight ahead wins — no steering, tiny jitter only
        angle += jitter;
    } else if (score_left > score_right) {
        // Turn left
        angle += TURN_SPEED + jitter;
    } else if (score_right > score_left) {
        // Turn right
        angle -= TURN_SPEED + jitter;
    } else {
        // Tie: random walk to avoid deadlock
        angle += (hash11(pos.x * 3.7 + float(iFrame)) - 0.5) * 1.2;
    }

    // Move agent forward 
    pos += vec2(cos(angle), sin(angle)) * AGENT_SPEED;

    // Toroidal wrapping: world is seamless like a torus 
    pos = mod(pos, iResolution.xy);

    // Output updated agent state
    fragColor = vec4(pos.x, pos.y, angle, 1.0);
}
