#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict image2D image;

layout(set = 1, binding = 0, std430) restrict buffer InputBuffer {
  vec2 points[];
}
points_buffer;

layout(set = 2, binding = 0, std430) restrict buffer BorderPixels {
  vec4 pixels[];
}
border_pixels;

layout(set = 3, binding = 0, std430) restrict buffer TriangleBuffer {
  int triangleCount;
  int triangleSites[];
}
triangle_buffer; 

layout(push_constant, std430) uniform Params {
  int phase;
  int iteration;
} params;

#include "gpu-dt_shared.glsl"

void postprocessInit() {
  ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
  ivec2 dims = imageSize(image);
  if (!inBounds(pos, dims)) return;

  vec4 px = imageLoad(image, pos);
  PixelData pixelData = decodePixel(px);

  // Collect border pixels in clockwise order
  int rightOffset = dims.x;
  int bottomOffset = rightOffset + (dims.y - 2);
  int leftOffset = bottomOffset + (dims.x - 1);
  if (pos.y == 0) {
    border_pixels.pixels[pos.x] = px;
  } else if (pos.x == dims.x - 1 && pos.y < dims.y - 1) {
    border_pixels.pixels[rightOffset + (pos.y - 1)] = px;
  } else if (pos.y == dims.y - 1) {
    border_pixels.pixels[bottomOffset + (dims.x - 1 - pos.x)] = px;
  } else if (pos.x == 0 && pos.y > 0) {
    border_pixels.pixels[leftOffset + (dims.y - 1 - pos.y)] = px;
  }

  if (pixelData.type != PIXEL_VORONOI_VERTEX) return;

  // Count voronoi vertices
  int neighbors[] = getVoronoiVertexNeighbors(pos);
  int distinctCount = countUniquePositions(neighbors);
  int trianglesToAdd = 1;
  if (distinctCount == 4) trianglesToAdd = 2;

  int idx = atomicAdd(triangle_buffer.triangleCount, trianglesToAdd);
  px = encodePixel(pixelData.siteIndex, idx, PIXEL_VORONOI_VERTEX, encodeColor(0, 0, 255));
  imageStore(image, pos, px);
}

void generateTrianglesPhase() {
  ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
  ivec2 dims = imageSize(image);
  if (!inBounds(pos, dims)) return;

  PixelData pixelData = decodePixel(imageLoad(image, pos));
  if (pixelData.type != PIXEL_VORONOI_VERTEX) return;

  int neighbors[] = getVoronoiVertexNeighbors(pos);

  ivec3 sites = ivec3(-1, -1, -1);

  if (neighbors[3] == neighbors[2]) {
    sites = ivec3(neighbors[1], neighbors[2], neighbors[0]);
  }
  if (neighbors[2] == neighbors[0]) {
    sites = ivec3(neighbors[3], neighbors[0], neighbors[1]);
  }
  if (neighbors[0] == neighbors[1]) {
    sites = ivec3(neighbors[2], neighbors[1], neighbors[3]);
  }
  if (neighbors[1] == neighbors[3]) {
    sites = ivec3(neighbors[0], neighbors[3], neighbors[2]);
  }

  int idx = pixelData.triangleIndex * 3;
  if (sites != ivec3(-1, -1, -1)) {
    triangle_buffer.triangleSites[idx] = sites.x;
    triangle_buffer.triangleSites[idx + 1] = sites.y;
    triangle_buffer.triangleSites[idx + 2] = sites.z;
  } else {
    triangle_buffer.triangleSites[idx] = neighbors[2];
    triangle_buffer.triangleSites[idx + 1] = neighbors[1];
    triangle_buffer.triangleSites[idx + 2] = neighbors[3];
    triangle_buffer.triangleSites[idx + 3] = neighbors[0];
    triangle_buffer.triangleSites[idx + 4] = neighbors[1];
    triangle_buffer.triangleSites[idx + 5] = neighbors[2];
  }
}

void main() {
  switch(params.phase) {
    case 0:
      postprocessInit();
      break;
    case 1:
      generateTrianglesPhase();
      break;
  }
}
