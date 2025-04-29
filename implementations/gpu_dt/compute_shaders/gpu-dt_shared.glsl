#define PIXEL_EMPTY 0.0
#define PIXEL_VORONOI_FLOOD 1.0
#define PIXEL_VORONOI_VERTEX 2.0

struct PixelData {
  ivec2 src;
  int siteIndex;
  int triangleIndex;
  float type;
  float color;
};

PixelData decodePixel(vec4 data) {
  int siteIndex = int(data.x);
  ivec2 src = ivec2(abs(round(points_buffer.points[siteIndex])));
  return PixelData(src, siteIndex, int(data.y), data.z, data.w);
}

vec4 encodePixel(float siteIndex, float triangleIndex, float type, float color) {
  vec4 data = vec4(0.0);
  data.x = siteIndex;
  data.y = triangleIndex;
  data.z = type;
  data.w = color;
  return data;
}

float encodeColor(int r, int g, int b) {
  r = r & 0xFF;
  g = g & 0xFF;
  b = b & 0xFF;
  int value = (r << 16) + (g << 8) + b;
  return float(value);
}

bool inBounds(vec2 pos, vec2 bounds) {
  return pos.x >= 0 && pos.x < bounds.x && pos.y >= 0 && pos.y < bounds.y;
}

int[4] getVoronoiVertexNeighbors(ivec2 pos) {
  int neighbors[4];
  for (int i = 0; i < 4; i++) {
    ivec2 offset = ivec2(i / 2, -(i % 2));
    vec4 px = imageLoad(image, pos + offset);
    PixelData pixelData = decodePixel(px);
    neighbors[i] = pixelData.siteIndex;
  }
  return neighbors;
}

int countUniquePositions(int[4] positions) {
  int distinctCount = 1;
  for (int i = 1; i < positions.length(); i++) {
    bool hasSame = false;
    for (int j = 0; j < i; j++) {
      if (positions[i] == positions[j]) {
        hasSame = true;
        break;
      }
    }
    if (!hasSame) distinctCount++;
  }
  return distinctCount;
}
