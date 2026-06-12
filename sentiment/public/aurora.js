// Steady Sentiment -- subscribe to /events (SSE) and drive the aurora.
//
// The shader gets a handful of smoothed uniforms: the headline score sets
// how bright and soft the sky is, energy (fragment disagreement) sets the
// turbulence and speed, the emotion mix picks the palette, and blocked
// check-ins send a red shockwave through the field every few seconds.

const EMOTION_COLORS = {
  joy: [1.0, 0.72, 0.3],
  surprise: [0.93, 0.45, 0.8],
  neutral: [0.36, 0.81, 0.79], // Steady teal; doubles as classic aurora green
  sadness: [0.25, 0.45, 0.95],
  fear: [0.6, 0.4, 0.95],
  anger: [0.95, 0.25, 0.35],
  disgust: [0.6, 0.8, 0.25],
};

// --- WebGL ----------------------------------------------------------------

const canvas = document.getElementById("aurora");
const gl = canvas.getContext("webgl", { antialias: false, depth: false });

const FRAGMENT_SHADER = `
precision highp float;
uniform vec2 u_res;
uniform float u_time;
uniform float u_score;   // -1..1  headline sentiment
uniform float u_energy;  //  0..1  fragment disagreement
uniform float u_pulse;   //  0..1  blocked intensity
uniform vec3 u_colA;     // palette: top three emotions...
uniform vec3 u_colB;
uniform vec3 u_colC;
uniform vec3 u_weights;  // ...and their normalized shares

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
             mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = p * 2.03 + 17.7;
    a *= 0.55;
  }
  return v;
}

// Blend the three emotion colors along a noise field, proportioned by
// their share of the mix.
vec3 palette(float x) {
  float a = u_weights.x;
  float ab = u_weights.x + u_weights.y;
  vec3 col = mix(u_colA, u_colB, smoothstep(a - 0.18, a + 0.18, x));
  return mix(col, u_colC, smoothstep(ab - 0.18, ab + 0.18, x));
}

void main() {
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_res) / u_res.y;
  float t = u_time;

  float lift = 0.5 + 0.5 * u_score;                              // 0 stormy .. 1 radiant
  float turb = 0.5 + 1.1 * u_energy + 0.5 * max(0.0, -u_score);  // negative days churn
  float speed = 1.0 + 1.6 * u_energy + 0.8 * max(0.0, -u_score);

  // Blocked shockwave: an expanding ring every few seconds that also
  // warps the sky it passes through.
  float cycle = fract(t / 7.0);
  float ring = exp(-pow((length(uv) - cycle * 1.7) / 0.10, 2.0)) * (1.0 - cycle) * u_pulse;
  uv += normalize(uv + 1e-4) * ring * 0.04;

  // Night sky, dimming as sentiment drops.
  vec3 col = mix(vec3(0.010, 0.012, 0.030), vec3(0.035, 0.030, 0.075), uv.y + 0.55);
  col *= 0.65 + 0.55 * lift;

  // Stars.
  vec2 cell = floor(gl_FragCoord.xy / 2.0);
  float twinkle = 0.5 + 0.5 * sin(t * 2.0 + hash(cell.yx) * 40.0);
  col += step(0.9985, hash(cell)) * (0.35 + 0.65 * twinkle) * (0.25 + 0.3 * lift);

  // Three aurora curtains.
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float drift = t * 0.03 * speed * (1.0 + 0.35 * fi);
    float y0 = mix(-0.22, 0.34, fi / 2.0);
    float wob = fbm(vec2(uv.x * (1.1 + 0.4 * fi) + drift, 7.3 * fi)) - 0.5;
    float y = y0 + wob * (0.5 + 0.55 * turb);

    // Soft and tall when bright, thin and sharp when heavy.
    float glow = exp(-abs(uv.y - y) * mix(9.0, 4.5, lift));
    glow *= 0.45 + 0.55 * fbm(vec2(uv.x * 2.6 - drift * 1.8, fi * 11.1 + t * 0.05 * speed));
    glow *= 0.55 + 0.75 * fbm(vec2(uv.x * (6.0 + 3.0 * turb) + drift * 2.4, uv.y * 1.8));

    vec3 tint = palette(fbm(vec2(uv.x * 0.7 + fi * 3.17 + t * 0.02 * speed, fi * 5.0)));
    col += tint * glow * (0.62 - 0.14 * fi) * (0.55 + 0.65 * lift);
  }

  col += vec3(0.90, 0.10, 0.18) * ring * 1.2;

  col *= 1.0 - 0.45 * dot(uv, uv); // vignette
  col = 1.0 - exp(-col * 1.7);     // soft rolloff
  gl_FragColor = vec4(col, 1.0);
}
`;

let uniforms = null;

if (gl) {
  const compile = (type, source) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(shader));
    }
    return shader;
  };

  const program = gl.createProgram();
  gl.attachShader(program, compile(gl.VERTEX_SHADER, "attribute vec2 p; void main() { gl_Position = vec4(p, 0.0, 1.0); }"));
  gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT_SHADER));
  gl.linkProgram(program);
  gl.useProgram(program);

  // One triangle that covers the screen.
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const p = gl.getAttribLocation(program, "p");
  gl.enableVertexAttribArray(p);
  gl.vertexAttribPointer(p, 2, gl.FLOAT, false, 0, 0);

  uniforms = Object.fromEntries(
    ["u_res", "u_time", "u_score", "u_energy", "u_pulse", "u_colA", "u_colB", "u_colC", "u_weights"].map(
      (name) => [name, gl.getUniformLocation(program, name)],
    ),
  );
}

