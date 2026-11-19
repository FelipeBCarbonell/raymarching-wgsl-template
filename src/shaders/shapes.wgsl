// =====================================================================
// SDFs (Signed Distance Functions)
// Cada função recebe um ponto p já no espaço local do objeto (posição
// subtraída) e devolve a distância com sinal até a superfície:
//   d > 0 -> fora, d = 0 -> na superfície, d < 0 -> dentro.
// A rotação é aplicada aqui: para girar o objeto por q, giramos o ponto
// pelo inverso de q (conjugado, pois q é unitário) e avaliamos a forma
// "parada".
// =====================================================================

fn to_local(p: vec3f, quat: vec4f) -> vec3f
{
  return rotate_vector(p, q_conjugate(quat));
}

// Caixa com cantos arredondados.
// b = meia-extensão em cada eixo, r = raio do arredondamento.
fn sdf_round_box(p: vec3f, b: vec3f, r: f32, quat: vec4f) -> f32
{
  var lp = to_local(p, quat);
  var q = abs(lp) - b;                       // simetria: só olho o 1º octante
  var outside = length(max(q, vec3f(0.0)));  // distância quando está fora
  var inside = min(max(q.x, max(q.y, q.z)), 0.0); // negativo quando está dentro
  return outside + inside - r;               // "infla" a caixa por r
}

// Esfera (generalizada para elipsoide).
// r.xyz = escala por eixo, r.w = raio global. Com escala (1,1,1) é
// exatamente length(p) - r.w.
fn sdf_sphere(p: vec3f, r: vec4f, quat: vec4f) -> f32
{
  var lp = to_local(p, quat);
  var radii = max(abs(r.xyz * r.w), vec3f(0.0001));

  // esfera perfeita: SDF exato
  if (radii.x == radii.y && radii.y == radii.z)
  {
    return length(lp) - radii.x;
  }

  // elipsoide: aproximação de Inigo Quilez
  var k0 = length(lp / radii);
  var k1 = max(length(lp / (radii * radii)), 0.0001);
  return k0 * (k0 - 1.0) / k1;
}

// Toro deitado no plano XZ.
// r.x = raio maior (centro até o meio do tubo), r.y = raio do tubo.
fn sdf_torus(p: vec3f, r: vec2f, quat: vec4f) -> f32
{
  var lp = to_local(p, quat);
  // distância no plano XZ até o círculo central, combinada com a altura
  var q = vec2f(length(lp.xz) - r.x, lp.y);
  return length(q) - r.y;
}

// NOVA PRIMITIVA: cilindro com tampas (e bordas arredondadas), eixo Y.
// r = raio, h = meia-altura, rb = arredondamento da borda.
// Ideia: em coordenadas (distância radial, altura) o cilindro vira um
// retângulo 2D, então uso o mesmo truque do box em 2D.
fn sdf_cylinder(p: vec3f, r: f32, h: f32, rb: f32, quat: vec4f) -> f32
{
  var lp = to_local(p, quat);
  var d = vec2f(length(lp.xz) - r, abs(lp.y) - h);
  var outside = length(max(d, vec2f(0.0)));
  var inside = min(max(d.x, d.y), 0.0);
  return outside + inside - rb;
}

fn sdf_mandelbulb(p: vec3f) -> vec2f
{
  var w = p;
  var m = dot(w, w);

  var dz = 1.0;
  var i = 0;

  for (i = 0; i < 15; i = i + 1)
  {
    dz = 8.0 * pow(sqrt(m), 7.0) * dz + 1.0;
    var r = length(w);
    var b = 8.0 * acos(w.y / r);
    var a = 8.0 * atan2(w.x, w.z);
    w = p + pow(r, 8.0) * vec3f(sin(b) * sin(a), cos(b), sin(b) * cos(a));

    m = dot(w, w);
    if (m > 256.0)
    {
      break;
    }
  }
  var r = 0.25 * log(m) * sqrt(m) / dz;
  return vec2f(r, f32(i) / 16.0);
}

fn sdf_weird_thing(p_: vec3f, s: f32) -> f32
{
  var scale = 1.0;
  var orb = vec4f(1000.0);
  var p = p_;

  for (var i = 0; i < 8; i = i + 1)
  {
    p = -1.0 + 2.0 * modc(0.5 * p + 0.5, vec3f(1.0));

    var r2 = dot(p, p);
    orb = min(orb, vec4f(abs(p), r2));

    var k = s / r2;
    p *= k;
    scale *= k;
  }

  return 0.3 * abs(p.y) / scale;
}
