import common;

[shader("compute")]
[numthreads(64, 1, 1)]
void drawcmdMain(uint3 threadId: SV_DispatchThreadID) {
  uint objIndex = threadId.x;

  if (objIndex >= scene.totalObjects) {
    return;
  }

  // TODO: Add actual frustum culling using
  uint index_count = scene.meshes[objIndex].indexCount;
  uint drawIndex;
  // Atomically increment the count buffer via the SceneData pointer!
  InterlockedAdd(scene.drawCount[0], 1, drawIndex);

  // Write the draw command to the tightly packed slot
  scene.indirectCommands[drawIndex].vertexCount = index_count;
  scene.indirectCommands[drawIndex].instanceCount = 1;
  scene.indirectCommands[drawIndex].firstVertex = 0;
  scene.indirectCommands[drawIndex].firstInstance = objIndex;
}
