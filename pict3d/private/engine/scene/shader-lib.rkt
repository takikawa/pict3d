#lang typed/racket/base

(require "../shader-lib.rkt")

(provide (all-defined-out))

(define pack-unpack-normal-code
  (string-append
   #<<code
vec2 pack_normal(vec3 norm) {
  vec2 res;
  res = 0.5 * (norm.xy + vec2(1.0, 1.0));
  res.x *= (norm.z < 0 ? -1.0 : 1.0);
  return res;
}

vec3 unpack_normal(vec2 norm) {
  vec3 res;
  res.xy = (2.0 * abs(norm)) - vec2(1.0, 1.0);
  res.z = (norm.x < 0 ? -1.0 : 1.0) * sqrt(abs(1.0 - res.x * res.x - res.y * res.y));
  return res;
}
code
   "\n\n"))

(define depth-fragment-code
  (string-append
   #<<code
float frag_depth(float znear, float zfar, float z) {
  return log2(-z/zfar) / log2(znear/zfar);
}

float unfrag_depth(float znear, float zfar, float logz) {
  return -exp2(logz * log2(znear/zfar)) * zfar;
}
code
   "\n\n"))

(define get-view-position-fragment-code
  (string-append
   depth-fragment-code
   #<<code
vec3 get_view_position(sampler2D depthTex, int width, int height, mat3 unproj0, mat3 unproj1,
                       float znear, float zfar) {
  // compute view z from depth buffer
  float depth = texelFetch(depthTex, ivec2(gl_FragCoord.xy), 0).r;
  if (depth == 0.0) discard;
  float z = unfrag_depth(znear, zfar, depth);
  
  // clip xy
  vec3 cpos = vec3((gl_FragCoord.xy / vec2(width,height) - vec2(0.5)) * 2.0, 1.0);
  
  // compute view position from clip xy and view z
  vec3 p0 = unproj0 * cpos;
  vec3 p1 = unproj1 * cpos;
  return (p0*z+p1) / p0.z;
}
code
   "\n\n"))

(define get-surface-fragment-code
  (string-append
   pack-unpack-normal-code
   #<<code
struct surface {
  vec3 normal;
  float roughness;
};

surface get_surface(sampler2D matTex) {
  vec4 mat = texelFetch(matTex, ivec2(gl_FragCoord.xy), 0);
  return surface(unpack_normal(mat.rg), mat.a);
}
code
   "\n\n"))

(define impostor-bounds-code
  (string-append
   #<<code
struct aabb {
  vec3 mins;
  vec3 maxs;
  float is_degenerate;
};

aabb impostor_bounds(mat4 view, mat4 proj, vec3 wmin, vec3 wmax) {
  vec4 vs[8];
  vs[0] = vec4(wmin, 1.0);
  vs[1] = vec4(wmin.xy, wmax.z, 1.0);
  vs[2] = vec4(wmin.x, wmax.y, wmin.z, 1.0);
  vs[3] = vec4(wmin.x, wmax.yz, 1.0);
  vs[4] = vec4(wmax.x, wmin.yz, 1.0);
  vs[5] = vec4(wmax.x, wmin.y, wmax.z, 1.0);
  vs[6] = vec4(wmax.xy, wmin.z, 1.0);
  vs[7] = vec4(wmax, 1.0);
  
  // view space min and max
  vec3 vmin = vec3(+1e39);  // closest 32-bit float is +Inf
  vec3 vmax = vec3(-1e39);
  
  // clip space min and max
  vec3 cmin = vec3(+1e39);
  vec3 cmax = vec3(-1e39);
  
  for (int i = 0; i < 8; i++) {
    vec4 vpos = view * vs[i];
    vpos /= vpos.w;
    vmin = min(vmin, vpos.xyz);
    vmax = max(vmax, vpos.xyz);
    
    vec4 cpos = proj * vpos;
    cpos /= abs(cpos.w);
    cmin = min(cmin, cpos.xyz);
    cmax = max(cmax, cpos.xyz);
  }
  
  if (vmin.z > 0.0) return aabb(cmin, cmax, 1.0);

  // if we're inside it, we should draw on the whole screen
  if (max(vmin.x, max(vmin.y, vmin.z)) <= 0.0 &&
      min(vmax.x, min(vmax.y, vmax.z)) >= 0.0) {
    cmin = vec3(-1.0);
    cmax = vec3(+1.0);
  }

  return aabb(cmin, cmax, 0.0);
}
code
   "\n\n"))

(define output-impostor-strip-vertex-code
  (string-append
   impostor-bounds-code
   #<<code
float output_impostor_strip(mat4 view, mat4 proj, vec3 wmin, vec3 wmax) {
  aabb bbx = impostor_bounds(view, proj, wmin, wmax);

  // output the correct vertices for a triangle strip
  switch (gl_VertexID) {
  case 0:
    gl_Position = vec4(bbx.mins.xy, 0.0, 1.0);
    break;
  case 1:
    gl_Position = vec4(bbx.maxs.x, bbx.mins.y, 0.0, 1.0);
    break;
  case 2:
    gl_Position = vec4(bbx.mins.x, bbx.maxs.y, 0.0, 1.0);
    break;
  default:
    gl_Position = vec4(bbx.maxs.xy, 0.0, 1.0);
    break;
  }

  return bbx.is_degenerate;
}
code
   "\n\n"))

