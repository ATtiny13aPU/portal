#version 100
// Version can't be changed to upper versions because of WebGL.

precision highp float;

// ---------------------------------------------------------------------------
// Scalar math ---------------------------------------------------------------
// ---------------------------------------------------------------------------

#define PI acos(-1.)
#define PI2 (acos(-1.) / 2.0)
    
// Checks if `x` is in range [a, b].
bool between(float a, float x, float b) {
    return a <= x && x <= b;
}

// Returns square of input.
float sqr(float a) {
    return a*a;
}

// ---------------------------------------------------------------------------
// Vector and ray math -------------------------------------------------------
// ---------------------------------------------------------------------------

struct Ray
{
    vec4 o; // Origin.
    vec4 d; // Direction.
};

const Ray ray_none = Ray(vec4(0.), vec4(0.));

// Returns normal that anti-directed to dir ray, and has length 1.
vec3 normalize_normal(vec3 normal, vec3 dir) {
    normal = normalize(normal);
    if (dot(normal, dir) > 0.) {
        normal *= -1.;
    }
    return normal;
}

// Is two vectors has same direction.
bool is_collinear(vec3 a, vec3 b) {
    return abs(dot(a, b) / (length(a) * length(b)) - 1.) < 0.01;
}

// Return reflected dir vector, based on normal and current dir.
vec3 my_reflect(vec3 dir, vec3 normal) {
     return dir - normal * dot(dir, normal) / dot(normal, normal) * 2.;
}

// Return refracted dir vector, based on normal and current dir.
vec3 my_refract(vec3 dir, vec3 normal, float refractive_index) {
    float ri = refractive_index;
    bool from_outside = dot(normal, dir) > 0.;
    if (!from_outside) {
        ri = 1. / ri;
    } else {
        normal = -normal;
    }

    dir = normalize(dir);
    float c = -dot(normal, dir);
    float d = 1.0 - ri * ri * (1.0 - c*c);
    if (d > 0.) {
        return dir * ri + normal * (ri * c - sqrt(d));
    } else {
        return my_reflect(dir, normal);
    }
}

// Return ray, trat is transformed used matrix. NOTE: Do not forget to normalize new r.d!!! If your `t` depends on it, memorize it somewhere.
Ray transform(mat4 matrix, Ray r) {
    return Ray(
        matrix * r.o,
        matrix * r.d
    );
}

vec3 get_normal(mat4 matrix) {
    return matrix[2].xyz;
}

// ---------------------------------------------------------------------------
// Surface intersection ------------------------------------------------------
// ---------------------------------------------------------------------------

// Intersection with some surface.
struct SurfaceIntersection {
    bool hit; // Is intersect.
    float t; // Distance to surface.
    float u; // X position on surface.
    float v; // Y position on surface.
    vec3 n; // Normal at intersection point.
};

// No intersection.
const SurfaceIntersection intersection_none = SurfaceIntersection(false, 1e10, 0., 0., vec3(0.));

// Intersect ray with plane with matrix `inverse(plane)`, and `normal`.
SurfaceIntersection plane_intersect(Ray r, mat4 plane_inv, vec3 normal) {
    normal = normalize_normal(normal, r.d.xyz);
    r = transform(plane_inv, r);
    float len = length(r.d);
    r.d = normalize(r.d);

    float t = -r.o.z/r.d.z;
    if (t < 0.) {
        return intersection_none;
    } else {
        vec4 pos = r.o + r.d * t; 
        return SurfaceIntersection(true, t / len, pos.x, pos.y, normal);
    }
}

// ---------------------------------------------------------------------------
// Color utils ---------------------------------------------------------------
// ---------------------------------------------------------------------------

// Forms color that next can be alpha-corrected. You should use this function instead of vec3(r, g, b), because of alpha-correction.
vec3 color(float r, float g, float b) {
    return vec3(r*r, g*g, b*b);
}

// Returns how this normal should change color.
float color_normal(vec3 normal, vec4 direction) {
    return abs(dot(normalize(direction.xyz), normalize(normal)));
}

