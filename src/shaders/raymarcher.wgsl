const THREAD_COUNT = 16;
const PI = 3.1415927f;
const MAX_DIST = 1000.0;

@group(0) @binding(0)
  var<storage, read_write> fb : array<vec4f>;

@group(1) @binding(0)
  var<storage, read_write> uniforms : array<f32>;

@group(2) @binding(0)
  var<storage, read_write> shapesb : array<shape>;

@group(2) @binding(1)
  var<storage, read_write> shapesinfob : array<vec4f>;

struct shape {
  transform : vec4f, // xyz = position
  radius : vec4f, // xyz = scale, w = global scale
  rotation : vec4f, // xyz = rotation
  op : vec4f, // x = operation, y = k value, z = repeat mode, w = repeat offset
  color : vec4f, // xyz = color
  animate_transform : vec4f, // xyz = animate position value (sin amplitude), w = animate speed
  animate_rotation : vec4f, // xyz = animate rotation value (sin amplitude), w = animate speed
  quat : vec4f, // xyzw = quaternion
  transform_animated : vec4f, // xyz = position buffer
};

struct march_output {
  color : vec3f,
  depth : f32,
  outline : bool,
};

// =====================================================================
// OPERAÇÕES BOOLEANAS SUAVES (Inigo Quilez, "smooth minimum")
// h é um peso em [0,1] que diz "quanto" de cada forma usar na região de
// transição de largura k. O termo k*h*(1-h) é o que arredonda a junção.
// A cor é misturada com o mesmo peso h, então a cor também "derrete".
// Retorno: xyz = cor, w = distância.
// =====================================================================

// União: fica com o mais próximo dos dois (min), suavizado.
fn op_smooth_union(d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  var k_eps = max(k, 0.0001);
  var h = clamp(0.5 + 0.5 * (d2 - d1) / k_eps, 0.0, 1.0);
  var d = mix(d2, d1, h) - k_eps * h * (1.0 - h);
  var col = mix(col2, col1, h);
  return vec4f(col, d);
}

// Subtração: remove d1 de d2  ->  max(d2, -d1), suavizado.
// (op() chama com d1 = forma nova, d2 = cena acumulada)
// A cavidade recebe a cor da forma que "cortou".
fn op_smooth_subtraction(d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  var k_eps = max(k, 0.0001);
  var h = clamp(0.5 - 0.5 * (d2 + d1) / k_eps, 0.0, 1.0);
  var d = mix(d2, -d1, h) + k_eps * h * (1.0 - h);
  var col = mix(col2, col1, h);
  return vec4f(col, d);
}

// Interseção: só o que está dentro dos dois  ->  max(d1, d2), suavizado.
fn op_smooth_intersection(d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  var k_eps = max(k, 0.0001);
  var h = clamp(0.5 - 0.5 * (d2 - d1) / k_eps, 0.0, 1.0);
  var d = mix(d2, d1, h) + k_eps * h * (1.0 - h);
  var col = mix(col2, col1, h);
  return vec4f(col, d);
}

fn op(op: f32, d1: f32, d2: f32, col1: vec3f, col2: vec3f, k: f32) -> vec4f
{
  // union
  if (op < 1.0)
  {
    return op_smooth_union(d1, d2, col1, col2, k);
  }

  // subtraction
  if (op < 2.0)
  {
    return op_smooth_subtraction(d2, d1, col2, col1, k);
  }

  // intersection
  return op_smooth_intersection(d2, d1, col2, col1, k);
}

// Repetição infinita (domain repetition): dobra o espaço em células de
// tamanho "offset". Todo ponto é levado para a célula central
// [-offset/2, offset/2], então um objeto vira infinitos objetos.
fn repeat(p: vec3f, offset: vec3f) -> vec3f
{
  return modc(p + 0.5 * offset, offset) - 0.5 * offset;
}

fn transform_p(p: vec3f, option: vec2f) -> vec3f
{
  // normal mode
  if (option.x <= 1.0)
  {
    return p;
  }

  // return repeat / mod mode
  return repeat(p, vec3f(option.y));
}

// paleta cosseno (Inigo Quilez) para colorir os fractais
fn palette(t: f32) -> vec3f
{
  return 0.5 + 0.5 * cos(2.0 * PI * (vec3f(t) + vec3f(0.0, 0.33, 0.67)));
}

