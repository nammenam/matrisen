import common;

[shader("compute")]
[numthreads(64, 1, 1)]
void drawcmdMain(uint3 threadId: SV_DispatchThreadID) {
  uint objIndex = threadId.x;

  if (objIndex >= scene.meshCount) {
    return;
  }

  Mesh *mesh_addr = scene.addresses.meshes[objIndex].meshBuffer;
  uint index_count = mesh_addr.indexCount;
  if (index_count == 0) {
    return;
  }
  uint drawIndex;
  InterlockedAdd(*scene.addresses.drawcount, 1, drawIndex);
  // --- CONDITIONAL COMPILE BLOCK ---
#if USE_MESH_SHADING
  scene.addresses.drawMap[drawIndex] = objIndex;

  uint totalTriangles = index_count / 3;
  uint groupCountX = (totalTriangles + 31) / 32;

  scene.addresses.indirectCommands[drawIndex].groupCountX = groupCountX;
  scene.addresses.indirectCommands[drawIndex].groupCountY = 1;
  scene.addresses.indirectCommands[drawIndex].groupCountZ = 1;
#else
  // Classic Vertex Pipeline Indirect Command
  scene.addresses.indirectCommands[drawIndex].vertexCount = index_count;
  scene.addresses.indirectCommands[drawIndex].instanceCount = 1;
  scene.addresses.indirectCommands[drawIndex].firstVertex = 0;
  scene.addresses.indirectCommands[drawIndex].firstInstance = objIndex;
#endif
  // ---------------------------------
}
