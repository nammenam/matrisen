import common;

[shader("compute")]
[numthreads(64, 1, 1)]
void drawcmdMain(uint3 threadId: SV_DispatchThreadID) {
  uint objIndex = threadId.x;

  if (objIndex >= scene.meshCount) {
    return;
  }

  Mesh *mesh_addr = scene.meshes[objIndex].meshBuffer;
  uint index_count = mesh_addr.indexCount;
  if (index_count == 0) {
    return;
  }

  // TODO: Add actual frustum culling here
  uint drawIndex;
  InterlockedAdd(scene.counters.drawCount, 1, drawIndex);
  // --- CONDITIONAL COMPILE BLOCK ---
#if USE_MESH_SHADING
  scene.drawMap[drawIndex] = objIndex;

  uint totalTriangles = index_count / 3;
  uint groupCountX = (totalTriangles + 31) / 32;

  scene.indirectCommands[drawIndex].groupCountX = groupCountX;
  scene.indirectCommands[drawIndex].groupCountY = 1;
  scene.indirectCommands[drawIndex].groupCountZ = 1;
#else
  // Classic Vertex Pipeline Indirect Command
  scene.indirectCommands[drawIndex].vertexCount = index_count;
  scene.indirectCommands[drawIndex].instanceCount = 1;
  scene.indirectCommands[drawIndex].firstVertex = 0;
  scene.indirectCommands[drawIndex].firstInstance = objIndex;
#endif
  // ---------------------------------
}