// Returns grid color based on position and start color. Copy-pasted somewhere from shadertoy.
vec3 color_grid(vec3 start, vec2 uv) {
    uv /= 8.;
    uv = uv - vec2(0.125, 0.125);
    const float fr = 3.14159*8.0;
    vec3 col = start;
    col += 0.4*smoothstep(-0.01,0.01,cos(uv.x*fr*0.5)*cos(uv.y*fr*0.5)); 
    float wi = smoothstep(-1.0,-0.98,cos(uv.x*fr))*smoothstep(-1.0,-0.98,cos(uv.y*fr));
    col *= wi;
    
    return col;
}

// Adds color `b` to color `a` with coef, that must lie in [0..1]. If coef == 0, then result is `a`, if coef == 1.0, then result is `b`.
vec3 color_add_weighted(vec3 a, vec3 b, float coef) {
    return a*(1.0 - coef) + b*coef;
}

// ---------------------------------------------------------------------------
// Materials processing ------------------------------------------------------
// ---------------------------------------------------------------------------

uniform float _offset_after_material; // Normally should equals to 0.0001, but for mobile can be different

// Result after material processing.
struct MaterialProcessing {
    bool is_final; // If this flag set to false, then next ray tracing will be proceed. Useful for: portals, glass, mirrors, etc.
    vec3 mul_to_color; // If is_final = true, then this color is multiplied to current color, otherwise this is the final color.
    Ray new_ray; // New ray if is_final = true.
};

// Shortcut for creating material with is_final = true.
MaterialProcessing material_final(vec3 color) {
    return MaterialProcessing(true, color, ray_none);    
}

// Shortcut for creating material with is_final = false.
MaterialProcessing material_next(vec3 mul_color, Ray new_ray) {
    return MaterialProcessing(false, mul_color, new_ray);
}

// Function to easy write simple material.
MaterialProcessing material_simple(
    SurfaceIntersection hit, Ray r,
    vec3 color, float normal_coef, 
    bool grid, float grid_scale, float grid_coef
) {
    color = color_add_weighted(color, color * color_normal(hit.n, r.d), normal_coef);
    if (grid) {
        color = color_add_weighted(color, color_grid(color, vec2(hit.u, hit.v) * grid_scale), grid_coef);
    }
    return material_final(color);
}

// Function to easy write reflect material.
MaterialProcessing material_reflect(
    SurfaceIntersection hit, Ray r,
    vec3 add_to_color
) {
    r.d = vec4(my_reflect(r.d.xyz, hit.n), 0.);
    r.o += r.d * _offset_after_material;
    return material_next(add_to_color, r);
}

// Function to easy write refract material.
MaterialProcessing material_refract(
    SurfaceIntersection hit, Ray r,
    vec3 add_to_color, float refractive_index
) {
    r.d = vec4(my_refract(r.d.xyz, hit.n, refractive_index), 0.);
    r.o += r.d * _offset_after_material;
    return material_next(add_to_color, r);
}

// Function to easy write teleport material.
MaterialProcessing material_teleport(
    SurfaceIntersection hit, Ray r,
    mat4 teleport_matrix
) {
    r.o += r.d * _offset_after_material;
    // todo add add_gray_after_teleportation
    r = transform(teleport_matrix, r);
    r.d = normalize(r.d);
    return material_next(vec3(1.), r);
}

// System materials
#define NOT_INSIDE 0
#define TELEPORT 1

// Actual predefined materials
#define DEBUG_RED 2
#define DEBUG_GREEN 3
#define DEBUG_BLUE 4

// User must use this offset for his materials
#define USER_MATERIAL_OFFSET 10

// ---------------------------------------------------------------------------
// Scene intersection --------------------------------------------------------
// ---------------------------------------------------------------------------

// Intersection with material.
struct SceneIntersection {
    int material;
    SurfaceIntersection hit;
};

const SceneIntersection scene_intersection_none = SceneIntersection(0, intersection_none);

bool nearer(SurfaceIntersection result, SurfaceIntersection current) {
    return current.hit && (current.t > 0.) && (!result.hit || (result.hit && current.t < result.t));
}

bool nearer(SceneIntersection result, SurfaceIntersection current) {
    return nearer(result.hit, current);
}

bool nearer(SceneIntersection result, SceneIntersection current) {
    return nearer(result, current.hit);
}