// =====================================================================
// CENA: devolve a cor e a distância do ponto p até a superfície mais
// próxima, combinando todos os objetos com suas operações.
// =====================================================================
fn scene(p: vec3f) -> vec4f // xyz = color, w = distance
{
    // chão: plano y = 0 (se desligado, distância "infinita" = 100)
    var d = mix(100.0, p.y, uniforms[17]);

    var spheresCount = i32(uniforms[2]);
    var boxesCount = i32(uniforms[3]);
    var torusCount = i32(uniforms[4]);
    var cylindersCount = i32(uniforms[31]);

    var all_objects_count = spheresCount + boxesCount + torusCount + cylindersCount;
    var result = vec4f(vec3f(1.0), d);

    // ---- fractal: Mandelbulb (cena "Fractal") ----
    if (uniforms[18] > 0.5)
    {
      var s = 1.5; // escala: avalio o fractal em p/s e corrijo a distância * s
      var m = sdf_mandelbulb((p - vec3f(0.0, 1.0, 0.0)) / s);
      var col = palette(0.6 + m.y * 1.5);
      result = op_smooth_union(result.w, m.x * s, result.xyz, col, 0.0001);
    }

    // ---- geometria "maluca": fractal apoloniano (cena "Weird") ----
    if (uniforms[19] > 0.5)
    {
      var s = 2.0;
      var w = sdf_weird_thing(p / s, 1.25) * s;
      var col = palette(0.15 * length(p) + 0.1 * p.y);
      result = op_smooth_union(result.w, w, result.xyz, col, 0.0001);
    }

    for (var i = 0; i < all_objects_count; i = i + 1)
    {
      // shapesinfo: x = tipo (0 esfera, 1 caixa, 2 toro, 3 cilindro), y = índice
      // a CPU já ordenou: uniões primeiro, depois subtrações, depois interseções
      var info = shapesinfob[i];
      var shape_type = i32(info.x);
      var idx = i32(info.y);
      var s = shapesb[idx];

      // 1) repetição (se ligada)  2) leva o ponto para o espaço do objeto
      var pt = transform_p(p, s.op.zw);
      var lp = pt - s.transform_animated.xyz;

      var dist = MAX_DIST;
      if (shape_type == 0)
      {
        dist = sdf_sphere(lp, s.radius, s.quat);
      }
      else if (shape_type == 1)
      {
        dist = sdf_round_box(lp, s.radius.xyz, s.radius.w, s.quat);
      }
      else if (shape_type == 2)
      {
        dist = sdf_torus(lp, s.radius.xy, s.quat);
      }
      else
      {
        dist = sdf_cylinder(lp, s.radius.x, s.radius.y, s.radius.w, s.quat);
      }

      // combina com o que já foi acumulado (d1 = cena, d2 = forma nova)
      result = op(s.op.x, result.w, dist, result.xyz, s.color.xyz, s.op.y);
    }

    return result;
}

// =====================================================================
// RAY MARCHING (sphere tracing)
// A distância devolvida pela cena é um "raio seguro": nenhuma superfície
// está mais perto que isso, então posso andar exatamente esse tanto.
// =====================================================================
fn march(ro: vec3f, rd: vec3f) -> march_output
{
  var max_marching_steps = i32(uniforms[5]);
  var EPSILON = uniforms[23];

  var depth = 0.0;
  var color = vec3f(0.0);
  var march_step = uniforms[22];
  var far = uniforms[20];

  var hit = false;
  var min_dist = MAX_DIST; // menor distância que o raio passou de algo (outline)

  for (var i = 0; i < max_marching_steps; i = i + 1)
  {
      var p = ro + rd * depth;
      var res = scene(p);

      min_dist = min(min_dist, res.w);

      // chegou perto o suficiente: acertou
      if (res.w < EPSILON)
      {
        color = res.xyz;
        hit = true;
        break;
      }

      // anda o raio pela distância segura (march_step < 1 deixa mais seguro)
      depth += res.w * march_step;

      // passou do plano de corte: não acertou nada
      if (depth > far)
      {
        break;
      }
  }

  if (!hit)
  {
    // sinaliza "céu" para o get_light; outline = raio passou raspando
    var outline = min_dist < uniforms[27];
    return march_output(vec3f(0.0), MAX_DIST, outline);
  }

  return march_output(color, depth, false);
}

