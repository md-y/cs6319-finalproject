#[compute]
#version 450


layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict image2D image;

layout(set = 1, binding = 0, std430) restrict buffer InputBuffer {
  vec2 points[];
}
points_buffer;

layout(push_constant, std430) uniform Params {
  int phase;
  int iteration;
} params;

#include "gpu-dt_shared.glsl"

void initPass() {
  ivec2 id = ivec2(gl_GlobalInvocationID.xy);
  int pointIdx = id.x * 16 + id.y;
  uint pointCount = points_buffer.points.length();
  if (pointIdx >= pointCount) return;

  vec2 point = points_buffer.points[pointIdx];
  ivec2 roundedPoint = ivec2(abs(round(point)));

  ivec2 dims = imageSize(image);
  if (!inBounds(roundedPoint, dims)) {
    return;
  }

  vec4 px = encodePixel(pointIdx, -1, PIXEL_VORONOI_FLOOD, encodeColor(255, 0, 0));
  imageStore(image, roundedPoint, px);
}

void jfaPass() {
  ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
  ivec2 dims = imageSize(image);
  if (!inBounds(pos, dims)) return;

  // We are doing 1+JFA, so start with 1 then do N/2, N/4, ..., 1
  int offset = 1;
  if (params.iteration > 0) {
    int N = max(dims.x, dims.y);
    float d = min(pow(2, params.iteration), N);
    offset = int(N / d);
  }

  float bestDistance = dims.x * dims.y;
  PixelData bestData = decodePixel(imageLoad(image, pos));

  // Pixel is a site
  if (bestData.src == pos) {
    return;
  }

  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      ivec2 otherPos = pos + ivec2(x, y) * offset;
      if (!inBounds(otherPos, dims)) continue;
      vec4 otherData = imageLoad(image, otherPos);
      PixelData pixelData = decodePixel(otherData);
      if (pixelData.type != PIXEL_EMPTY) {
        float dist = distance(pixelData.src, pos);
        if (dist < bestDistance) {
          bestDistance = dist;
          bestData = pixelData;
        }
      }
    }
  }

  int shade = int(bestData.siteIndex * 255 / points_buffer.points.length());
  vec4 px = encodePixel(bestData.siteIndex, bestData.triangleIndex, bestData.type, encodeColor(shade, shade, shade));
  imageStore(image, pos, px);
}

void removeIslandsPass() {
  ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
  ivec2 dims = imageSize(image);
  if (!inBounds(pos, dims)) return;

  vec4 px = imageLoad(image, pos);
  PixelData pixelData = decodePixel(px);
  ivec2 srcPos = pixelData.src;
  if (srcPos == pos) {
    return;
  }

  ivec2 xRange = ivec2(0, 0);
  ivec2 yRange = ivec2(0, 0);
  if (srcPos.x > pos.x) xRange.y = 1;
  else if (srcPos.x < pos.x) xRange.x = -1;
  if (srcPos.y > pos.y) yRange.y = 1;
  else if (srcPos.y < pos.y) yRange.x = -1;

  float bestDistance = dims.x * dims.y;
  vec4 bestData = px;

  for (int x = xRange.x; x <= xRange.y; x++) {
    for (int y = yRange.x; y <= yRange.y; y++) {
      if (x == 0 && y == 0) continue;

      ivec2 otherPos = pos + ivec2(x, y);
      vec4 otherData = imageLoad(image, otherPos);
      PixelData otherPixelData = decodePixel(otherData);
      if (otherPixelData.type == PIXEL_EMPTY) continue;

      if (srcPos == otherPixelData.src) return; // Not an island

      float dist = distance(pos, otherPixelData.src);
      if (dist < bestDistance && otherPixelData.src != srcPos) {
        bestDistance = dist;
        bestData = otherData;
      }
    }
  }

  imageStore(image, pos, bestData);
}

void locateVerticesPass() {
  ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
  ivec2 dims = imageSize(image);
  if (!inBounds(pos, dims)) return;

  // Ignore corners on edge
  if (pos.y == 0 || pos.x == dims.x - 1) return;

  int neighbors[] = getVoronoiVertexNeighbors(pos);

  // Ignore cases where diagonals are the same
  if (neighbors[0] == neighbors[3] || neighbors[1] == neighbors[2]) return;

  int distinctCount = countUniquePositions(neighbors);  
  if (distinctCount >= 3) {
    PixelData pixelData = decodePixel(imageLoad(image, pos));
    vec4 px = encodePixel(pixelData.siteIndex, pixelData.triangleIndex, PIXEL_VORONOI_VERTEX, encodeColor(0, 255, 0));
    imageStore(image, pos, px);
  }
}

void main() {
  switch(params.phase) {
    case 0:
      initPass();
      break;
    case 1:
      jfaPass();
      break;
    case 2:
      removeIslandsPass();
      break;
    case 3:
      locateVerticesPass();
      break;
  }
}