// Get capsule normal, thanks iq: https://www.shadertoy.com/view/Xt3SzX
vec3 cap_normal(vec3 pos, vec3 a, vec3 b, float radius) {
    vec3  ba = b - a;
    vec3  pa = pos - a;
    float h = clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0);
    return (pa - h*ba)/radius;
}

// Get intersection with capsule, thanks iq: https://www.shadertoy.com/view/Xt3SzX
SurfaceIntersection cap(Ray r, vec3 pa, vec3 pb, float radius) {
    vec3 ro = r.o.xyz;
    vec3 rd = r.d.xyz;
    vec3 ba = pb - pa;
    vec3 oa = ro - pa;

    float baba = dot(ba,ba);
    float bard = dot(ba,rd);
    float baoa = dot(ba,oa);
    float rdoa = dot(rd,oa);
    float oaoa = dot(oa,oa);

    float a = baba      - bard*bard;
    float b = baba*rdoa - baoa*bard;
    float c = baba*oaoa - baoa*baoa - radius*radius*baba;
    float h = b*b - a*c;
    if( h>=0.0 ) {
        float t = (-b-sqrt(h))/a;
        float y = baoa + t*bard;
        // body
        if( y>0.0 && y<baba ) {
            vec3 pos = ro + rd * t;
            return SurfaceIntersection(true, t, 0., 0., cap_normal(pos, pa, pb, radius));
        }
        // caps
        vec3 oc = (y<=0.0) ? oa : ro - pb;
        b = dot(rd,oc);
        c = dot(oc,oc) - radius*radius;
        h = b*b - c;
        if( h>0.0 ) {
            t = -b - sqrt(h);
            vec3 pos = ro + rd * t;
            return SurfaceIntersection(true, t, 0., 0., cap_normal(pos, pa, pb, radius));
        };
    }
    return intersection_none;
}

// Intersect ray with debug thing
SceneIntersection debug_intersect(Ray r) {
    vec3 pa = vec3(0.);
    float radius = 0.03;

    SurfaceIntersection hit = intersection_none;
    SceneIntersection i = SceneIntersection(0, hit);

    hit = cap(r, pa, vec3(1., 0., 0.), radius);
    if (nearer(i, hit)) {
      i.material = DEBUG_RED;
      i.hit = hit;
    }

    hit = cap(r, pa, vec3(0., 1., 0.), radius);
    if (nearer(i, hit)) {
      i.material = DEBUG_GREEN;
      i.hit = hit;
    }

    hit = cap(r, pa, vec3(0., 0., 1.), radius);
    if (nearer(i, hit)) {
      i.material = DEBUG_BLUE;
      i.hit = hit;
    }

    return i;
}

// ---------------------------------------------------------------------------
// Code for current scene ----------------------------------------------------
// ---------------------------------------------------------------------------

SceneIntersection process_plane_intersection(SceneIntersection i, SurfaceIntersection hit, int inside) {
    if (inside == NOT_INSIDE) {
        // Not inside, do nothing
    } else if (inside == TELEPORT) {
        // This is wrong code, do nothing
    } else {
        i.hit = hit;
        i.material = inside;
    }
    return i;
}

SceneIntersection process_portal_intersection(SceneIntersection i, SurfaceIntersection hit, int inside, int teleport_material) {
    if (inside == NOT_INSIDE) {
        // Not inside, do nothing
    } else if (inside == TELEPORT) {
        i.hit = hit;
        i.material = teleport_material;
    } else {
        i.hit = hit;
        i.material = inside;
    }
    return i;
}

// ---------------------------------------------------------------------------
// User library --------------------------------------------------------------
// ---------------------------------------------------------------------------

//%library//%

//%uniforms//%

//%materials_defines//%

//%intersection_functions//%

SceneIntersection scene_intersect(Ray r) {
    SceneIntersection i = SceneIntersection(0, intersection_none);
    SceneIntersection ihit = SceneIntersection(0, intersection_none);
    SurfaceIntersection hit = intersection_none;
    vec3 normal = vec3(0.);
    int inside = NOT_INSIDE;
    float len = 1.;
    Ray transformed_ray = ray_none;

//%intersections//%

    return i;
}

