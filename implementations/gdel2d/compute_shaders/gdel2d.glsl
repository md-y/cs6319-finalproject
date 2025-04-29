#[compute]
#version 450

#define NULL_POINT -100
#define NULL_EDGE ivec2(NULL_POINT, NULL_POINT)
#define NULL_TRIANGLE -100

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer PointBuffer {
  int insertedCount;
  vec3 points[];
}
points_buffer;

layout(set = 1, binding = 0, std430) restrict buffer TriangleBuffer {
  int badEdgeFlag;
  int count;
  ivec4 triangles[];
}
triangle_buffer;

layout(set = 2, binding = 0, std430) restrict buffer InsertionBuffer {
  int insertions[];
}
insertion_buffer;

layout(push_constant, std430) uniform Params {
  int phase;
  int iteration;
} params;

int getThreadIndex() {
  ivec2 id = ivec2(gl_GlobalInvocationID.xy);
  return id.x * 16 + id.y;
}

vec2 getPoint(int idx) {
  int gamma = 1 << 30;
  if (idx == -1) {
    return vec2(-gamma, gamma);
  }
  if (idx == -2) {
    return vec2(0, -gamma);
  }
  if (idx == -3) {
    return vec2(gamma, gamma);
  }
  vec3 p = points_buffer.points[idx];
  return vec2(p.x, p.y);
}

void deletePoint(int idx) {
  points_buffer.points[idx].z = 1;
}

bool isPointDeleted(int idx) {
  return points_buffer.points[idx].z != 0;
}

ivec3 getTriangle(int idx) {
  ivec4 val = triangle_buffer.triangles[idx];
  return ivec3(val.x, val.y, val.z);
}

void setTriangle(int idx, ivec3 tri) {
  triangle_buffer.triangles[idx] = ivec4(tri.x, tri.y, tri.z, 0);
}

int getUpdatedBadEdgeFlag() {
  return (params.phase + 1) * 100 + params.iteration + 1;
}

void markTriangle(int idx) {
  ivec3 tri = getTriangle(idx);
  triangle_buffer.triangles[idx] = ivec4(tri.x, tri.y, tri.z, 1);
  int flagVal = getUpdatedBadEdgeFlag();
  if (triangle_buffer.badEdgeFlag != flagVal) {
    triangle_buffer.badEdgeFlag = flagVal;
  }
}

void resetBadEdgeFlagIfNecessary() {
  int oldVal = triangle_buffer.badEdgeFlag;
  if (oldVal != getUpdatedBadEdgeFlag()) {
    atomicCompSwap(triangle_buffer.badEdgeFlag, oldVal, 0);
  }
}

void unmarkTriangle(int idx) {
  ivec3 tri = getTriangle(idx);
  triangle_buffer.triangles[idx] = ivec4(tri.x, tri.y, tri.z, 0);
}

bool triangleIsMarked(int idx) {
  ivec4 tri = triangle_buffer.triangles[idx];
  return tri.w != 0;
}

ivec2 getSharedEdge(int triIdx1, int triIdx2) {
  ivec3 tri1 = getTriangle(triIdx1);
  ivec3 tri2 = getTriangle(triIdx2);

  ivec2 edges1[3];
  edges1[0] = ivec2(tri1.x, tri1.y);
  edges1[1] = ivec2(tri1.y, tri1.z);
  edges1[2] = ivec2(tri1.z, tri1.x);

  ivec2 edges2[3];
  edges2[0] = ivec2(tri2.x, tri2.z);
  edges2[1] = ivec2(tri2.z, tri2.y);
  edges2[2] = ivec2(tri2.y, tri2.x);
  
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      if (edges1[i] == edges2[j]) {
        return edges1[i];
      }
    }
  }
  return NULL_EDGE;
}

bool pointInCircumcircle(int triIdx, int pointIdx) {
  ivec3 tri = getTriangle(triIdx);
  vec2 a = getPoint(tri.x);
  vec2 b = getPoint(tri.y);
  vec2 c = getPoint(tri.z);
  vec2 p = getPoint(pointIdx);

  vec2 aRel = a - p;
  vec2 bRel = b - p;
  vec2 cRel = c - p;

  float det = (
    (aRel.x * aRel.x + aRel.y * aRel.y) * (bRel.x * cRel.y - bRel.y * cRel.x) -
    (bRel.x * bRel.x + bRel.y * bRel.y) * (aRel.x * cRel.y - aRel.y * cRel.x) +
    (cRel.x * cRel.x + cRel.y * cRel.y) * (aRel.x * bRel.y - aRel.y * bRel.x)
  );

  return det > 0.0;
}

int findUnsharedPoint(ivec3 tri, int p, int q) {
  for (int i = 0; i < 3; i++) {
    if (tri[i] != p && tri[i] != q) {
      return tri[i];
    }
  }
  return NULL_POINT;
}

float vecSign(vec2 p1, vec2 p2, vec2 p3) {
  return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
}