// Normal = gradiente do SDF, por diferenças centrais em x, y e z.
fn get_normal(p: vec3f) -> vec3f
{
  var e = vec2f(0.0005, 0.0);
  var n = vec3f(
    scene(p + e.xyy).w - scene(p - e.xyy).w,
    scene(p + e.yxy).w - scene(p - e.yxy).w,
    scene(p + e.yyx).w - scene(p - e.yyx).w
  );
  return normalize(n);
}

// https://iquilezles.org/articles/rmshadows/
// Marcha da superfície em direção à luz. Se bater em algo -> sombra (0).
// Senão, quanto mais perto o raio passou de um objeto (h) em relação à
// distância percorrida (t), mais "penumbra". k controla a dureza:
// k pequeno -> sombra dura, k grande -> sombra suave.
fn get_soft_shadow(ro: vec3f, rd: vec3f, tmin: f32, tmax: f32, k: f32) -> f32
{
  var res = 1.0;
  var t = tmin;
  var k_eps = max(k, 0.0001);

  for (var i = 0; i < 128; i = i + 1)
  {
    if (t > tmax)
    {
      break;
    }

    var h = scene(ro + rd * t).w;
    if (h < 0.0001)
    {
      return 0.0;
    }

    res = min(res, h / (k_eps * t));
    t += clamp(h, 0.005, 0.25);
  }

  res = clamp(res, 0.0, 1.0);
  return res * res * (3.0 - 2.0 * res); // smoothstep: penumbra mais bonita
}

fn get_AO(current: vec3f, normal: vec3f) -> f32
{
  var occ = 0.0;
  var sca = 1.0;
  for (var i = 0; i < 5; i = i + 1)
  {
    var h = 0.001 + 0.15 * f32(i) / 4.0;
    var d = scene(current + h * normal).w;
    occ += (h - d) * sca;
    sca *= 0.95;
  }

  return clamp( 1.0 - 2.0 * occ, 0.0, 1.0 ) * (0.5 + 0.5 * normal.y);
}

fn get_ambient_light(light_pos: vec3f, sun_color: vec3f, rd: vec3f) -> vec3f
{
  var backgroundcolor1 = int_to_rgb(i32(uniforms[12]));
  var backgroundcolor2 = int_to_rgb(i32(uniforms[29]));
  var backgroundcolor3 = int_to_rgb(i32(uniforms[30]));

  var ambient = backgroundcolor1 - rd.y * rd.y * 0.5;
  ambient = mix(ambient, 0.85 * backgroundcolor2, pow(1.0 - max(rd.y, 0.0), 4.0));

  var sundot = clamp(dot(rd, normalize(vec3f(light_pos))), 0.0, 1.0);
  var sun = 0.25 * sun_color * pow(sundot, 5.0) + 0.25 * vec3f(1.0,0.8,0.6) * pow(sundot, 64.0) + 0.2 * vec3f(1.0,0.8,0.6) * pow(sundot, 512.0);
  ambient += sun;
  ambient = mix(ambient, 0.68 * backgroundcolor3, pow(1.0 - max(rd.y, 0.0), 16.0));

  return ambient;
}

// =====================================================================
// ILUMINAÇÃO
// difusa (Lambert) * sombra  +  ambiente do céu * AO  +  especular
// =====================================================================
fn get_light(current: vec3f, obj_color: vec3f, rd: vec3f) -> vec3f
{
  var light_position = vec3f(uniforms[13], uniforms[14], uniforms[15]);
  var sun_color = int_to_rgb(i32(uniforms[16]));
  var ambient = get_ambient_light(light_position, sun_color, rd);

  // if the object is too far away from the light source, return ambient light
  // (é aqui que os raios que não acertaram nada viram "céu")
  if (length(current) > uniforms[20] + uniforms[8])
  {
    return ambient;
  }

  var normal = get_normal(current);
  var l = normalize(light_position); // sol = luz direcional

  // difusa: cos do ângulo entre normal e luz
  var diffuse = clamp(dot(normal, l), 0.0, 1.0);

  // sombra: raio da superfície (afastado um pouco pela normal) até o sol
  var shadow = 0.0;
  if (diffuse > 0.0)
  {
    shadow = get_soft_shadow(current + normal * 0.01, l, uniforms[24], uniforms[25], uniforms[21]);
  }

  // oclusão de ambiente: cantos e frestas ficam mais escuros
  var ao = get_AO(current, normal);

  // luz ambiente vinda do céu (cor de fundo)
  var sky = int_to_rgb(i32(uniforms[12]));

  // especular Blinn-Phong (brilho do sol)
  var half_v = normalize(l - rd);
  var spec = pow(clamp(dot(normal, half_v), 0.0, 1.0), 32.0) * diffuse * shadow;

  var lin = sun_color * diffuse * shadow
          + 0.35 * sky * ao
          + 0.05 * ao;

  return obj_color * lin + 0.25 * spec * sun_color;
}

