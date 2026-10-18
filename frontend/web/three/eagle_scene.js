// EAGLE EYE landing scene — procedural electrical-cabinet digital twin (Three.js r170).
//
// API (window.EagleEyeScene):
//   supported()                       -> bool (WebGL available)
//   mount(container, {reducedMotion})  -> starts rendering into a canvas appended to container
//   unmount(container)                 -> stops and disposes everything
// The container receives a CustomEvent 'eagleeye-scene-status' with detail 'ready' | 'unsupported' | 'error'.
//
// Everything in this scene is an illustrative visualisation; it does not display inspection data.

import * as THREE from './three.module.min.js';

const C = {
  cyan: 0x22d3ee, ice: 0x8bd8ff, violet: 0x8b7cf6, pass: 0x10b981, fail: 0xef4444, amber: 0xf59e0b,
  bg: 0x04070d, steel: 0x8c96a3, graphite: 0x1a212c,
};

function webglSupported() {
  try {
    const c = document.createElement('canvas');
    return !!(window.WebGLRenderingContext && (c.getContext('webgl2') || c.getContext('webgl')));
  } catch (e) {
    return false;
  }
}

function canvasTex(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function labelTex(text, { bg = '#f2f2ee', fg = '#121418', w = 256, h = 96, font = 'bold 56px Inter, Arial, sans-serif', border = '#9aa0a6' } = {}) {
  return canvasTex(w, h, (g) => {
    g.fillStyle = bg; g.fillRect(0, 0, w, h);
    g.strokeStyle = border; g.lineWidth = 4; g.strokeRect(2, 2, w - 4, h - 4);
    g.fillStyle = fg; g.font = font; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(text, w / 2, h / 2 + 3);
  });
}

function annotationTex(title, sub, color) {
  return canvasTex(512, 150, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.fillStyle = 'rgba(6,11,20,0.82)';
    g.strokeStyle = color; g.lineWidth = 3;
    g.beginPath(); g.rect(6, 6, w - 12, h - 12); g.fill(); g.stroke();
    g.fillStyle = color; g.fillRect(6, 6, 10, h - 12);
    g.font = '600 46px "JetBrains Mono", Menlo, monospace'; g.fillStyle = '#e7eef8'; g.textBaseline = 'top';
    g.fillText(title, 34, 22);
    g.font = '500 32px "JetBrains Mono", Menlo, monospace'; g.fillStyle = color;
    g.fillText(sub, 34, 84);
  });
}

function blueprintTex() {
  return canvasTex(1024, 768, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.strokeStyle = 'rgba(139,216,255,0.9)'; g.lineWidth = 2;
    g.strokeRect(20, 20, w - 40, h - 40);
    g.lineWidth = 1.2;
    g.strokeStyle = 'rgba(139,216,255,0.25)';
    for (let x = 40; x < w - 40; x += 32) { g.beginPath(); g.moveTo(x, 30); g.lineTo(x, h - 30); g.stroke(); }
    for (let y = 40; y < h - 40; y += 32) { g.beginPath(); g.moveTo(30, y); g.lineTo(w - 30, y); g.stroke(); }
    g.strokeStyle = 'rgba(34,211,238,0.95)'; g.lineWidth = 2;
    g.setLineDash([10, 6]);
    [[70, 70, 640, 170, 'Z1 PROTECTION'], [70, 300, 280, 190, 'Z2 POWER'], [380, 300, 330, 190, 'Z3 CONTROL'], [70, 540, 470, 150, 'Z4 X12']].forEach(([x, y, ww, hh, t]) => {
      g.strokeRect(x, y, ww, hh);
      g.font = '600 18px "JetBrains Mono", monospace'; g.fillStyle = 'rgba(34,211,238,1)'; g.fillText(t, x + 8, y + 22);
    });
    g.setLineDash([]);
    g.strokeStyle = 'rgba(231,238,248,0.85)'; g.lineWidth = 1.6;
    for (let i = 0; i < 6; i++) g.strokeRect(110 + i * 92, 110, i === 0 ? 70 : 38, 110);
    for (let i = 0; i < 2; i++) g.strokeRect(110 + i * 100, 340, 80, 120);
    for (let i = 0; i < 3; i++) g.strokeRect(420 + i * 96, 350, 60, 100);
    for (let i = 0; i < 12; i++) g.strokeRect(100 + i * 34, 600, 28, 60);
    g.font = '600 13px "JetBrains Mono", monospace'; g.fillStyle = 'rgba(231,238,248,0.9)';
    ['QF01', 'CB41', 'CB42', 'CB43', 'CB44', 'CB45'].forEach((t, i) => g.fillText(t, 112 + i * 92, 104));
    g.strokeStyle = 'rgba(139,124,246,0.8)';
    g.strokeRect(w - 300, h - 120, 260, 80);
    g.fillStyle = 'rgba(139,124,246,0.95)'; g.font = '600 15px "JetBrains Mono", monospace';
    g.fillText('GA DRAWING · CAB-07', w - 288, h - 92); g.fillText('SHEET 1/1  ·  ILLUSTRATIVE', w - 288, h - 64);
  });
}

