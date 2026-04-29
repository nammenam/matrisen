import common;

// ==========================================
// TERRAIN COMPUTE SHADER
// ==========================================

// --- Value Noise Helpers ---

float hash(float2 p) {
  p = frac(p * float2(127.1, 311.7));
  p += dot(p, p + 19.19);
  return frac(p.x * p.y);
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
  float amplitude = 1.0;
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
  if (t < 0.3)
    col = lerp(float3(0.42, 0.32, 0.18), float3(0.25, 0.55, 0.20), t / 0.3);
  else if (t < 0.75)
    col = lerp(float3(0.25, 0.55, 0.20), float3(0.55, 0.55, 0.55),
               (t - 0.3) / 0.45);
  else
    col = lerp(float3(0.55, 0.55, 0.55), float3(1.0, 1.0, 1.0),
               (t - 0.75) / 0.25);

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