fn set_camera(ro: vec3f, ta: vec3f, cr: f32) -> mat3x3<f32>
{
  var cw = normalize(ta - ro);
  var cp = vec3f(sin(cr), cos(cr), 0.0);
  var cu = normalize(cross(cw, cp));
  var cv = normalize(cross(cu, cw));
  return mat3x3<f32>(cu, cv, cw);
}

// Oscilação senoidal: val = amplitude por eixo, time_scale = velocidade.
fn animate(val: vec3f, time_scale: f32, offset: f32) -> vec3f
{
  var time = uniforms[0];
  return val * sin(time * time_scale + offset);
}

// Roda 1 vez por OBJETO (não por pixel): calcula posição animada e o
// quaternion de rotação e guarda no buffer, para o render só ler.
@compute @workgroup_size(THREAD_COUNT, 1, 1)
fn preprocess(@builtin(global_invocation_id) id : vec3u)
{
  var time = uniforms[0];
  var spheresCount = i32(uniforms[2]);
  var boxesCount = i32(uniforms[3]);
  var torusCount = i32(uniforms[4]);
  var cylindersCount = i32(uniforms[31]);
  var all_objects_count = spheresCount + boxesCount + torusCount + cylindersCount;

  if (id.x >= u32(all_objects_count))
  {
    return;
  }

  var s = shapesb[id.x];

  // posição = posição base + seno animado
  var pos = s.transform.xyz + animate(s.animate_transform.xyz, s.animate_transform.w, 0.0);

  // rotação base em graus (GUI) -> radianos, + rotação animada (radianos)
  var euler = s.rotation.xyz * (PI / 180.0) + animate(s.animate_rotation.xyz, s.animate_rotation.w, 0.0);

  shapesb[id.x].transform_animated = vec4f(pos, 0.0);
  shapesb[id.x].quat = quaternion_from_euler(euler);
}

@compute @workgroup_size(THREAD_COUNT, THREAD_COUNT, 1)
fn render(@builtin(global_invocation_id) id : vec3u)
{
  // unpack data
  var fragCoord = vec2f(f32(id.x), f32(id.y));
  var rez = vec2(uniforms[1]);
  var time = uniforms[0];

  // camera setup
  var lookfrom = vec3(uniforms[6], uniforms[7], uniforms[8]);
  var lookat = vec3(uniforms[9], uniforms[10], uniforms[11]);
  var camera = set_camera(lookfrom, lookat, 0.0);
  var ro = lookfrom;

  // get ray direction
  var uv = (fragCoord - 0.5 * rez) / rez.y;
  uv.y = -uv.y;
  var rd = camera * normalize(vec3(uv, 1.0));

  // 1) marcha o raio  2) ponto atingido  3) ilumina
  var res = march(ro, rd);
  var p = ro + rd * res.depth;
  var color = get_light(p, res.color, rd);

  // névoa leve: objetos muito longe se fundem com o céu (suaviza horizonte)
  if (res.depth < MAX_DIST)
  {
    var sky = get_ambient_light(vec3f(uniforms[13], uniforms[14], uniforms[15]), int_to_rgb(i32(uniforms[16])), rd);
    var fog = 1.0 - exp(-0.0002 * res.depth * res.depth);
    color = mix(color, sky, fog);
  }

  // outline (pós-processamento): pinta a silhueta
  if (uniforms[26] > 0.5 && res.outline)
  {
    color = int_to_rgb(i32(uniforms[28]));
  }

  // display the result
  color = linear_to_gamma(color);
  fb[mapfb(id.xy, uniforms[1])] = vec4(color, 1.0);
}
