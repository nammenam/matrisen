import common;

// ==========================================
// TERRAIN COMPUTE SHADER
// ==========================================

// --- Value Noise Helpers ---



uint pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float hash(float2 p) {
    uint2 q = uint2(int2(p));
    uint n = pcg(q.x ^ pcg(q.y));
    return float(n) * (1.0 / 4294967296.0);
}

float hashAlt(float2 p) {
    uint2 q = uint2(int2(p));
    q = q * uint2(1597334673u, 3812015801u);
    uint n = (q.x ^ q.y) * 1597334673u;
    return float(n) * (1.0 / 4294967296.0);
}

float valueNoise(float2 p) {
  float2 i = floor(p);
  float2 f = frac(p);

  // Smoothstep interpolation
  float2 u = f * f * (3.0 - 2.0 * f);

  float a = hash(i + float2(0, 0));
  float b = hash(i + float2(1, 0));
  float c = hash(i + float2(0, 1));
  float d = hash(i + float2(1, 1));

  return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float fbm(float2 p) {
  float height = 0.0;
  float amplitude = 0.5;
  float frequency = 1.0;
  float total_amplitude = 0.0;

  // 4 octaves of value noise
  for (int i = 0; i < 4; i++) {
    height += valueNoise(p * frequency) * amplitude;
    total_amplitude += amplitude;
    amplitude *= 0.5;
    frequency *= 2.1; // slightly irrational to avoid grid artifacts
  }

  return height / total_amplitude;
}

// Returns the world-space height at a given grid coordinate.
// Pull this out so both the vertex writer and normal calculator use
// the exact same function — no subtle mismatch between them.
float terrainHeight(uint x, uint y, uint gridSize, float worldScale,
                    float heightScale) {
  float2 uv = float2(x, y) / float2(gridSize - 1, gridSize - 1);
  return fbm(uv * 4.0) * heightScale; // 4.0 = zoom factor, tune to taste
}

[shader("compute")]
[numthreads(16, 16, 1)]
void terain(uint3 threadId: SV_DispatchThreadID) {
  const uint GRID_SIZE = 256;
  const float WORLD_SCALE = 1.0;
  const float HEIGHT_SCALE = 128.0;

  uint x = threadId.x;
  uint y = threadId.y;

  if (x >= GRID_SIZE || y >= GRID_SIZE)
    return;

  // ---- Write vertex ----
  uint vertIndex = y * GRID_SIZE + x;

  float wx = (float)x * WORLD_SCALE;
  float wy = (float)y * WORLD_SCALE;
  float wz = terrainHeight(x, y, GRID_SIZE, WORLD_SCALE, HEIGHT_SCALE);

  uint xl = x > 0 ? x - 1 : x;
  uint xr = x < GRID_SIZE - 1 ? x + 1 : x;
  uint yl = y > 0 ? y - 1 : y;
  uint yr = y < GRID_SIZE - 1 ? y + 1 : y;

  float hL = terrainHeight(xl, y, GRID_SIZE, WORLD_SCALE, HEIGHT_SCALE);
  float hR = terrainHeight(xr, y, GRID_SIZE, WORLD_SCALE, HEIGHT_SCALE);
  float hD = terrainHeight(x, yl, GRID_SIZE, WORLD_SCALE, HEIGHT_SCALE);
  float hU = terrainHeight(x, yr, GRID_SIZE, WORLD_SCALE, HEIGHT_SCALE);

  float stepX = (float)(xr - xl) * WORLD_SCALE;
  float stepZ = (float)(yr - yl) * WORLD_SCALE;

  float3 normal =
      normalize(float3(-(hR - hL) / stepX, -(hU - hD) / stepZ, 1.0));

  float2 uv = float2(x, y) / float2(GRID_SIZE - 1, GRID_SIZE - 1);

  float t = saturate(wz / HEIGHT_SCALE);
  float3 col;
  // col = lerp(float3(0.10, 0.10, 0.10), float3(0.95, 0.95, 0.90), t);
  col = (normal + 1.0) * 0.5;

  Vertex v;
  v.position = float3(wx, wy, wz);
  v.normal = normal;
  v.uv_x = uv.x;
  v.uv_y = uv.y;
  v.color = float4(col, 1.0);

  scene.meshes[0].vertexBuffer[vertIndex] = v;

  // ---- Write indices (only threads that own a valid quad) ----
  if (x < GRID_SIZE - 1 && y < GRID_SIZE - 1) {
    uint tl = y * GRID_SIZE + x;
    uint tr = tl + 1;
    uint bl = tl + GRID_SIZE;
    uint br = bl + 1;

    uint base = (y * (GRID_SIZE - 1) + x) * 6;
    scene.meshes[0].indexBuffer[base + 0] = tl;
    scene.meshes[0].indexBuffer[base + 1] = bl;
    scene.meshes[0].indexBuffer[base + 2] = tr;
    scene.meshes[0].indexBuffer[base + 3] = tr;
    scene.meshes[0].indexBuffer[base + 4] = bl;
    scene.meshes[0].indexBuffer[base + 5] = br;
  }
}