(define output-impostor-quad-vertex-code
  (string-append
   impostor-bounds-code
   #<<code
float output_impostor_quad(mat4 view, mat4 proj, vec3 wmin, vec3 wmax) {
  aabb bbx = impostor_bounds(view, proj, wmin, wmax);

  // output the correct vertices for a quad
  switch (gl_VertexID % 4) {
  case 0:
    gl_Position = vec4(bbx.mins.xy, 0.0, 1.0);
    break;
  case 1:
    gl_Position = vec4(bbx.maxs.x, bbx.mins.y, 0.0, 1.0);
    break;
  case 2:
    gl_Position = vec4(bbx.maxs.xy, 0.0, 1.0);
    break;
  default:
    gl_Position = vec4(bbx.mins.x, bbx.maxs.y, 0.0, 1.0);
    break;
  }

  return bbx.is_degenerate;
}
code
   "\n\n"))

(define ray-trace-fragment-code
  (string-append
   #<<code
vec3 frag_coord_to_direction(vec4 frag_coord, mat4 unproj, int width, int height) {
  vec2 clip_xy = (frag_coord.xy / vec2(width,height) - vec2(0.5)) * 2.0;
  vec4 vpos = unproj * vec4(clip_xy, 0.0, 1.0);
  return normalize(vpos.xyz);
}

vec2 unit_sphere_intersect(vec3 origin, vec3 dir) {
  float b = dot(origin,dir);
  float disc = b*b - dot(origin,origin) + 1;
  if (disc < 0.0) discard;
  float q = sqrt(disc);
  return vec2(-q,q) - vec2(b);
}
code
   "\n\n"))

(define model-vertex-code
  (string-append
   matrix-code
   #<<code
in vec4 _model0;
in vec4 _model1;
in vec4 _model2;

mat4x3 get_model_transform() {
  return rows2mat4x3(_model0, _model1, _model2);
}
code
   "\n\n"))

(define output-mat-fragment-code
  (string-append
   depth-fragment-code
   pack-unpack-normal-code
   #<<code
void output_mat(vec3 dir, float roughness, float z, float znear, float zfar) {
  gl_FragDepth = frag_depth(znear, zfar, z);
  gl_FragColor = vec4(pack_normal(normalize(dir)), 1.0, roughness);
}
code
   "\n\n"))

(define output-opaq-fragment-code
  (string-append
   depth-fragment-code
   #<<code
void output_opaq(vec3 color, float a, float z, float znear, float zfar) {
  gl_FragDepth = frag_depth(znear, zfar, z);
  gl_FragColor = vec4(color, a);
}
code
   "\n\n"))

(define output-tran-fragment-code
  (string-append
   depth-fragment-code
   #<<code
void output_tran(vec3 color, float a, float z, float znear, float zfar) {
  float depth = frag_depth(znear, zfar, z);
  float d = 1 - depth;
  float weight = a * clamp(1 / (d*d*d) - 1, 0.001953125, 32768.0);
  gl_FragDepth = depth;
  gl_FragData[0] = vec4(color * weight * a, a);
  gl_FragData[1] = vec4(a * weight);
}
code
   "\n\n"))

(define light-fragment-code
  (string-append
   get-surface-fragment-code
   #<<code
vec3 attenuate_invsqr(vec3 light_color, float dist) {
  return max(vec3(0.0), (light_color/(dist*dist) - 0.05) / 0.95);
}

vec3 attenuate_linear(vec3 light_color, float radius, float dist) {
  return light_color * max(0.0, (radius - dist) / radius);
}

// Ward model for anisotropic, but without the anisotropy (so that it's consistent with the
// full anisotropic model if we ever want to use it)
float specular(vec3 N, vec3 L, vec3 V, float dotLN, float dotVN, float m) {
  vec3 uH = L+V;  // unnormalized half vector
  float dotsum = dotVN + dotLN;
  float dotHNsqr = dotsum * dotsum / dot(uH,uH);  // pow(dot(N,normalize(uH)),2)
  float mm = m * m;
  return sqrt(dotLN/dotVN) / (12.566371 * mm) * exp((dotHNsqr - 1.0) / (mm * dotHNsqr));
}

void output_light(vec3 light, surface s, vec3 L, vec3 V) {
  vec3 N = s.normal;
  float dotNL = dot(N,L);
  if (dotNL < 1e-7) discard;
  float dotNV = dot(N,V);
  if (dotNV < 1e-7) discard;
  gl_FragData[0] = vec4(light * dotNL, 0.0);
  gl_FragData[1] = vec4(light * specular(N,L,V,dotNL,dotNV,s.roughness), 0.0);
}
code
   "\n\n"))