bool pointInTriangle(int triangleIndex, int pointIndex) {
  ivec3 tri = getTriangle(triangleIndex);

  vec2 A = getPoint(tri.x);
  vec2 B = getPoint(tri.y);
  vec2 C = getPoint(tri.z);

  vec2 P = getPoint(pointIndex);

  float d1 = vecSign(P, A, B);
  float d2 = vecSign(P, B, C);
  float d3 = vecSign(P, C, A);

  bool hasNeg = (d1 < 0.0) || (d2 < 0.0) || (d3 < 0.0);
  bool hasPos = (d1 > 0.0) || (d2 > 0.0) || (d3 > 0.0);

  return !(hasNeg && hasPos);
}

float orient(vec2 a, vec2 b, vec2 c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

bool doSegmentsCross(vec2 a, vec2 b, vec2 c, vec2 d) {
  float o1 = orient(a, b, c);
  float o2 = orient(a, b, d);
  float o3 = orient(c, d, a);
  float o4 = orient(c, d, b);
  return (o1 * o2 < 0.0) && (o3 * o4 < 0.0);
}

bool isFlipValid(int triIdx1, int triIdx2, int p, int q, int r, int s) {
  ivec3 tris[] = ivec3[](getTriangle(triIdx1), getTriangle(triIdx2));

  vec2 rPos = getPoint(r);
  vec2 sPos = getPoint(s);

  for (int t = 0; t < 2; t++) {
    ivec3 tri = tris[t];
    for (int i = 0; i < 3; ++i) {
      int vi = tri[i];
      int vj = tri[(i+1)%3];
      if ((vi == p && vj == q) || (vi == q && vj == p)) continue;
      vec2 iPos = getPoint(vi);
      vec2 jPos = getPoint(vj);
      if (doSegmentsCross(rPos, sPos, iPos, jPos)) return false;
    }
  }

  return true;
}


/*
* PHASES
*/

void updateInsertion() {
  int pointIdx = getThreadIndex();
  uint pointCount = points_buffer.points.length();
  if (pointIdx >= pointCount) return;
  if (isPointDeleted(pointIdx)) return;

  int loc = NULL_TRIANGLE;
  for (int i = 0; i < triangle_buffer.count; i++) {
    if (pointInTriangle(i, pointIdx)) {
      loc = i;
      break;
    }
  }
  if (loc == NULL_TRIANGLE) return;
  insertion_buffer.insertions[loc] = pointIdx;
}

void splitTriangles() {
  int triIdx = getThreadIndex();
  if (triIdx >= triangle_buffer.count) return;

  int pointIdx = insertion_buffer.insertions[triIdx];
  if (pointIdx < 0) return;

  insertion_buffer.insertions[triIdx] = -1;

  ivec3 tri = getTriangle(triIdx);
  int newIdx = atomicAdd(triangle_buffer.count, 2);
  setTriangle(triIdx, ivec3(tri.x, tri.y, pointIdx));
  setTriangle(newIdx, ivec3(tri.y, tri.z, pointIdx));
  setTriangle(newIdx + 1, ivec3(tri.z, tri.x, pointIdx));

  markTriangle(triIdx);
  markTriangle(newIdx);
  markTriangle(newIdx + 1);

  deletePoint(pointIdx);
  atomicAdd(points_buffer.insertedCount, 1);
}

void flipEdges() {
  int triIdx = getThreadIndex();
  if (triIdx == 0) resetBadEdgeFlagIfNecessary();
  if (triIdx >= triangle_buffer.count) return;
  if (!triangleIsMarked(triIdx)) return;

  ivec3 tri = getTriangle(triIdx);

  int incident[3] = int[](NULL_TRIANGLE, NULL_TRIANGLE, NULL_TRIANGLE);
  ivec2 incidentEdges[3] = ivec2[](NULL_EDGE, NULL_EDGE, NULL_EDGE);
  int incidentCount = 0;

  for (int i = 0; i < triangle_buffer.count; i++) {
    if (i == triIdx) continue;
    ivec2 edge = getSharedEdge(triIdx, i);
    if (edge == NULL_EDGE) continue;
    if (triangleIsMarked(i) && i < triIdx) {
      unmarkTriangle(triIdx);
      return;
    }
    incidentEdges[incidentCount] = edge;
    incident[incidentCount] = i;
    incidentCount++;
  }

  for (int i = 0; i < incidentCount; i++) {
    int incIdx = incident[i];
    ivec3 inc = getTriangle(incIdx);
    ivec2 sharedEdge = incidentEdges[i];
    int p = sharedEdge.x;
    int q = sharedEdge.y;

    int r = findUnsharedPoint(inc, p, q);
    if (r == NULL_POINT || !pointInCircumcircle(triIdx, r)) continue;
    int s = findUnsharedPoint(tri, p, q);
    if (s == NULL_POINT) continue;

    if (!isFlipValid(triIdx, incIdx, p, q, r, s)) continue;

    setTriangle(triIdx, ivec3(s, p, r));
    setTriangle(incIdx, ivec3(s, q, r));
    markTriangle(triIdx);
    markTriangle(incIdx);
    return;
  }

  unmarkTriangle(triIdx);
}

void main() {
  switch(params.phase) {
    case 0:
      updateInsertion();
      break;
    case 1:
      splitTriangles();
      break;
    case 2:
      flipEdges();
      break;
  }
}