MaterialProcessing material_process(Ray r, SceneIntersection i) {
    SurfaceIntersection hit = i.hit;
    if (i.material == 0) {
    } else if (i.material == DEBUG_RED) {
        return material_simple(hit, r, color(0.9, 0.2, 0.2), 0.5, false, 1., 0.);
    } else if (i.material == DEBUG_GREEN) {
        return material_simple(hit, r, color(0.2, 0.9, 0.2), 0.5, false, 1., 0.);
    } else if (i.material == DEBUG_BLUE) {
        return material_simple(hit, r, color(0.2, 0.2, 0.9), 0.5, false, 1., 0.);

//%material_processing//%

    }

    // If there is no material with this number.
    return material_final(vec3(0.));
}

// ---------------------------------------------------------------------------
// Ray tracing ---------------------------------------------------------------
// ---------------------------------------------------------------------------

uniform int _ray_tracing_depth;

vec3 ray_tracing(Ray r) {
    vec3 current_color = vec3(1.);
    for (int j = 0; j < 10000; j++) {
        if (j > _ray_tracing_depth) {
            return current_color;
        }
        SceneIntersection i = scene_intersect(r);

        // Offset ray
        r.o += r.d * i.hit.t;
        if (i.hit.hit) {
            MaterialProcessing m = material_process(r, i);
            current_color *= m.mul_to_color;
            if (m.is_final) {
                return current_color;
            } else {
                r = m.new_ray;
            }
        } else {
            return current_color * color(0.6, 0.6, 0.6);
        }
    }
    return current_color;
}

// ---------------------------------------------------------------------------
// Draw image ----------------------------------------------------------------
// ---------------------------------------------------------------------------

uniform mat4 _camera;
uniform float _view_angle;
uniform int _use_panini_projection;
uniform float _panini_param;
varying vec2 uv;
varying vec2 uv_screen;

const float Pi = 3.14159265359;
const float Pi2 = Pi * 2.0;
const float Pi05 = Pi * 0.5;

float Pow2(float x) {return x*x;}

// Thanks https://www.shadertoy.com/view/Wt3fzB
// tc ∈ [-1,1]² | fov ∈ [0, π) | d ∈ [0,1]
vec3 PaniniProjection(vec2 tc, float fov, float d)
{
    float d2 = d*d;

    {
        float fo = Pi05 - fov * 0.5;

        // There was * 2, because image should be 2×1 with coords [-1,1]², but in my version, image should be 1×1 with coords [-1,1]².
        float f = cos(fo)/sin(fo) /* * 2.0 */;
        float f2 = f*f;

        float b = (sqrt(max(0.0, Pow2(d+d2)*(f2+f2*f2))) - (d*f+f)) / (d2+d2*f2-1.0);

        tc *= b;
    }
    
    /* http://tksharpless.net/vedutismo/Pannini/panini.pdf */
    float h = tc.x;
    float v = tc.y;
    
    float h2 = h*h;
    
    float k = h2/Pow2(d+1.0);
    float k2 = k*k;
    
    float discr = max(0.0, k2*d2 - (k+1.0)*(k*d2-1.0));
    
    float cosPhi = (-k*d+sqrt(discr))/(k+1.0);
    float S = (d+1.0)/(d+cosPhi);
    float tanTheta = v/S;
    
    float sinPhi = sqrt(max(0.0, 1.0-Pow2(cosPhi)));
    if(tc.x < 0.0) sinPhi *= -1.0;
    
    float s = inversesqrt(1.0+Pow2(tanTheta));
    
    return vec3(sinPhi, tanTheta, cosPhi) * s;
}

void main() {
    vec4 o = _camera * vec4(0., 0., 0., 1.);
    vec4 d;
    if (_use_panini_projection == 1) {
        d = normalize(_camera * vec4(PaniniProjection(vec2(uv_screen.x, uv_screen.y), _view_angle, _panini_param), 0.));
    } else {
        float h = tan(_view_angle / 2.);
        d = normalize(_camera * vec4(uv_screen.x * h, uv_screen.y * h, 1.0, 0.));
    }
     
    Ray r = Ray(o, d);
    gl_FragColor = vec4(sqrt(ray_tracing(r)), 1.);
}