function ductTex() {
  return canvasTex(512, 64, (g, w, h) => {
    g.fillStyle = '#9aa2ac'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#5a616b';
    for (let x = 4; x < w; x += 18) g.fillRect(x, 6, 6, h - 12);
    g.fillStyle = 'rgba(255,255,255,0.12)'; g.fillRect(0, 0, w, 6);
  });
}

function ventTex() {
  return canvasTex(256, 256, (g, w, h) => {
    g.fillStyle = '#c9ced6'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#3c424c';
    for (let r = 0; r < 6; r++) for (let c = 0; c < 4; c++) g.fillRect(24 + c * 54, 22 + r * 18, 40, 7);
    g.fillStyle = '#2a7d4f'; g.beginPath(); g.arc(220, 160, 8, 0, Math.PI * 2); g.fill();
    g.fillStyle = '#2b2f36'; g.font = 'bold 26px Inter, Arial'; g.fillText('24V DC', 30, 175);
    g.fillStyle = '#2b2f36'; g.fillRect(16, 206, w - 32, 34);
  });
}

class EagleScene {
  constructor(container, opts) {
    this.container = container;
    this.reduced = !!(opts && opts.reducedMotion);
    this.disposables = [];
    this.pointer = new THREE.Vector2(0, 0);
    this.pointerSmooth = new THREE.Vector2(0, 0);
    this.visible = true;
    this.clock = new THREE.Clock();
    this.markers = [];
    this.trails = [];
    this.layers = [[], [], [], []];
  }

  track(o) { this.disposables.push(o); return o; }

  mat(params) { return this.track(new THREE.MeshStandardMaterial(params)); }

  start() {
    const r = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 1.05;
    r.setClearColor(0x000000, 0);
    r.domElement.style.width = '100%';
    r.domElement.style.height = '100%';
    r.domElement.style.display = 'block';
    r.domElement.style.pointerEvents = 'none';
    this.container.appendChild(r.domElement);
    this.renderer = r;

    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(C.bg, 0.055);
    this.scene = scene;
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.1, 100);
    this.camBase = new THREE.Vector3(3.6, 1.15, 7.4);
    this.camTarget = new THREE.Vector3(-0.15, -0.1, 0);

    this.buildEnvironment();
    this.buildCabinet();
    this.buildBlueprint();
    this.buildScan();
    this.buildPointCloud();
    this.buildGround();