function resize() {
  // Cap the backing store: a wall display doesn't need retina noise fields.
  const scale = Math.min(window.devicePixelRatio || 1, 1.5);
  canvas.width = Math.round(canvas.clientWidth * scale);
  canvas.height = Math.round(canvas.clientHeight * scale);
  gl?.viewport(0, 0, canvas.width, canvas.height);
}
window.addEventListener("resize", resize);
resize();

// The shader state eases toward whatever the latest snapshot says, so a
// new score is a slow change in the weather, not a scene cut.
const state = {
  score: 0,
  energy: 0.25,
  pulse: 0,
  colA: EMOTION_COLORS.neutral.slice(),
  colB: EMOTION_COLORS.neutral.slice(),
  colC: EMOTION_COLORS.neutral.slice(),
  weights: [1, 0, 0],
};
const target = structuredClone(state);

function tick(now) {
  requestAnimationFrame(tick);
  if (!gl) return;

  const k = 0.02; // ~1-2s ease at 60fps
  for (const key of ["score", "energy", "pulse"]) state[key] += (target[key] - state[key]) * k;
  for (const key of ["colA", "colB", "colC", "weights"]) {
    state[key] = state[key].map((v, i) => v + (target[key][i] - v) * k);
  }

  gl.uniform2f(uniforms.u_res, canvas.width, canvas.height);
  gl.uniform1f(uniforms.u_time, now / 1000);
  gl.uniform1f(uniforms.u_score, state.score);
  gl.uniform1f(uniforms.u_energy, state.energy);
  gl.uniform1f(uniforms.u_pulse, state.pulse);
  gl.uniform3fv(uniforms.u_colA, state.colA);
  gl.uniform3fv(uniforms.u_colB, state.colB);
  gl.uniform3fv(uniforms.u_colC, state.colC);
  gl.uniform3fv(uniforms.u_weights, state.weights);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}
requestAnimationFrame(tick);

// --- data -> uniforms + footer ---------------------------------------------

const els = Object.fromEntries(
  ["score", "label", "emotions", "blocked", "summary", "quotes", "live", "message", "teams", "models", "updated-at"].map(
    (id) => [id, document.getElementById(id)],
  ),
);

const fmt = (score) => `${score > 0 ? "+" : ""}${(score ?? 0).toFixed(2)}`;

function topEmotions(emotions) {
  return Object.entries(emotions || { neutral: 1 })
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3);
}

function applySnapshot(data) {
  if (data.updated_at === undefined) return; // nothing scored yet, footer-only update

  target.score = data.score ?? 0;
  target.energy = data.energy ?? 0.25;
  target.pulse = data.blocked_count ? Math.min(1, 0.4 + 0.2 * data.blocked_count) : 0;

  const top = topEmotions(data.emotions);
  const total = top.reduce((sum, [, share]) => sum + share, 0) || 1;
  ["colA", "colB", "colC"].forEach((key, i) => {
    const [emotion] = top[Math.min(i, top.length - 1)];
    target[key] = (EMOTION_COLORS[emotion] || EMOTION_COLORS.neutral).slice();
  });
  target.weights = [0, 1, 2].map((i) => (top[i]?.[1] ?? 0) / total);

  els.score.textContent = fmt(data.score);
  els.label.textContent = data.label || "";
  els.emotions.innerHTML = "";
  for (const [emotion, share] of top) {
    const chip = document.createElement("span");
    chip.className = `chip emotion-${emotion}`;
    chip.textContent = `${emotion} ${Math.round(share * 100)}%`;
    els.emotions.appendChild(chip);
  }
  els.blocked.hidden = !data.blocked_count;
  els.blocked.textContent = data.blocked_count ? `⚠ ${data.blocked_count} blocked` : "";
  els.summary.textContent = data.summary || "";

  els.quotes.innerHTML = "";
  const quote = (mark, highlight) => {
    if (!highlight) return;
    const span = document.createElement("span");
    span.className = "quote";
    span.textContent = `${mark} “${highlight.text}” — ${highlight.person}`;
    els.quotes.appendChild(span);
  };
  quote("☀", data.highlights?.brightest);
  quote("☁", data.highlights?.heaviest);
}

const source = new EventSource("/events");

source.onmessage = (event) => {
  const data = JSON.parse(event.data);
  applySnapshot(data);

  els.message.textContent = data.error || "";
  els.live.classList.toggle("error", Boolean(data.error));
  els.teams.textContent = data.error ? "" : `${(data.teams || []).join(", ")} · ${data.date || ""}`;
  if (data.models) {
    els.models.textContent = "distilbert sst-2 + distilroberta emotion · on-CPU, no LLMs";
  }
  if (data.updated_at) {
    const time = new Date(data.updated_at).toLocaleTimeString([], {
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
    });
    els["updated-at"].textContent = `Updated ${time}`;
  }
};

source.onerror = () => {
  els.message.textContent = "Reconnecting…";
  els.live.classList.add("error");
};

source.onopen = () => {
  els.live.classList.remove("error");
};

// Double-click anywhere to toggle fullscreen -- handy on wall displays
// where launching the browser in kiosk mode isn't an option.
document.addEventListener("dblclick", () => {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.documentElement.requestFullscreen();
});

if (!gl) {
  els.summary.textContent = "WebGL isn't available in this browser — the readout below still works.";
}