    this.onPointer = (e) => {
      this.pointer.set((e.clientX / window.innerWidth) * 2 - 1, -((e.clientY / window.innerHeight) * 2 - 1));
    };
    window.addEventListener('pointermove', this.onPointer, { passive: true });
    this.ro = new ResizeObserver(() => this.resize());
    this.ro.observe(this.container);
    this.io = new IntersectionObserver((entries) => { this.visible = entries.some((e) => e.isIntersecting); });
    this.io.observe(this.container);
    this.onVis = () => { if (!document.hidden) this.clock.getDelta(); };
    document.addEventListener('visibilitychange', this.onVis);
    this.resize();
    this.loop = this.loop.bind(this);
    this.raf = requestAnimationFrame(this.loop);
    this.container.dispatchEvent(new CustomEvent('eagleeye-scene-status', { detail: 'ready' }));
  }

  buildEnvironment() {
    const pm = new THREE.PMREMGenerator(this.renderer);
    const env = new THREE.Scene();
    const room = new THREE.Mesh(new THREE.BoxGeometry(20, 12, 20), new THREE.MeshBasicMaterial({ color: 0x0b111b, side: THREE.BackSide }));
    env.add(room);
    const panel = (color, w, h, x, y, z, ry) => {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide }));
      m.position.set(x, y, z); m.rotation.y = ry; env.add(m);
    };
    panel(0xdff6ff, 6, 3, 0, 4, 6, Math.PI);
    panel(0x9fe9ff, 3, 6, -7, 1, 0, Math.PI / 2);
    panel(0xb7a8ff, 3, 5, 7, 0, -2, -Math.PI / 2);
    panel(0xffffff, 8, 1, 0, 5.8, 0, 0);
    const rt = pm.fromScene(env, 0.04);
    this.scene.environment = rt.texture;
    this.track(rt); this.track(pm);
    env.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });

    this.scene.add(new THREE.HemisphereLight(0x9fdcff, 0x05070c, 0.55));
    const key = new THREE.DirectionalLight(0xe6f6ff, 1.6);
    key.position.set(4, 5, 6); this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x8b7cf6, 1.1);
    rim.position.set(-6, 2, -3); this.scene.add(rim);
    this.scanLight = new THREE.PointLight(C.cyan, 0, 4, 2);
    this.scene.add(this.scanLight);
  }

  box(w, h, d, material, x, y, z, layer = 2, parent = null) {
    const m = new THREE.Mesh(this.track(new THREE.BoxGeometry(w, h, d)), material);
    m.position.set(x, y, z);
    (parent || this.cab).add(m);
    if (layer !== null) this.layers[layer].push({ obj: m, z0: z });
    return m;
  }

  buildCabinet() {
    const cab = new THREE.Group();
    this.cab = cab;
    this.scene.add(cab);
    cab.rotation.y = -0.38;
    const shell = this.mat({ color: C.graphite, metalness: 0.85, roughness: 0.38 });
    const plateM = this.mat({ color: 0xa4adb8, metalness: 0.65, roughness: 0.42 });
    const railM = this.mat({ color: 0xc8ced6, metalness: 0.9, roughness: 0.25 });
    const breakerM = this.mat({ color: 0xebebe6, metalness: 0.05, roughness: 0.55 });
    const darkM = this.mat({ color: 0x2b313b, metalness: 0.2, roughness: 0.5 });
    const contM = this.mat({ color: 0x5b616c, metalness: 0.25, roughness: 0.5 });
    const beigeM = this.mat({ color: 0xcfc39c, metalness: 0.05, roughness: 0.6 });
    const termM = this.mat({ color: 0xd8d2c2, metalness: 0.05, roughness: 0.6 });
    const termBlueM = this.mat({ color: 0x4c7fd6, metalness: 0.05, roughness: 0.6 });
    const copperM = this.mat({ color: 0xc27a3a, metalness: 0.9, roughness: 0.3 });
    const greenM = this.mat({ color: 0x1f8f55, emissive: 0x0b3a22, metalness: 0.1, roughness: 0.5 });
    const dt = this.track(ductTex());
    dt.wrapS = THREE.RepeatWrapping; dt.repeat.set(6, 1);
    const ductM = this.mat({ color: 0xffffff, map: dt, metalness: 0.15, roughness: 0.6 });
    const vt = this.track(ventTex());
    const psuM = this.mat({ color: 0xffffff, map: vt, metalness: 0.55, roughness: 0.35 });
    const psuSide = this.mat({ color: 0xaeb5bf, metalness: 0.7, roughness: 0.3 });

    // enclosure
    const W = 4.6, H = 3.6, D = 0.95;
    this.box(W, H, 0.05, shell, 0, 0, -D / 2, 0);
    this.box(0.08, H, D, shell, -W / 2, 0, 0, 0);
    this.box(0.08, H, D, shell, W / 2, 0, 0, 0);
    this.box(W, 0.08, D, shell, 0, H / 2, 0, 0);
    this.box(W, 0.08, D, shell, 0, -H / 2, 0, 0);
    const lip = this.mat({ color: 0x2a3340, metalness: 0.8, roughness: 0.3 });
    this.box(W + 0.12, 0.06, 0.06, lip, 0, H / 2 + 0.02, D / 2, 0);
    this.box(W + 0.12, 0.06, 0.06, lip, 0, -H / 2 - 0.02, D / 2, 0);
    this.box(0.06, H + 0.1, 0.06, lip, -W / 2 - 0.02, 0, D / 2, 0);
    this.box(0.06, H + 0.1, 0.06, lip, W / 2 + 0.02, 0, D / 2, 0);
    // backplate
    this.box(4.15, 3.15, 0.04, plateM, 0, 0, -0.4, 0);
    const zf = -0.36;
    // rails
    [0.95, -0.05, -0.98].forEach((y) => this.box(3.7, 0.16, 0.05, railM, -0.15, y, zf + 0.04, 1));
    // ducts
    this.box(3.9, 0.24, 0.26, ductM, -0.1, 0.46, zf + 0.13, 1);
    this.box(3.9, 0.24, 0.26, ductM, -0.1, -0.53, zf + 0.13, 1);
    const vduct = this.box(0.26, 2.9, 0.26, this.mat({ color: 0xa2a9b2, metalness: 0.15, roughness: 0.6 }), 1.78, 0, zf + 0.13, 1);
    vduct.userData.static = true;

    this.devices = [];
    const addLabel = (text, x, y, z, layer = 3, opts = {}) => {
      const t = this.track(labelTex(text, opts));
      const m = new THREE.Mesh(this.track(new THREE.PlaneGeometry(opts.pw || 0.24, opts.ph || 0.085)), this.track(new THREE.MeshStandardMaterial({ map: t, roughness: 0.6, metalness: 0.0 })));
      m.position.set(x, y, z);
      this.cab.add(m);
      this.layers[layer].push({ obj: m, z0: z });
      return m;
    };
    // row 1 — breakers
    const row1 = [['QF01', 0.44, 3], ['CB41', 0.17, 1], ['CB42', 0.17, 1], ['CB43', 0.17, 1], ['CB44', 0.17, 1, 'missing'], ['CB45', 0.3, 2]];
    let x = -1.75;
    row1.forEach(([tag, w, poles, state]) => {
      const cx = x + w / 2;
      if (state !== 'missing') {
        const g = this.box(w, 0.62, 0.32, breakerM, cx, 0.95, zf + 0.2, 2);
        for (let p = 0; p < poles; p++) {
          const px = cx - w / 2 + (p + 0.5) * (w / poles);
          this.box(w / poles * 0.42, 0.14, 0.06, darkM, px, 1.02, zf + 0.39, 2);
          this.box(w / poles * 0.36, 0.05, 0.03, greenM, px, 1.06, zf + 0.42, 2);
        }
        this.box(w * 0.9, 0.02, 0.01, this.mat({ color: 0x2a5bb8, metalness: 0.2, roughness: 0.5 }), cx, 0.84, zf + 0.365, 2);
        this.devices.push({ tag, mesh: g, verdict: 'pass', w, h: 0.62, d: 0.32, pos: new THREE.Vector3(cx, 0.95, zf + 0.2) });
      } else {
        this.devices.push({ tag, mesh: null, verdict: 'fail', note: 'MISSING', w, h: 0.62, d: 0.32, pos: new THREE.Vector3(cx, 0.95, zf + 0.2) });
      }
      addLabel(tag, cx, 1.36, zf + 0.05, 3, { pw: Math.max(0.2, w * 0.92), ph: 0.08 });
      x += w + 0.16;
    });
    // row 2 — PSUs and contactors
    [['PS11', -1.62], ['PS12', -1.12, 'PS21']].forEach(([tag, cx, printed]) => {
      const g = this.box(0.42, 0.68, 0.4, psuM, cx, -0.05, zf + 0.24, 2);
      g.material = [psuSide, psuSide, psuSide, psuSide, psuM, psuSide];
      this.devices.push({ tag, mesh: g, verdict: printed ? 'fail' : 'pass', note: printed ? `${printed} ≠ ${tag}` : null, w: 0.42, h: 0.68, d: 0.4, pos: new THREE.Vector3(cx, -0.05, zf + 0.24) });
      addLabel(printed || tag, cx, 0.36, zf + 0.05, 3, { pw: 0.26 });
    });
    [['K1', -0.42], ['K2', 0.02, 'occluded'], ['K3', 0.46]].forEach(([tag, cx, state]) => {
      const g = this.box(0.3, 0.52, 0.34, contM, cx, -0.05, zf + 0.21, 2);
      this.box(0.18, 0.15, 0.04, beigeM, cx, -0.02, zf + 0.4, 2);
      for (let k = 0; k < 3; k++) {
        this.box(0.05, 0.05, 0.03, railM, cx - 0.09 + k * 0.09, 0.15, zf + 0.39, 2);
        this.box(0.05, 0.05, 0.03, railM, cx - 0.09 + k * 0.09, -0.25, zf + 0.39, 2);
      }
      this.devices.push({ tag, mesh: g, verdict: state ? 'uncertain' : 'pass', note: state ? 'UNREADABLE' : null, w: 0.3, h: 0.52, d: 0.34, pos: new THREE.Vector3(cx, -0.05, zf + 0.21) });
      const l = addLabel(tag, cx, 0.3, zf + 0.05, 3, { pw: 0.2 });
      if (state) this.box(0.08, 0.12, 0.02, this.mat({ color: 0x15171b, roughness: 0.4 }), cx - 0.02, 0.3, zf + 0.07, 3);
      void l;
    });
    // relay bank
    for (let i = 0; i < 6; i++) this.box(0.07, 0.42, 0.26, this.mat({ color: i % 2 ? 0x3b4250 : 0x434b59, metalness: 0.2, roughness: 0.55 }), 0.86 + i * 0.09, -0.05, zf + 0.16, 2);
    // row 3 — terminal strip X12 + earth bar
    this.terminals = [];
    const ferr = ['X12-1A', 'X12-2A', 'X12-3A', 'X12-8B', 'X12-5B', 'X12-68', 'X12-7C', 'X12-8C', 'X12-9A', 'X12-10A', 'X12-11A', 'X12-12A'];
    const verd = ['pass', 'pass', 'pass', 'fail', 'pass', 'uncertain', 'pass', 'pass', 'pass', 'pass', 'pass', 'pass'];
    const notes = [null, null, null, 'X12-8B ≠ X12-4B', null, '8 ↔ B confusable', null, null, null, null, null, null];
    for (let i = 0; i < 12; i++) {
      const cx = -1.7 + i * 0.13;
      const blue = i === 10 || i === 11;
      const t = this.box(0.11, 0.42, 0.3, blue ? termBlueM : termM, cx, -1.0, zf + 0.17, 2);
      this.box(0.06, 0.06, 0.02, railM, cx, -0.87, zf + 0.33, 2);
      const fl = addLabel(ferr[i], cx, -0.66, zf + 0.33, 3, { pw: 0.12, ph: 0.05, w: 256, h: 96, font: 'bold 44px "JetBrains Mono", monospace' });
      this.terminals.push({ tag: `X12:${i + 1}`, ferrule: ferr[i], mesh: t, label: fl, verdict: verd[i], note: notes[i], pos: new THREE.Vector3(cx, -0.66, zf + 0.33) });
    }
    addLabel('X12', -1.85, -0.66, zf + 0.06, 3, { bg: '#f1d34a', pw: 0.14, ph: 0.06 });
    this.box(0.9, 0.12, 0.08, copperM, 0.25, -1.05, zf + 0.08, 2);
    for (let i = 0; i < 6; i++) this.box(0.035, 0.035, 0.03, railM, -0.1 + i * 0.14, -1.05, zf + 0.13, 2);
    addLabel('PE', 0.25, -0.87, zf + 0.06, 3, { bg: '#f1d34a', pw: 0.12, ph: 0.06 });
    // wires
    this.buildWires(zf);
  }

  buildWires(zf) {
    const cols = [0x7a4a2a, 0x2654c4, 0x1c1c1e, 0x808286, 0xc42826];
    const wireMats = cols.map((c) => this.mat({ color: c, metalness: 0.1, roughness: 0.45 }));
    const geTube = (pts, mat) => {
      const curve = new THREE.CatmullRomCurve3(pts.map((p) => new THREE.Vector3(...p)));
      const m = new THREE.Mesh(this.track(new THREE.TubeGeometry(curve, 48, 0.012, 6, false)), mat);
      this.cab.add(m);
      this.layers[2].push({ obj: m, z0: 0 });
      return curve;
    };
    const curves = [];
    this.devices.filter((d) => d.mesh).forEach((d, i) => {
      if (d.pos.y > 0.5) {
        curves.push(geTube([[d.pos.x, d.pos.y - 0.3, zf + 0.22], [d.pos.x + 0.01, d.pos.y - 0.4, zf + 0.25], [d.pos.x, 0.6, zf + 0.22]], wireMats[i % 5]));
      } else {
        curves.push(geTube([[d.pos.x, d.pos.y - d.h / 2, zf + 0.22], [d.pos.x - 0.02, -0.35, zf + 0.25], [d.pos.x, -0.4, zf + 0.22]], wireMats[(i + 2) % 5]));
      }
    });
    this.terminals.forEach((t, i) => {
      curves.push(geTube([[t.pos.x, -0.66, zf + 0.3], [t.pos.x + 0.005, -0.72, zf + 0.29], [t.pos.x, -0.82, zf + 0.25]], wireMats[[0, 1, 2, 0, 1, 3, 1, 2, 0, 1, 1, 1][i]]));
      curves.push(geTube([[t.pos.x, -0.65, zf + 0.33], [t.pos.x, -0.6, zf + 0.3], [t.pos.x, -0.66 + 0.03, zf + 0.22]], wireMats[[0, 1, 2, 0, 1, 3, 1, 2, 0, 1, 1, 1][i]]));
    });
    // earth wires
    const gy = this.mat({ color: 0x5aa83e, metalness: 0.1, roughness: 0.45 });
    for (let k = 0; k < 3; k++) curves.push(geTube([[0.05 + k * 0.18, -0.65, zf + 0.22], [0.06 + k * 0.18, -0.85, zf + 0.2], [0.05 + k * 0.18, -1.02, zf + 0.12]], gy));
    // signal trails along a subset of wires
    const glowTex = this.track(canvasTex(64, 64, (g, w, h) => {
      const gr = g.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2);
      gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(34,211,238,0.9)'); gr.addColorStop(1, 'rgba(34,211,238,0)');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
    }));
    this.glowTex = glowTex;
    curves.filter((_, i) => i % 3 === 0).slice(0, 9).forEach((curve, i) => {
      const sm = this.track(new THREE.SpriteMaterial({ map: glowTex, color: i % 4 === 0 ? C.violet : C.cyan, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
      const s = new THREE.Sprite(sm);
      s.scale.set(0.09, 0.09, 1);
      this.cab.add(s);
      this.trails.push({ curve, sprite: s, speed: 0.18 + (i % 4) * 0.06, offset: i * 0.37 });
    });
  }

  buildBlueprint() {
    const tex = this.track(blueprintTex());
    const mat = this.track(new THREE.MeshBasicMaterial({ map: tex, transparent: true, opacity: 0.55, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
    const plane = new THREE.Mesh(this.track(new THREE.PlaneGeometry(4.2, 3.15)), mat);
    this.blueprint = plane;
    this.bpFrom = { pos: new THREE.Vector3(-2.6, 0.45, -1.9), rot: new THREE.Euler(0.04, 0.42, -0.03) };
    this.bpTo = { pos: new THREE.Vector3(0, 0, 0.5), rot: new THREE.Euler(0, 0, 0) };
    this.scene.add(plane);
    // alignment correspondence lines (drawing corners -> cabinet corners)
    const lineMat = this.track(new THREE.LineBasicMaterial({ color: C.ice, transparent: true, opacity: 0 }));
    this.corrMat = lineMat;
    this.corrGeo = this.track(new THREE.BufferGeometry());
    this.corrGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(8 * 3), 3));
    this.corr = new THREE.LineSegments(this.corrGeo, lineMat);
    this.scene.add(this.corr);
    // measurement markers
    const dimMat = this.track(new THREE.LineBasicMaterial({ color: C.ice, transparent: true, opacity: 0.55 }));
    const pts = [];
    const L = -2.55, T = 1.58, B = -1.58;
    pts.push(L, T, 0.5, L, B, 0.5, L - 0.06, T, 0.5, L + 0.06, T, 0.5, L - 0.06, B, 0.5, L + 0.06, B, 0.5);
    pts.push(-2.08, 1.95, 0.5, 2.08, 1.95, 0.5, -2.08, 1.89, 0.5, -2.08, 2.01, 0.5, 2.08, 1.89, 0.5, 2.08, 2.01, 0.5);
    const dg = this.track(new THREE.BufferGeometry());
    dg.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    const dims = new THREE.LineSegments(dg, dimMat);
    this.cab.add(dims);
    const mk = (text, x, y) => {
      const t = this.track(canvasTex(256, 64, (g, w, h) => { g.font = '600 30px "JetBrains Mono", monospace'; g.fillStyle = '#8bd8ff'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(text, w / 2, h / 2); }));
      const s = new THREE.Sprite(this.track(new THREE.SpriteMaterial({ map: t, transparent: true, depthWrite: false })));
      s.scale.set(0.62, 0.155, 1); s.position.set(x, y, 0.5); this.cab.add(s);
    };
    mk('800 mm', 0, 2.1);
    mk('600 mm', -2.92, 0);
  }

  buildScan() {
    const curtain = this.track(new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      uniforms: { uColor: { value: new THREE.Color(C.cyan) }, uAlpha: { value: 1 } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: 'uniform vec3 uColor; uniform float uAlpha; varying vec2 vUv; void main(){ float d = abs(vUv.y-0.5); float a = exp(-d*d/0.0035)*0.55 + exp(-d*d/0.00012)*0.9; float edge = smoothstep(0.0,0.06,vUv.x)*smoothstep(1.0,0.94,vUv.x); gl_FragColor = vec4(uColor, a*edge*uAlpha); }',
    }));
    const scan = new THREE.Mesh(this.track(new THREE.PlaneGeometry(4.5, 0.5)), curtain);
    scan.position.set(0, 0, 0.5);
    this.cab.add(scan);
    this.scanMesh = scan;
    this.scanMat = curtain;
    const sheet = this.track(new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      uniforms: { uColor: { value: new THREE.Color(C.cyan) } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: 'uniform vec3 uColor; varying vec2 vUv; void main(){ float a = (1.0-vUv.y)*0.22*smoothstep(0.0,0.08,vUv.x)*smoothstep(1.0,0.92,vUv.x); gl_FragColor = vec4(uColor,a); }',
    }));
    const sh = new THREE.Mesh(this.track(new THREE.PlaneGeometry(4.5, 0.95)), sheet);
    sh.rotation.x = -Math.PI / 2;
    sh.position.set(0, 0, 0.02);
    this.cab.add(sh);
    this.scanSheet = sh;
    // bounding boxes + annotations for each inspected item
    const colorFor = (v) => (v === 'fail' ? C.fail : v === 'uncertain' ? C.amber : C.pass);
    const items = [
      ...this.devices.map((d) => ({ y: d.pos.y, center: d.pos.clone(), size: new THREE.Vector3(d.w + 0.05, d.h + 0.05, d.d + 0.05), verdict: d.verdict, tag: d.tag, note: d.note, layer: 2 })),
      ...this.terminals.map((t) => ({ y: t.pos.y, center: t.pos.clone(), size: new THREE.Vector3(0.135, 0.075, 0.05), verdict: t.verdict, tag: t.tag, note: t.note, layer: 3 })),
    ];
    items.forEach((it) => {
      const g = this.track(new THREE.EdgesGeometry(this.track(new THREE.BoxGeometry(it.size.x, it.size.y, it.size.z))));
      const m = this.track(new THREE.LineBasicMaterial({ color: colorFor(it.verdict), transparent: true, opacity: 0 }));
      const ls = new THREE.LineSegments(g, m);
      ls.position.copy(it.center);
      this.cab.add(ls);
      let sprite = null;
      if (it.note) {
        const tex = this.track(annotationTex(it.tag, it.note, it.verdict === 'fail' ? '#ef4444' : '#f59e0b'));
        sprite = new THREE.Sprite(this.track(new THREE.SpriteMaterial({ map: tex, transparent: true, opacity: 0, depthWrite: false, depthTest: false })));
        sprite.scale.set(0.95, 0.28, 1);
        sprite.position.copy(it.center).add(new THREE.Vector3(0.5, 0.32, 0.45));
        sprite.renderOrder = 10;
        this.cab.add(sprite);
      }
      this.markers.push({ ...it, lines: ls, mat: m, sprite, heat: 0 });
    });
  }

  buildPointCloud() {
    const pts = [];
    const tmp = [];
    const pushFace = (cx, cy, z, w, h, n) => { for (let i = 0; i < n; i++) tmp.push([cx + (Math.random() - 0.5) * w, cy + (Math.random() - 0.5) * h, z]); };
    this.devices.forEach((d) => d.mesh && pushFace(d.pos.x, d.pos.y, d.pos.z + d.d / 2 + 0.005, d.w, d.h, 90));
    this.terminals.forEach((t) => pushFace(t.pos.x, -1.0, -0.36 + 0.33, 0.1, 0.4, 25));
    pushFace(0, 0, -0.37, 4.0, 3.0, 900);
    tmp.forEach((p) => pts.push(...p));
    const g = this.track(new THREE.BufferGeometry());
    g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    const alpha = new Float32Array(tmp.length);
    g.setAttribute('aAlpha', new THREE.BufferAttribute(alpha, 1));
    const m = this.track(new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
      uniforms: { uColor: { value: new THREE.Color(C.ice) }, uSize: { value: 2.2 * Math.min(window.devicePixelRatio || 1, 1.75) } },
      vertexShader: 'attribute float aAlpha; varying float vA; uniform float uSize; void main(){ vA = aAlpha; vec4 mv = modelViewMatrix*vec4(position,1.0); gl_PointSize = uSize; gl_Position = projectionMatrix*mv; }',
      fragmentShader: 'uniform vec3 uColor; varying float vA; void main(){ vec2 c = gl_PointCoord-0.5; if(dot(c,c)>0.25) discard; gl_FragColor = vec4(uColor, vA*0.85); }',
    }));
    this.cloud = new THREE.Points(g, m);
    this.cloudY = tmp.map((p) => p[1]);
    this.cloudAlpha = alpha;
    this.cab.add(this.cloud);
  }

  buildGround() {
    const grid = new THREE.GridHelper(60, 120, 0x1d4a66, 0x0f2233);
    grid.position.y = -2.05;
    grid.material.transparent = true;
    grid.material.opacity = 0.55;
    this.track(grid.geometry); this.track(grid.material);
    this.scene.add(grid);
    const glow = new THREE.Mesh(this.track(new THREE.CircleGeometry(3.2, 48)), this.track(new THREE.MeshBasicMaterial({ map: this.glowTex, color: C.cyan, transparent: true, opacity: 0.25, depthWrite: false, blending: THREE.AdditiveBlending })));
    glow.rotation.x = -Math.PI / 2;
    glow.position.y = -2.04;
    this.scene.add(glow);
  }

  resize() {
    const w = this.container.clientWidth, h = this.container.clientHeight;
    if (!w || !h) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.fov = w / h < 1 ? 42 : 30;
    this.camera.updateProjectionMatrix();
    if (this.reduced) this.renderStatic();
  }

  renderStatic() {
    this.update(6.2, true);
    this.renderer.render(this.scene, this.camera);
  }

  update(t, frozen = false) {
    const ease = (x) => x * x * (3 - 2 * x);
    // camera: slow orbit + pointer parallax
    this.pointerSmooth.lerp(this.pointer, frozen ? 1 : 0.04);
    const yaw = frozen ? 0 : Math.sin(t * 0.26) * 0.1;
    const p = this.camBase.clone();
    p.applyAxisAngle(new THREE.Vector3(0, 1, 0), yaw + this.pointerSmooth.x * 0.16);
    p.y += this.pointerSmooth.y * 0.45;
    this.camera.position.copy(p);
    this.camera.lookAt(this.camTarget);
    // exploded view cycle (16 s): assembled -> exploded -> assembled
    const cyc = (t % 16) / 16;
    let ex = 0;
    if (!frozen) {
      if (cyc > 0.55 && cyc < 0.68) ex = ease((cyc - 0.55) / 0.13);
      else if (cyc >= 0.68 && cyc < 0.8) ex = 1;
      else if (cyc >= 0.8 && cyc < 0.93) ex = 1 - ease((cyc - 0.8) / 0.13);
    }
    const spread = [0, 0.08, 0.26, 0.42];
    this.layers.forEach((layer, li) => layer.forEach((o) => { if (!o.obj.userData.static) o.obj.position.z = o.z0 + spread[li] * ex; }));
    this.cloud.position.z = spread[2] * ex;
    // scan: sweeps top -> bottom every 7 s
    const sp = frozen ? 0.62 : (t % 7) / 7;
    const sy = 1.65 - sp * 3.3;
    this.scanMesh.position.y = sy;
    this.scanSheet.position.y = sy;
    this.scanMat.uniforms.uAlpha.value = frozen ? 0.6 : Math.min(1, Math.min(sp, 1 - sp) * 12);
    const wp = new THREE.Vector3(0, sy, 0.3).applyMatrix4(this.cab.matrixWorld);
    this.scanLight.position.copy(wp);
    this.scanLight.intensity = frozen ? 0 : 2.2;
    // markers light up as the scan passes
    this.markers.forEach((m) => {
      if (frozen) m.heat = m.verdict === 'pass' ? 0.35 : 1;
      else if (Math.abs(sy - m.y) < 0.06) m.heat = 1;
      else m.heat = Math.max(0, m.heat - (m.verdict === 'pass' ? 0.012 : 0.006));
      m.lines.position.z = m.center.z + spread[m.layer] * ex;
      if (m.sprite) m.sprite.position.z = m.center.z + 0.45 + spread[m.layer] * ex;
      m.mat.opacity = m.heat * (m.verdict === 'pass' ? 0.75 : 1);
      if (m.sprite) m.sprite.material.opacity = Math.min(1, m.heat * 1.4);
    });
    // point cloud capture
    if (this.cloudAlpha) {
      for (let i = 0; i < this.cloudAlpha.length; i++) {
        const d = this.cloudY[i] - sy;
        if (frozen) this.cloudAlpha[i] = 0.25;
        else if (d > -0.02 && d < 0.05) this.cloudAlpha[i] = 1;
        else this.cloudAlpha[i] = Math.max(0, this.cloudAlpha[i] - 0.006);
      }
      this.cloud.geometry.attributes.aAlpha.needsUpdate = true;
    }
    // trails
    this.trails.forEach((tr) => {
      const u = frozen ? 0.5 : (t * tr.speed + tr.offset) % 1;
      tr.sprite.position.copy(tr.curve.getPointAt(u));
      tr.sprite.position.z += 0.02 + spread[2] * ex;
      tr.sprite.material.opacity = frozen ? 0 : Math.sin(u * Math.PI);
    });
    // blueprint alignment cycle (14 s)
    const bc = frozen ? 0.5 : (t % 14) / 14;
    let a = 0;
    if (bc > 0.3 && bc < 0.45) a = ease((bc - 0.3) / 0.15);
    else if (bc >= 0.45 && bc < 0.72) a = 1;
    else if (bc >= 0.72 && bc < 0.86) a = 1 - ease((bc - 0.72) / 0.14);
    const to = this.bpTo.pos.clone().applyMatrix4(this.cab.matrixWorld);
    const qTo = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, this.cab.rotation.y, 0));
    const qFrom = new THREE.Quaternion().setFromEuler(this.bpFrom.rot);
    this.blueprint.position.lerpVectors(this.bpFrom.pos, to, a);
    this.blueprint.quaternion.slerpQuaternions(qFrom, qTo, a);
    this.blueprint.material.opacity = 0.42 - 0.22 * a;
    // correspondence lines visible while aligning
    const corners = [[-2.1, 1.575], [2.1, 1.575], [2.1, -1.575], [-2.1, -1.575]];
    const arr = this.corrGeo.attributes.position.array;
    corners.forEach(([cx, cy], i) => {
      const from = new THREE.Vector3(cx, cy, 0).applyMatrix4(this.blueprint.matrixWorld);
      const tgt = new THREE.Vector3(cx * 0.98, cy * 0.98, 0.48).applyMatrix4(this.cab.matrixWorld);
      arr.set([from.x, from.y, from.z, tgt.x, tgt.y, tgt.z], i * 6);
    });
    this.corrGeo.attributes.position.needsUpdate = true;
    this.corrMat.opacity = frozen ? 0.25 : (a > 0 && a < 1 ? 0.7 : (a === 1 ? 0.35 : 0));
  }

  loop() {
    this.raf = requestAnimationFrame(this.loop);
    if (this.reduced || !this.visible || document.hidden) return;
    const t = this.clock.getElapsedTime();
    this.cab.updateMatrixWorld();
    this.blueprint.updateMatrixWorld();
    this.update(t);
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    cancelAnimationFrame(this.raf);
    window.removeEventListener('pointermove', this.onPointer);
    document.removeEventListener('visibilitychange', this.onVis);
    if (this.ro) this.ro.disconnect();
    if (this.io) this.io.disconnect();
    this.disposables.forEach((d) => { try { d.dispose(); } catch (e) { /* ignore */ } });
    if (this.renderer) {
      this.renderer.dispose();
      this.renderer.forceContextLoss();
      this.renderer.domElement.remove();
    }
  }
}

const instances = new WeakMap();

window.EagleEyeScene = {
  supported: webglSupported,
  mount(container, opts) {
    if (!container || instances.has(container)) return;
    if (!webglSupported()) {
      container.dispatchEvent(new CustomEvent('eagleeye-scene-status', { detail: 'unsupported' }));
      return;
    }
    try {
      const s = new EagleScene(container, opts || {});
      instances.set(container, s);
      s.start();
      if (s.reduced) { s.cab.updateMatrixWorld(); s.blueprint.updateMatrixWorld(); s.renderStatic(); }
    } catch (e) {
      console.error('EAGLE EYE scene failed', e);
      container.dispatchEvent(new CustomEvent('eagleeye-scene-status', { detail: 'error' }));
    }
  },
  unmount(container) {
    const s = instances.get(container);
    if (s) { s.dispose(); instances.delete(container); }
  },
};

// drain mounts requested before this module finished loading
(window.__eeSceneQueue || []).splice(0).forEach(([el, o]) => window.EagleEyeScene.mount(el, o));
