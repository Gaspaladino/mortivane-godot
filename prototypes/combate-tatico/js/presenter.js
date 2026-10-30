// =====================================================================
// APRESENTAÇÃO — câmera, animações, efeitos. Apenas REPRODUZ os
// confrontos já resolvidos pela lógica (combat.js). Velocidade e
// "pular" alteram somente o tempo, nunca o resultado.
// =====================================================================
(function (G) {
  'use strict';
  const W = 1280, H = 720, GROUND = 560;
  const HOME = {
    knight: { x: 445, y: 580 }, swordsman: { x: 315, y: 618 }, mage: { x: 185, y: 560 },
    brute: { x: 835, y: 580 }, duelist: { x: 965, y: 618 }, conjurer: { x: 1095, y: 560 },
  };
  // Posições de formação dos aliados por posição na equipe (0 = frente, 2 = retaguarda)
  const ALLY_SLOTS = [{ x: 445, y: 580 }, { x: 315, y: 618 }, { x: 185, y: 560 }];
  const BG_M = { x: 520, y: 320 }; // o cenário se estende além da arena (sem bordas pretas)
  const isRanged = sk => sk.tags.includes('magic') || sk.tags.includes('ranged');
  const SFX = (n, o) => G.SFX && G.SFX.play(n, o);
  // Área de combate (mundo) e regras de espaçamento
  const ARENA = { minX: 90, maxX: 1190, minY: 545, maxY: 640 };
    const FRONT = { ally: 600, enemy: 690 }; // linha de frente usada no reagrupamento entre rodadas
  // Peso de cada personagem: duração dos deslocamentos, curva, alcance da arma e quanto é empurrado
  const MOVE = {
    knight:    { dash: 1.30, ease: 'inOut', reach: 72, knock: 0.65, width: 96 },
    swordsman: { dash: 0.70, ease: 'out',   reach: 82, knock: 1.00, width: 84 },
    mage:      { dash: 1.10, ease: 'inOut', reach: 70, knock: 1.10, width: 84 },
    brute:     { dash: 1.40, ease: 'inOut', reach: 88, knock: 0.55, width: 124 },
    duelist:   { dash: 0.75, ease: 'out',   reach: 84, knock: 1.00, width: 84 },
    conjurer:  { dash: 1.10, ease: 'inOut', reach: 70, knock: 1.10, width: 88 },
    lancer:    { dash: 0.90, ease: 'out',   reach: 128, knock: 0.90, width: 86 },
    brawler:   { dash: 0.60, ease: 'out',   reach: 60, knock: 0.95, width: 80 },
    archer:    { dash: 0.90, ease: 'inOut', reach: 70, knock: 1.10, width: 80 },
  };
  const LEVELS = ['light', 'medium', 'heavy', 'extreme'];
  // Poses defensivas (bloqueio / aparo / esquiva) por classe — preparadas no planejamento
  const DEF_POSE = {
    knight:    { block: { guard: 1.15, arm: -0.25, crouch: 0.08, lean: 0.06 }, parry: { arm: -0.9, guard: 0.5, crouch: 0.05 } },
    swordsman: { parry: { arm: -0.95, lean: 0.08, crouch: 0.06 }, dodge: { crouch: 0.12, lean: -0.1, arm: -0.3 }, block: { arm: -0.6, guard: 0.6, crouch: 0.06 } },
    mage:      { dodge: { cast: 0.55, crouch: 0.07, lean: -0.06, arm: -0.3 }, block: { cast: 0.8, arm: -0.6 } },
    lancer:    { parry: { arm: 0.9, crouch: 0.07, lean: 0.04 }, block: { arm: 0.9, crouch: 0.07 } },
    brawler:   { dodge: { crouch: 0.14, lean: -0.12, arm: -0.25 }, block: { arm: -0.35, crouch: 0.1 } },
    archer:    { dodge: { crouch: 0.13, lean: -0.12, cast: 0.15 } },
    brute:     { block: { guard: 1, arm: -0.6, crouch: 0.1 } },
    duelist:   { parry: { arm: -1.0, lean: 0.06, crouch: 0.05 } },
    conjurer:  { dodge: { cast: 0.5, crouch: 0.06, lean: -0.08 } },
  };
  const DEF_GENERIC = { block: { guard: 1, crouch: 0.06 }, parry: { arm: -0.7 }, dodge: { cast: 0.4, crouch: 0.06 } };
  // Quebra de Postura: cada um perde a guarda do seu jeito (armas nunca atravessam o corpo)
  const BREAK_POSE = {
    knight: { guard: -0.6, arm: 0.9, lean: -0.35, crouch: 0.08 }, swordsman: { arm: 1.5, lean: -0.38, crouch: 0.06 },
    mage: { cast: 0, arm: 0.9, lean: -0.32, crouch: 0.08 }, lancer: { arm: -1.4, lean: -0.3, crouch: 0.06 },
    brawler: { arm: -0.5, lean: -0.42, crouch: 0.1 }, archer: { cast: 0, lean: -0.34, crouch: 0.1, arm: 0.5 },
    brute: { kneel: 1, tilt: 0.36, crouch: 0.3, arm: 0.9 }, duelist: { arm: 1.4, lean: -0.42, crouch: 0.06 },
    conjurer: { cast: 0, arm: 1.0, lean: -0.35 },
  };
  // Gestos ocasionais de espera, por classe: [propriedades, duração] — sempre voltam à pose base
  const GESTURES = {
    knight:    [[[{ guard: 0.55 }, 260], [{ guard: 0 }, 300]], [[{ arm: -0.35 }, 240], [{ arm: 0 }, 300]], [[{ crouch: 0.07 }, 280], [{ crouch: 0 }, 320]]],
    swordsman: [[[{ arm: -0.9 }, 160], [{ arm: 0.5 }, 180], [{ arm: 0 }, 220]], [[{ lean: 0.07 }, 260], [{ lean: -0.05 }, 260], [{ lean: 0 }, 200]], [[{ crouch: 0.06, lean: 0.08 }, 220], [{ crouch: 0, lean: 0 }, 260]]],
    mage:      [[[{ cast: 0.45, arm: -0.3 }, 320], [{ cast: 0, arm: 0 }, 380]], [[{ arm: 0.25 }, 300], [{ arm: 0 }, 340]]],
    lancer:    [[[{ arm: 0.45 }, 280], [{ arm: 0 }, 320]], [[{ arm: -0.25 }, 200], [{ arm: 0.1 }, 200], [{ arm: 0 }, 200]]],
    brawler:   [[[{ arm: 0.35 }, 140], [{ arm: -0.15 }, 160], [{ arm: 0 }, 180]], [[{ lean: 0.06 }, 200], [{ lean: -0.06 }, 200], [{ lean: 0 }, 180]]],
    archer:    [[[{ cast: 0.35 }, 260], [{ cast: 0 }, 300]], [[{ lean: -0.1 }, 260], [{ lean: 0 }, 280]], [[{ cast: 0.75, lean: -0.04 }, 380], [{ cast: 0.75 }, 500], [{ cast: 0, lean: 0 }, 300]]],
    brute:     [[[{ arm: -0.55 }, 420], [{ arm: 0 }, 460]], [[{ crouch: 0.08 }, 320], [{ crouch: 0 }, 360]]],
    duelist:   [[[{ arm: -0.4 }, 220], [{ arm: 0.2 }, 220], [{ arm: 0 }, 220]], [[{ lean: 0.08 }, 260], [{ lean: 0 }, 260]]],
    conjurer:  [[[{ cast: 0.5 }, 380], [{ cast: 0 }, 420]]],
  };
  const Z_MIN = 0.72; // menor zoom permitido (o cenário cobre essa área)
  const STANCE_STATE = { block: 'BLOCKING', parry: 'PARRYING', dodge: 'DODGING' };
  const ease = {
    lin: t => t,
    out: t => 1 - Math.pow(1 - t, 3),
    in: t => t * t,
    inOut: t => 0.5 - Math.cos(Math.PI * t) / 2,
    back: t => { const c = 1.7; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); },
  };
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, t) => a + (b - a) * t;

  class Presenter {
    constructor(canvas) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.speed = 1;
      this.slow = 1; this.slowTimer = 0; this.freeze = 0;
      this.skipping = false;
      this.tweens = []; this.waits = [];
      this.particles = []; this.texts = []; this.fx = [];
      this.banner = null; this.caption = null; this.screenFlash = 0;
      this.cam = { x: W / 2, y: H / 2, z: 1 }; this.camT = { x: W / 2, y: H / 2, z: 1 }; this.viewCY = H / 2;
      this.shake = 0; this.spot = null; this.time = 0;
      this.threatened = null; this.nums = []; this.plates = []; this.showLabels = true; this.highlight = null;
      this.bg = this._buildBackground();
      this.fog = Array.from({ length: 20 }, (_, i) => ({ x: Math.random() * (W + BG_M.x * 2) - BG_M.x, y: GROUND - 40 + Math.random() * 120, r: 80 + Math.random() * 120, v: 0.004 + Math.random() * 0.01 }));
      this._last = performance.now();
      this._resize();
      new ResizeObserver(() => this._resize()).observe(canvas.parentElement);
      requestAnimationFrame(t => this._frame(t));
    }

    // ------------------------------------------------------------ setup
    reset(battle) {
      this.vis = {};
      battle.units.forEach((u, i) => {
        const h = u.side === 'ally' ? ALLY_SLOTS[u.slot] : HOME[u.id];
        this.vis[u.id] = { id: u.id, art: u.def.art, name: u.name, side: u.side,
          face: u.side === 'ally' ? 1 : -1, home: h, x: h.x, y: h.y,
          lean: 0, arm: 0, guard: 0, cast: 0, crouch: 0, flash: 0, alpha: 1, hop: 0,
          barrier: 0, ready: 0, dead: u.hp <= 0, hp: u.hp, dispHp: u.hp, maxHp: u.maxHp,
          statuses: { ...u.statuses }, phase: i * 1.7, trail: [], stance: null,
          state: u.hp > 0 ? 'IDLE' : 'DEFEATED', tilt: 0, kneel: 0, busy: null,
          formation: u.def.formation != null ? u.def.formation : u.slot, wound: 0, ambT: 1500 + i * 700,
          post: u.post, postMax: u.postMax, dispPost: u.post, broken: u.broken, stable: u.stable, prep: null, gestT: 2500 + i * 900 };
      });
      this.tweens = []; this.waits = []; this.particles = []; this.texts = []; this.fx = [];
      this.banner = null; this.caption = null; this.spot = null;
      this.threatened = null; this.nums = [];
      this.overview();
    }

    _resize() {
      const r = this.canvas.parentElement.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.canvas.width = Math.round(r.width * dpr);
      this.canvas.height = Math.round(r.height * dpr);
      this.scale = Math.max(r.width / W, r.height / H); // preenche (corta bordas)
      this.offX = (r.width - W * this.scale) / 2;
      // em telas "largas" corta o céu, nunca o chão onde estão os personagens
      this.offY = clamp(r.height - 690 * this.scale, r.height - H * this.scale, 0);
      this.dpr = dpr;
      this.viewCY = ((r.height / 2) - this.offY) / this.scale; // centro visível (mundo, câmera em zoom 1)
      if (!this.spot) this.overview();
    }

    // ------------------------------------------------------------ tempo
    tween(obj, props, dur, e = 'out') {
      if (this.skipping || dur <= 0) { Object.assign(obj, props); return Promise.resolve(); }
      return new Promise(res => {
        const from = {}; for (const k in props) from[k] = obj[k];
        this.tweens.push({ obj, from, to: props, dur, t: 0, e: ease[e] || ease.out, res });
      });
    }
    wait(ms) {
      if (this.skipping || ms <= 0) return Promise.resolve();
      return new Promise(res => this.waits.push({ t: ms, res }));
    }
    slowMo(factor, realMs) { if (this.skipping || G.reduceMotion) return; this.slow = factor; this.slowTimer = realMs; }
    hitStop(realMs) { if (this.skipping) return; this.freeze = Math.max(this.freeze, realMs); }
    skip() {
      this.skipping = true;
      for (const tw of this.tweens) { Object.assign(tw.obj, tw.to); tw.res(); }
      for (const w of this.waits) w.res();
      this.tweens = []; this.waits = [];
      this.particles = []; this.texts = []; this.fx = []; this.banner = null; this.nums = []; this.plates = [];
      this.slow = 1; this.freeze = 0;
    }

    _frame(now) {
      const real = Math.min(50, now - this._last); this._last = now;
      if (this.paused) { requestAnimationFrame(t => this._frame(t)); return; }
      if (this.slowTimer > 0) { this.slowTimer -= real; if (this.slowTimer <= 0) this.slow = 1; }
      let dt = real * this.speed * this.slow;
      if (this.freeze > 0) { this.freeze -= real; dt = 0; }
      this.time += real;
      this._update(dt, real);
      this._draw();
      requestAnimationFrame(t => this._frame(t));
    }

    _update(dt, real) {
      for (let i = this.tweens.length - 1; i >= 0; i--) {
        const tw = this.tweens[i];
        tw.t += dt;
        const p = clamp(tw.t / tw.dur, 0, 1), e = tw.e(p);
        for (const k in tw.to) tw.obj[k] = lerp(tw.from[k], tw.to[k], e);
        if (p >= 1) { this.tweens.splice(i, 1); tw.res(); }
      }
      for (let i = this.waits.length - 1; i >= 0; i--) {
        const w = this.waits[i]; w.t -= dt;
        if (w.t <= 0) { this.waits.splice(i, 1); w.res(); }
      }
      if (this.follow) this._frameFollow();
      // câmera suave (tempo real para não "travar" na câmera lenta)
      const k = 1 - Math.exp(-real * 0.006 * Math.max(1, this.speed * 0.8));
      this.cam.x = lerp(this.cam.x, this.camT.x, k);
      this.cam.y = lerp(this.cam.y, this.camT.y, k);
      this.cam.z = lerp(this.cam.z, this.camT.z, k);
      this.shake = Math.max(0, this.shake - real * 0.03);
      this.screenFlash = Math.max(0, this.screenFlash - real * 0.003);
      for (const id in (this.vis || {})) {
        const v = this.vis[id];
        v.flash = Math.max(0, v.flash - dt * 0.005);
        v.dispHp = lerp(v.dispHp, v.hp, 1 - Math.exp(-dt * 0.008));
        v.dispPost = lerp(v.dispPost, v.post, 1 - Math.exp(-dt * 0.006));
        v.postFlash = Math.max(0, (v.postFlash || 0) - dt * 0.003);
        if (v.trail.length && (this.time - v.trail[0].t > 160)) v.trail.shift();
        if (v.dashing) v.trail.push({ x: v.x, y: v.y, t: this.time });
      }
      for (let i = this.particles.length - 1; i >= 0; i--) {
        const p = this.particles[i];
        p.life -= dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vy += (p.g || 0) * dt;
        p.vx *= 0.995;
        if (p.life <= 0) this.particles.splice(i, 1);
      }
      for (let i = this.texts.length - 1; i >= 0; i--) {
        const t = this.texts[i]; t.life -= dt; t.y += t.vy * dt; t.vy *= 0.97;
        if (t.life <= 0) this.texts.splice(i, 1);
      }
      for (let i = this.fx.length - 1; i >= 0; i--) {
        const f = this.fx[i]; f.t += dt;
        if (f.t >= f.dur) this.fx.splice(i, 1);
      }
      if (this.banner) { this.banner.t += dt; if (this.banner.t > this.banner.dur) this.banner = null; }
      for (const f of this.fog) { f.x += f.v * real; if (f.x > W + BG_M.x) f.x = -BG_M.x; }
      if (this.ambient && this.vis && !this.skipping) this._ambientTick(real);
      // condição física: muda suavemente conforme a vida
      for (const id in (this.vis || {})) {
        const v = this.vis[id], r = v.hp / v.maxHp;
        v.wound = lerp(v.wound, clamp((0.5 - r) / 0.35, 0, 1), 1 - Math.exp(-real * 0.002));
      }
    }

    // ------------------------------------------------------------ câmera
    // tamanho do mundo visível com zoom 1 (depende da proporção da tela)
    get viewW() { return this.canvas.clientWidth / this.scale; }
    get viewH() { return this.canvas.clientHeight / this.scale; }
    // plano geral: garante que a arena inteira cabe, mesmo em telas estreitas
    overview() {
      this.follow = null; this.spot = null;
      const z = Math.min(1, (this.viewW || W) / (ARENA.maxX - ARENA.minX + 170));
      this.camT = this._clampCam({ x: W / 2, y: (this.viewCY || H / 2) + (1 - z) * 60, z });
    }
    _clampCam(c) {
      const hw = this.viewW / 2 / c.z, hh = this.viewH / 2 / c.z;
      // 40 px de folga para o tremor de câmera nunca revelar a borda do cenário
      return { x: clamp(c.x, -BG_M.x + 40 + hw, W + BG_M.x - 40 - hw), y: clamp(c.y, -BG_M.y + 40 + hh, H + BG_M.y - 40 - hh), z: c.z };
    }
    // Atacante e alvo cabem juntos na tela? (senão, a câmera acompanha o projétil)
    canFrame(vs) {
      const xs = vs.map(v => v.x);
      return this.viewW / (Math.max(...xs) - Math.min(...xs) + 240) >= Z_MIN;
    }
    // A câmera passa a ACOMPANHAR os personagens focados (inclusive quando são empurrados),
    // e vai direto de um confronto ao próximo, sem voltar ao plano geral.
    focusOn(vs, extraZoom = 0) {
      vs = vs.filter(Boolean);
      if (!vs.length) return;
      this.follow = { vs, extraZoom };
      this.spot = new Set(vs.map(v => v.id));
      this._frameFollow();
    }
    _frameFollow() {
      const { vs, extraZoom } = this.follow;
      const xs = vs.map(v => v.x), ys = vs.map(v => v.y - 60);
      const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
      const cy = (Math.min(...ys) + Math.max(...ys)) / 2;
      const span = Math.max(...xs) - Math.min(...xs) + 240; // margem para armas, projéteis e recuos
      const spanY = Math.max(...ys) - Math.min(...ys) + 300;
      // zoom desejado, limitado pelo que REALMENTE cabe na tela (nunca corta o alvo)
      const fit = Math.min(this.viewW / span, this.viewH / spanY);
      const z = clamp(Math.min(clamp(1.85 - span / 1000, 1.05, 1.5) + extraZoom, fit), Z_MIN, 1.6);
      this.camT = this._clampCam({ x: cx, y: cy + (1 - Math.min(z, 1)) * 40, z });
    }
    toScreen(wx, wy) {
      const x = (wx - this.cam.x) * this.cam.z + W / 2, y = (wy - this.cam.y) * this.cam.z + this.viewCY;
      return { x: x * this.scale + this.offX, y: y * this.scale + this.offY };
    }
    // fator mundo → pixels de tela (para manter a interface com tamanho constante)
    get pxPerWorld() { return this.cam.z * this.scale; }
    toWorld(sx, sy) {
      const x = (sx - this.offX) / this.scale, y = (sy - this.offY) / this.scale;
      return { x: (x - W / 2) / this.cam.z + this.cam.x, y: (y - this.viewCY) / this.cam.z + this.cam.y };
    }
    pick(sx, sy) {
      const p = this.toWorld(sx, sy);
      let best = null;
      for (const id in this.vis) {
        const v = this.vis[id];
        if (v.dead) continue;
        if (Math.abs(p.x - v.x) < 50 && p.y < v.y + 16 && p.y > v.y - 155) {
          if (!best || v.y > best.y) best = v;
        }
      }
      return best ? best.id : null;
    }

    // ------------------------------------------------------------ efeitos
    sparks(x, y, color, n = 14, spd = 0.5, g = 0.0012) {
      if (this.skipping) return;
      for (let i = 0; i < n; i++) {
        const a = Math.random() * Math.PI * 2, s = spd * (0.3 + Math.random());
        this.particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s - 0.15, g, life: 300 + Math.random() * 300, max: 600, color, r: 2 + Math.random() * 2.5 });
      }
    }
    float(x, y, text, color, size = 26, life = 1100) {
      if (this.skipping) return;
      this.texts.push({ x, y, text, color, size, life, max: life, vy: -0.09 });
    }
    addFx(f) { if (!this.skipping) this.fx.push(Object.assign({ t: 0 }, f)); }
    // CombatStatusUI: estado comunicado por um ÍCONE pequeno ao lado da barra (nunca texto grande);
    // um aviso por personagem por vez (o novo substitui o anterior)
    statusIcon(v, icon, color, dur = 950) {
      if (this.skipping || !v) return;
      this.fx = this.fx.filter(f => !(f.kind === 'sicon' && f.ref === v));
      this.addFx({ kind: 'sicon', ref: v, icon, color, dur });
    }
    showBanner(text, color, dur = 900, sub = '') { if (!this.skipping) this.banner = { text, color, t: 0, dur, sub }; }
    // tremor pequeno e direcional (na direção do golpe); golpes leves quase não tremem
    hurtShake(amount, dir = 0) {
      if (this.skipping || amount < 3) return;
      if (G.reduceMotion) amount *= 0.3; // opção "reduzir animações"
      if (amount >= this.shake) this.shakeDir = dir;
      this.shake = Math.max(this.shake, amount);
    }
    // luz breve no impacto (sem esconder personagens)
    flashAt(x, y, color, r = 70) { this.addFx({ kind: 'flash', dur: 160, x, y, color, r }); }

    // ============================================================ ESTADOS VISUAIS
    // Cada personagem tem seu próprio estado visual e pode estar numa
    // "rotina" (recuperação, queda, reposicionamento) enquanto o próximo
    // confronto já começa. A lógica nunca depende disso.
    setState(v, s) { v.state = s; }
    // Executa uma rotina em segundo plano; v.busy indica que ainda está acontecendo.
    routine(v, fn) {
      const p = (v.busy || Promise.resolve()).then(() => fn()).catch(() => {}).then(() => { if (v.busy === p) v.busy = null; });
      v.busy = p;
      return p;
    }
    // Sincroniza a postura antes de o personagem entrar em outro confronto.
    sync(...vs) { return Promise.all(vs.filter(Boolean).map(v => v.busy || null)); }
    faceTo(v, other) { if (!v.dead && other && Math.abs(other.x - v.x) > 4) v.face = other.x > v.x ? 1 : -1; }
    clampPos(x, y) { return { x: clamp(x, ARENA.minX, ARENA.maxX), y: clamp(y, ARENA.minY, ARENA.maxY) }; }
    moveTo(v, x, y, dur, e) {
      const p = this.clampPos(x, y);
      return this.tween(v, { x: p.x, y: p.y }, dur, e || MOVE[v.art].ease);
    }
    dust(v, n = 8) { this.sparks(v.x, v.y - 4, 'rgba(160,140,130,0.55)', n, 0.18, -0.0002); }

    // Afasta personagens sobrepostos e mantém todos na arena (suave).
    settle(lock = []) {
      if (!this.vis) return;
      const all = Object.values(this.vis);
      const target = {};
      for (const v of all) target[v.id] = this.clampPos(v.x, v.y);
      for (let it = 0; it < 4; it++) {
        for (let i = 0; i < all.length; i++) for (let j = i + 1; j < all.length; j++) {
          const a = all[i], b = all[j], ta = target[a.id], tb = target[b.id];
          const dx = tb.x - ta.x, dy = tb.y - ta.y;
          const need = (MOVE[a.art].width + MOVE[b.art].width) / 2;
          if (Math.abs(dy) > 46 || Math.abs(dx) >= need) continue;
          const push = (need - Math.abs(dx)) / 2 + 1, s = dx >= 0 ? 1 : -1;
          const fixedA = a.dead || a.busy || lock.includes(a), fixedB = b.dead || b.busy || lock.includes(b);
          if (fixedA && fixedB) continue;
          if (fixedA) tb.x += s * push * 2; else if (fixedB) ta.x -= s * push * 2;
          else { ta.x -= s * push; tb.x += s * push; }
          ta.x = clamp(ta.x, ARENA.minX, ARENA.maxX); tb.x = clamp(tb.x, ARENA.minX, ARENA.maxX);
        }
      }
      for (const v of all) {
        const t = target[v.id];
        if (v.dead || v.busy) continue;
        if (Math.abs(t.x - v.x) > 1 || Math.abs(t.y - v.y) > 1) {
          this.setState(v, 'REPOSITIONING');
          this.tween(v, { x: t.x, y: t.y }, 380, 'inOut').then(() => { if (v.state === 'REPOSITIONING') this.setState(v, 'IDLE'); });
        }
        this.faceTo(v, this._nearestFoe(v));
      }
    }
    _nearestFoe(v) {
      let best = null, bd = 1e9;
      for (const id in this.vis) {
        const o = this.vis[id];
        if (o.side === v.side || o.dead) continue;
        const d = Math.abs(o.x - v.x) + Math.abs(o.y - v.y) * 0.5;
        if (d < bd) { bd = d; best = o; }
      }
      return best;
    }

    // ------------------------------------------------------------ MOVIMENTO AMBIENTE
    // Pequenos passos com propósito: voltar para a "faixa" preferida da formação,
    // recuar se um inimigo está perto demais, ajustar distância de um aliado.
    // Nunca durante ações, quedas, nem com o personagem selecionado/arrastado.
    _ambientTick(dt) {
      const ui = this.ui, busyIds = new Set();
      if (ui && ui.sel) busyIds.add(ui.sel.uid);
      if (ui && ui.drag) return; // não mexe nada enquanto o jogador arrasta uma corrente
      for (const id in this.vis) {
        const v = this.vis[id];
        // inimigo preparando o ataque: só gestos discretos sobre a pose de preparação (sem sair do lugar)
        if (v.state === 'PREPARING' && !v.dead && !v.busy) {
          v.gestT -= dt;
          if (v.gestT <= 0) { v.gestT = 4200 + Math.random() * 4500; this._gesture(v, true); }
          continue;
        }
        if (v.dead || v.busy || busyIds.has(id) || !['IDLE', 'BLOCKING', 'PARRYING', 'DODGING'].includes(v.state)) continue;
        // gestos de classe (intervalos variados; nunca com postura defensiva preparada)
        v.gestT -= dt;
        if (v.gestT <= 0 && v.state === 'IDLE' && !v.prep) { v.gestT = 3500 + Math.random() * 5000; this._gesture(v); continue; }
        // postura comprometida: ajusta os pés com mais frequência
        if (v.post / v.postMax < 0.5) v.ambT -= dt * 0.6;
        v.ambT -= dt;
        if (v.ambT > 0) continue;
        v.ambT = 2600 + Math.random() * 4200;
        const foe = this._nearestFoe(v);
        const sideDir = v.side === 'ally' ? 1 : -1;
        const pref = v.side === 'ally' ? [560, 420, 270][v.formation] : [740, 880, 1040][v.formation];
        // profundidade preferida: frente mais à frente da tela, retaguarda mais ao fundo (só preferência)
        const prefY = [612, 590, 562][v.formation] + (v.phase % 1 - 0.5) * 20;
        let dy = clamp((prefY - v.y) * 0.35, -16, 16) + (Math.random() - 0.5) * 14;
        // CombatAmbientMovement: preferência de formação FRACA (não puxa de volta à posição inicial);
        // melee pode ficar avançado; ranged só busca espaço discretamente
        const behindPref = sideDir * (v.x - pref) < 0;
        const pull = v.formation === 0 ? (behindPref ? 0.06 : 0) : 0.06;
        let dx = clamp((pref - v.x) * pull, -10, 10) + (Math.random() - 0.5) * 14;
        if (foe && Math.abs(foe.x - v.x) < 170) dx = -sideDir * 26;               // inimigo perto: recua
        if (Math.abs(dx) < 6 && Math.abs(dy) < 5) { this.tween(v, { lean: (Math.random() - 0.5) * 0.06 }, 600, 'inOut'); continue; } // só ajusta postura
        // respeita o espaço dos outros
        const nx = clamp(v.x + dx, ARENA.minX, ARENA.maxX), ny = clamp(v.y + dy, ARENA.minY, ARENA.maxY);
        const crowded = Object.values(this.vis).some(o => o !== v && !o.dead && Math.abs(o.y - ny) < 46 && Math.abs(o.x - nx) < (MOVE[o.art].width + MOVE[v.art].width) / 2);
        if (crowded) continue;
        this.setState(v, 'REPOSITIONING');
        const dur = 420 + Math.hypot(dx, dy) * 10;
        this.tween(v, { x: nx, y: ny }, dur, 'inOut').then(() => { if (v.state === 'REPOSITIONING') this.setState(v, v.stance ? STANCE_STATE[v.stance] : 'IDLE'); if (foe) this.faceTo(v, foe); });
        this.tween(v, { hop: 3 }, dur / 4, 'out').then(() => this.tween(v, { hop: 0 }, dur / 4, 'in')).then(() => this.tween(v, { hop: 2 }, dur / 4, 'out')).then(() => this.tween(v, { hop: 0 }, dur / 4, 'in'));
      }
    }

    _gesture(v, keepPose = false) {
      const list = GESTURES[v.art];
      if (!list) return;
      const g = list[Math.floor(Math.random() * list.length)];
      // base: pose de espera, ou a pose atual de preparação (o gesto volta exatamente a ela)
      const base = keepPose ? { arm: v.arm, guard: v.guard, cast: v.cast, lean: v.lean, crouch: v.crouch } : this._stancePose(v);
      const st = v.state;
      this.routine(v, async () => {
        for (const [props, dur] of g) {
          if (v.state !== st || v.dead) break;
          const target = {};
          for (const k in props) target[k] = (base[k] || 0) + props[k];
          await this.tween(v, target, dur, 'inOut');
        }
        if (!v.dead && v.state === st) await this.tween(v, base, 220, 'inOut');
        if (v.art === 'mage' || v.art === 'conjurer') this.sparks(v.x + v.face * 26, v.y - 112, v.side === 'ally' ? 'rgba(160,220,255,0.5)' : 'rgba(210,150,255,0.5)', 3, 0.08, -0.0003);
      });
    }

    // ------------------------------------------------------------ REAÇÕES FÍSICAS
    // level: light | medium | heavy | extreme  — dir: +1/-1 (para onde é empurrado)
    // Retorna rápido (depois do impacto); a recuperação continua em segundo plano.
    react(v, level, dir, killed) {
      const P = MOVE[v.art];
      if (killed || level === 'heavy' || level === 'extreme') this._lastVictim = v;
      if (level === 'extreme' || killed) SFX('heavy');
      if (killed) return this.routine(v, () => this._fall(v, dir, true));
      if (level === 'light') {
        return this.routine(v, async () => {
          this.setState(v, 'HIT_LIGHT');
          await this.tween(v, { x: clamp(v.x + dir * 16 * P.knock, ARENA.minX, ARENA.maxX), lean: -0.3, crouch: 0.05 }, 90, 'out');
          await this.tween(v, { lean: 0, crouch: 0 }, 220, 'inOut');
          this.setState(v, 'IDLE');
        });
      }
      if (level === 'medium') {
        return this.routine(v, async () => {
          this.setState(v, 'HIT_HEAVY');
          this.dust(v, 6);
          const slide = this.tween(v, { x: clamp(v.x + dir * 85 * P.knock, ARENA.minX, ARENA.maxX), lean: -0.45, crouch: 0.1 }, 320, 'out');
          for (let i = 0; i < 3; i++) { await this.wait(80); this.dust(v, 3); }
          await slide;
          await this.tween(v, { lean: 0, crouch: 0 }, 300, 'inOut');
          this.setState(v, 'IDLE');
        });
      }
      if (level === 'heavy') {
        return this.routine(v, async () => {
          this.setState(v, 'STAGGERING');
          this.dust(v, 8);
          await this.tween(v, { x: clamp(v.x + dir * 105 * P.knock, ARENA.minX, ARENA.maxX), lean: -0.6, crouch: 0.12 }, 300, 'out');
          // quase cai: apoia a mão no chão e fica ajoelhado
          await this.tween(v, { lean: 0, tilt: 0.38, crouch: 0.32, kneel: 1, arm: 0.9 }, 220, 'in');
          this.dust(v, 6);
          await this.wait(420);
          await this.tween(v, { tilt: 0.12, crouch: 0.15, kneel: 0.3 }, 300, 'inOut');
          await this.tween(v, { tilt: 0, crouch: 0, kneel: 0, arm: 0 }, 260, 'inOut');
          this.setState(v, 'IDLE');
        });
      }
      return this.routine(v, () => this._fall(v, dir, false));
    }

    // Derrubada (com recuperação) ou derrota (fica no chão).
    async _fall(v, dir, defeated) {
      this.setState(v, defeated ? 'DEFEATED' : 'KNOCKDOWN');
      const P = MOVE[v.art];
      const fx = clamp(v.x + dir * 150 * P.knock, ARENA.minX, ARENA.maxX);
      // arremessado em arco, cai de costas
      this.tween(v, { x: fx }, 420, 'out');
      await this.tween(v, { hop: 46 * P.knock, tilt: -0.9 }, 200, 'out');
      await this.tween(v, { hop: 0, tilt: -1.45, crouch: 0, lean: 0, arm: 0.6, kneel: 0 }, 200, 'in');
      this.dust(v, 14);
      SFX('thud', { vol: 0.8 });
      if (defeated) SFX('defeat', { vol: 0.6 });
      this.hurtShake(defeated ? 8 : 6, dir);
      await this.tween(v, { hop: 8 }, 90, 'out'); await this.tween(v, { hop: 0 }, 110, 'in');
      if (defeated) {
        v.dead = true;
        await this.tween(v, { alpha: 0.45 }, 400);
        return;
      }
      await this.wait(650);
      // levantando
      this.setState(v, 'GETTING_UP');
      await this.tween(v, { tilt: -0.5, crouch: 0.3, kneel: 0.6 }, 380, 'inOut');
      await this.tween(v, { tilt: 0.2, crouch: 0.2, kneel: 0.2 }, 300, 'inOut');
      await this.tween(v, { tilt: 0, crouch: 0, kneel: 0, arm: 0 }, 280, 'out');
      this.setState(v, 'IDLE');
    }

    // Golpe/finalização da arma depois de atacar, sem voltar à formação.
    followThrough(v, effort = false) {
      return this.routine(v, async () => {
        this.setState(v, 'ATTACKING');
        await this.wait(120);
        await this.tween(v, { arm: 0.35, lean: effort ? 0.18 : 0.05, crouch: effort ? 0.12 : 0.04, cast: 0 }, effort ? 380 : 260, 'out');
        if (effort) await this.wait(160);
        await this.tween(v, this._stancePose(v), 300, 'inOut');
        this.setState(v, v.stance ? STANCE_STATE[v.stance] : 'IDLE');
      });
    }
    _stancePose(v) {
      const r = v.stance || v.prep;
      const base = { arm: 0, guard: 0, cast: 0, lean: 0, crouch: 0 };
      if (!r) return base;
      return Object.assign(base, (DEF_POSE[v.art] || {})[r] || DEF_GENERIC[r] || {});
    }
    // Postura defensiva escolhida no planejamento (transição suave; null = cancelar)
    setPrepStance(id, reaction) {
      const v = this.vis && this.vis[id];
      if (!v || v.dead || v.prep === reaction) return;
      v.prep = reaction;
      if (v.broken || v.busy || !['IDLE', 'BLOCKING', 'PARRYING', 'DODGING', 'PREPARING'].includes(v.state)) return;
      this.setState(v, reaction ? STANCE_STATE[reaction] : 'IDLE');
      this.tween(v, this._stancePose(v), 280, 'inOut');
    }

    // ------------------------------------------------------------ POSTURA (apresentação)
    // Barra cai em etapas junto com os golpes; a Quebra acontece no golpe que zera a Postura.
    _postureStep(v, value) { v.post = value; }
    _postureBreak(v, dir) {
      if (v.dead) return;
      SFX('postureBreak');
      this.flashAt(v.x, v.y - 80, '#ffd36a', 90);
      this.addFx({ kind: 'shatter', dur: 520, x: v.x, y: v.y - 80, color: '#ffd36a' });
      this.sparks(v.x, v.y - 80, '#ffd36a', 22, 0.6);
      this.hurtShake(8, dir);
      this.hitStop(90);
      this.wait(160).then(() => this.statusIcon(v, 'break', '#ffd36a', 1400)); // depois do número de dano, acima dele
      this.focusOn([v], 0.15);
      // depois da reação física, fica na pose de guarda aberta até cumprir a penalidade
      this.routine(v, async () => {
        this.setState(v, 'BROKEN');
        await this.tween(v, Object.assign({ guard: 0, cast: 0, lean: 0, crouch: 0, arm: 0, tilt: 0, kneel: 0 }, BREAK_POSE[v.art] || BREAK_POSE.swordsman), 260, 'out');
      });
    }
    async playStagger(ev) {
      for (const id of ev.unitIds) {
        const v = this.vis[id];
        if (!v || v.dead) continue;
        await this.sync(v);
        this.focusOn([v], 0.1);
        this.caption = `${v.name} está desequilibrado e perde a ação`;
        this.statusIcon(v, 'lost', '#ff9a8a', 1300);
        await this.wait(380);
        // recuperação: ajusta os pés, ergue a guarda, Postura volta ao máximo
        this.setState(v, 'REPOSITIONING');
        this.tween(v, { hop: 6 }, 120, 'out').then(() => this.tween(v, { hop: 0 }, 140, 'in'));
        await this.tween(v, Object.assign({ tilt: 0, kneel: 0 }, this._stancePose(v)), 360, 'inOut');
        v.post = v.postMax; v.broken = false; v.stable = true;
        SFX('recover');
        this.addFx({ kind: 'ring', dur: 420, x: v.x, y: v.y - 70, color: '#ffd36a', r: 55 });
        this.statusIcon(v, 'restore', '#ffd36a', 1100);
        this.setState(v, 'IDLE');
        await this.wait(220);
      }
      this.caption = null;
    }

    // ------------------------------------------------------------ intenções
    // Etapa 1: cada inimigo assume a postura do que vai fazer (rápido).
    async announceIntents(intents) {
      for (const it of intents) {
        const A = this.vis[it.actorId], T = this.vis[it.targetId], sk = G.SKILLS[it.skillId];
        if (!A || A.dead) continue;
        await this.sync(A);
        const magic = sk.tags.includes('magic');
        this.setState(A, 'PREPARING');
        if (sk.kind === 'defense') {
          this.focusOn([A], -0.25);
          A.prep = sk.reaction; this.tween(A, Object.assign({ ready: 1 }, this._stancePose(A)), 360, 'inOut');
          this.caption = `${A.name} se prepara para defender (${sk.name})`;
        } else if (sk.combo) {
          // combinação anunciada: os dois membros assumem postura e ficam destacados
          const Ps = (it.partners || []).map(id => this.vis[id]);
          this.focusOn([A, ...Ps, T], -0.25);
          for (const v of [A, ...Ps]) { this.faceTo(v, T); this.setState(v, 'PREPARING'); this.tween(v, { ready: 1, arm: -1.1, lean: -0.1 }, 240); this.sparks(v.x, v.y - 150, '#ffb36a', 8, 0.2, -0.0004); }
          this.showBanner('ATAQUE COMBINADO', '#ff9a5a', 1000, `${[A, ...Ps].map(v => v.name).join(' + ')} → ${T.name}`);
          this.caption = `${[A, ...Ps].map(v => v.name).join(' e ')} preparam ${sk.name} contra ${T.name}!`;
          await this.wait(350);
        } else {
          this.focusOn([A, T], -0.2);
          this.faceTo(A, T);
          // posturas controladas: o brutamontes ergue a arma devagar, o duelista se posiciona,
          // o conjurador concentra energia (sem tremores)
          const prep = { brute: [{ ready: 1, arm: -1.25, lean: -0.12, crouch: 0.08 }, 700], duelist: [{ ready: 1, arm: -0.7, lean: 0.12, crouch: 0.05 }, 420], conjurer: [{ ready: 1, arm: -0.5, cast: 0.8, lean: -0.05 }, 560] }[A.art]
            || [{ ready: 1, arm: magic ? -0.4 : -1.0, cast: magic ? 0.7 : 0, lean: -0.08 }, 360];
          this.tween(A, prep[0], prep[1], 'inOut');
          if (magic) { this.sparks(A.x + A.face * 26, A.y - 110, '#c86bff', 6, 0.12, -0.0004); SFX('magicCharge', { vol: 0.5 }); }
          this.caption = `${A.name} prepara ${sk.name} contra ${T.name}`;
        }
        await this.wait(560);
      }
      this.caption = null;
      this.overview();
      await this.wait(160);
    }
    clearIntents() {
      this.threatened = null;
      for (const id in this.vis) { const v = this.vis[id]; v.ready = 0; if (!v.dead && v.state === 'PREPARING') this.setState(v, 'IDLE'); }
    }

    // ------------------------------------------------------------ reprodução contínua
    // Os confrontos principais seguem a ordem lógica, um em destaque por vez;
    // recuperações e reposicionamentos continuam em paralelo.
    async playAll(events) {
      this.clearIntents();
      this.showLabels = false;
      for (let i = 0; i < events.length; i++) {
        const ev = events[i];
        this._eventIndex = i;
        // não corta a reação forte anterior: espera um pouco ela terminar
        if (this._lastVictim && this._lastVictim.busy) await Promise.race([this._lastVictim.busy, this.wait(650)]);
        this._lastVictim = null;
        if (ev.type === 'clash') await this.playClash(ev);
        else if (ev.type === 'attack') await this.playConfrontation(ev);
        else if (ev.type === 'stances') await this.playStances(ev);
        else if (ev.type === 'support') await this.playSupport(ev);
        else if (ev.type === 'fizzle') await this.playFizzle(ev);
        else if (ev.type === 'stagger') await this.playStagger(ev);
        if (ev.after) this._applySnapshot(ev.after, false);
        this.settle();
      }
      this.caption = null;
      // deixa as últimas quedas/recuperações terminarem e revela as novas posições
      await Promise.all(Object.values(this.vis).map(v => v.busy));
      this.overview();
      this.settle();
      await this.wait(450);
      this.showLabels = true;
      this.skipping = false;
    }

    // PersistentPositionController — fim da rodada: cada um FICA onde terminou a última ação.
    // Só pequenos ajustes naturais (no máx. ~60 px): recuar de um inimigo colado, abrir espaço,
    // virar para a ameaça, recompor a guarda. A formação inicial (v.home) nunca é destino.
    endRound(snap) {
      this._applySnapshot(snap, true);
      const STEP = 60;
      for (const id in this.vis) {
        const v = this.vis[id];
        v.stance = null;
        if (v.dead) continue;
        v.ready = 0; v.barrier = 0; v.prep = null;
        const foe = this._nearestFoe(v);
        let tx = v.x, hopBack = false;
        const ranged = (G.UNITS[v.id] && G.UNITS[v.id].formation || 0) >= 2 || /mage|archer|conjurer/.test(v.art);
        if (foe) {
          const d = Math.abs(foe.x - v.x), away = foe.x >= v.x ? -1 : 1;
          const want = ranged ? 190 : 120; // distância de conforto (ranged busca um pouco mais de espaço)
          if (d < want) { tx = v.x + away * Math.min(STEP, want - d); hopBack = d < 90 && !v.broken; }
        }
        // nunca atravessa para trás da própria retaguarda além do necessário
        tx = clamp(tx, ARENA.minX, ARENA.maxX);
        if (foe) this.faceTo(v, foe);
        if (v.broken) { this.tween(v, { x: tx }, clamp(Math.abs(tx - v.x) * 3, 200, 600), 'inOut'); continue; } // segue desequilibrado
        this.setState(v, 'REPOSITIONING');
        const settleBody = { arm: 0, guard: 0, cast: 0, lean: 0, crouch: 0, tilt: 0, kneel: 0 };
        const go = hopBack
          ? this.tween(v, { crouch: 0.16, lean: -0.1 }, 90, 'out').then(() => Promise.all([this.tween(v, { x: tx }, 260, 'out'), this.tween(v, { hop: 24 }, 130, 'out').then(() => this.tween(v, { hop: 0 }, 130, 'in'))])).then(() => this.tween(v, settleBody, 160, 'out')) // pequeno salto de afastamento
          : this.tween(v, Object.assign({ x: tx }, settleBody), clamp(Math.abs(tx - v.x) * 3.2, 220, 520), 'inOut');
        Promise.resolve(go).then(() => {
          if (v.state !== 'REPOSITIONING') return;
          this.setState(v, 'IDLE');
          this.tween(v, { guard: v.art === 'knight' ? 0.4 : 0.15, lean: 0.06 }, 200, 'out'); // assume postura de confronto
        });
      }
      this.wait(700).then(() => this.settle());
    }

    _applySnapshot(snap, final) {
      for (const id in snap) {
        const v = this.vis[id];
        v.hp = snap[id].hp; v.statuses = { ...snap[id].statuses };
        if (snap[id].post != null) { v.post = snap[id].post; v.postMax = snap[id].postMax; v.broken = snap[id].broken; v.stable = snap[id].stable; }
        if (this.skipping) { v.dispHp = v.hp; v.dispPost = v.post; }
        // garantia: quem morreu na lógica fica derrotado mesmo se a animação foi pulada
        if (v.hp <= 0 && !v.dead && (final || this.skipping || !v.busy)) {
          v.dead = true; this.setState(v, 'DEFEATED');
          Object.assign(v, { tilt: -1.45, hop: 0, alpha: 0.45, crouch: 0, lean: 0, kneel: 0 });
        }
      }
    }

    // Posturas defensivas e Proteção (início da rodada)
    async playStances(ev) {
      this.caption = 'Posturas defensivas';
      const NAME = { block: 'BLOQUEIO', dodge: 'ESQUIVA', parry: 'APARO' };
      const moves = [];
      const vs = [];
      for (const st of ev.list) {
        const v = this.vis[st.unitId];
        vs.push(v);
        await this.sync(v);
        v.stance = st.reaction;
        this.setState(v, STANCE_STATE[st.reaction]);
        if (st.protectId) {
          const T = this.vis[st.protectId];
          // fica entre o aliado e a ameaça mais próxima
          const foe = this._nearestFoe(T) || v;
          const dir = foe.x >= T.x ? 1 : -1;
          this.statusIcon(T, 'protect', '#9fd0ff');
          v.dashing = true;
          this.faceTo(v, foe);
          moves.push(this.moveTo(v, T.x + dir * 82, T.y + 8, 300 * MOVE[v.art].dash, 'out').then(() => { v.dashing = false; }));
          vs.push(T);
        }
        this.statusIcon(v, st.protectId ? 'protect' : st.reaction, '#9fd0ff');
        if (st.postHeal) { this.float(v.x + 62, v.y - 140, `+${st.postHeal}`, '#ffd36a', 14, 1000); this.addFx({ kind: 'ring', dur: 380, x: v.x, y: v.y - 70, color: '#ffd36a', r: 50 }); SFX('recover', { vol: 0.6 }); }
        moves.push(this.tween(v, this._stancePose(v), 220, 'out'));
        if (st.reaction === 'dodge') this.sparks(v.x, v.y - 60, '#cfe9ff', 8, 0.2, -0.0003);
      }
      this.focusOn(vs, -0.3);
      await Promise.all(moves);
      await this.wait(300);
      this.caption = null;
    }

    async playSupport(ev) {
      const A = this.vis[ev.actorId], T = this.vis[ev.targetId];
      await this.sync(A);
      this.caption = `${A.name}  ·  ${G.SKILLS[ev.skillId].name}  →  ${T.name}`;
      this.focusOn([A, T], -0.15);
      this.setState(A, 'PREPARING');
      await this.tween(A, { cast: 1, arm: -0.5 }, 220);
      await this._fireProjectile(A, T, 'support');
      this.addFx({ kind: 'ring', dur: 400, x: T.x, y: T.y - 70, color: '#7fe0a0', r: 60 });
      this.sparks(T.x, T.y - 70, '#7fe0a0', 14, 0.25, -0.0004);
      this.float(T.x, T.y - 165, `+${G.CONFIG.support.amount} FORÇA`, '#7fe0a0', 22);
      if (ev.postHeal) { this.float(T.x + 62, T.y - 140, `+${ev.postHeal}`, '#ffd36a', 14, 1000); SFX('recover', { vol: 0.6 }); }
      this.followThrough(A);
      await this.wait(220);
      this.caption = null;
    }

    async playFizzle(ev) {
      const A = this.vis[ev.actorId];
      this.float(A.x, A.y - 170, `${G.SKILLS[ev.skillId].name}: ${ev.reason}`, '#a99', 16, 900);
      await this.wait(300);
    }

    // ============================================================ SEQUÊNCIAS DE GOLPES
    // Divide o dano total entre os impactos (inteiros que SOMAM exatamente o total).
    _splitDamage(total, shares) {
      const out = []; let acc = 0, sum = shares.reduce((a, b) => a + b, 0);
      shares.forEach((sh, i) => {
        const v = i === shares.length - 1 ? total - acc : Math.round(total * sh / sum);
        out.push(Math.max(0, v)); acc += out[i];
      });
      return out;
    }
    _steps(sk) {
      return sk.hits || [{ by: 0, share: 1, motion: sk.tags.includes('magic') ? 'proj' : sk.tags.includes('ranged') ? 'arrow' : (sk.tags.includes('heavy') ? 'over' : 'h'), react: 'final' }];
    }
    // Leva os parceiros de uma combinação para perto, sem ocupar o lugar do líder.
    _bringPartners(partners, lead, tx, ty) {
      return Promise.all(partners.filter(p => p && !p.dead).map(async (p, i) => {
        await this.sync(p);
        const dir = tx >= lead.x ? 1 : -1;
        this.setState(p, 'APPROACHING'); p.dashing = true;
        this.faceTo(p, { x: tx });
        const lane = (ty > (ARENA.minY + ARENA.maxY) / 2 ? -1 : 1) * (40 + i * 20);
        await this.moveTo(p, tx - dir * (MOVE[p.art].reach + 95), ty + lane, 240 * MOVE[p.art].dash, 'out');
        p.dashing = false;
        this.tween(p, { lean: -0.15, arm: -1.2 }, 140);
      }));
    }
    // ============================================================ CAMERA DIRECTOR (projéteis)
    // A: quem dispara; L: alvo. Se os dois cabem na tela → enquadramento compartilhado.
    // Senão: mostra o disparo, acompanha o projétil e chega no alvo ANTES do impacto.
    // Retorna no instante do contato (o dano só aparece depois disso).
    async _fireProjectile(A, L, kind) {
      const dir = L.x >= A.x ? 1 : -1;
      const arrow = kind === 'arrow' || kind === 'arrowp';
      const sx = A.x + dir * 30, sy = A.y - (arrow ? 96 : 115);
      const tx = L.x - dir * 16, ty = L.y - 72;
      const dist = Math.abs(tx - sx);
      const dur = clamp(190 + dist * 0.3, 230, 560) * (arrow ? (kind === 'arrowp' ? 0.75 : 0.85) : 1);
      const shared = this.canFrame([A, L]);
      const proj = { id: '__proj', x: sx, y: sy + 60 };
      if (shared) this.focusOn([A, L]);
      else this.focusOn([A, proj], 0.05);
      const color = kind === 'support' ? '#7fe0a0' : arrow ? '#e8dcc0' : (A.side === 'ally' ? '#8fd3ff' : '#c86bff');
      this.addFx({ kind: arrow ? 'arrow' : 'proj', dur, x0: sx, y0: sy, x1: tx, y1: ty, color, heavy: kind === 'arrowp', arc: arrow ? 10 : 26 * (this._eventIndex % 2 ? 1 : -1) });
      SFX(arrow ? 'whoosh' : 'magicCast', { vol: 0.6 });
      this.tween(proj, { x: tx, y: ty + 60 }, dur, 'in');
      if (!shared) {
        await this.wait(dur * 0.4);
        this.focusOn([proj, L], 0.08);       // passa a priorizar o alvo
        await this.wait(dur * 0.6);
        this.focusOn([L], 0.12);             // impacto e reação com o defensor visível
      } else await this.wait(dur);
      return dir;
    }

    // Um golpe individual (cosmético: varia por "motion"; não muda nada da lógica).
    async _strikeMotion(A, L, motion, others = [], prepped = false) {
      const dir = L.x >= A.x ? 1 : -1;
      this.faceTo(A, L);
      this.setState(A, 'ATTACKING');
      if (motion === 'proj') {
        if (!prepped) { SFX('magicCharge', { vol: 0.4 }); await this.tween(A, { cast: 1, arm: -0.6 }, 110); }
        this.tween(A, { arm: 0.3, lean: 0.08 }, 90);
        await this._fireProjectile(A, L, 'magic');
        return dir;
      }
      if (motion === 'arrow' || motion === 'arrowp') {
        // prepara o arco, puxa a corda, mira, solta e sente o recuo
        if (!prepped) { SFX('bowDraw', { vol: 0.6 }); await this.tween(A, { cast: 1, lean: -0.06, arm: -0.1 }, motion === 'arrowp' ? 420 : 200, 'out'); if (motion === 'arrowp') await this.wait(120); }
        SFX('bowRelease');
        this.tween(A, { cast: 0, lean: -0.14 }, 70, 'out').then(() => this.tween(A, { lean: 0 }, 220, 'inOut'));
        await this._fireProjectile(A, L, motion);
        return dir;
      }
      // abre espaço: outro atacante no ponto de golpe dá um passo atrás (coreografia)
      const reach = MOVE[A.art].reach * (motion === 'punch' || motion === 'punch2' || motion === 'upper' ? 1 : 1);
      const standX = L.x - dir * reach;
      let standY = A.y;
      for (const o of others) {
        if (o === A || o.dead || Math.abs(o.x - standX) > 60) continue;
        this.tween(o, { x: o.x - dir * 55, lean: -0.1 }, 160, 'out');
        standY = clamp(L.y + (L.y > (ARENA.minY + ARENA.maxY) / 2 ? -34 : 34), ARENA.minY, ARENA.maxY);
      }
      if (Math.abs(A.x - standX) > 18 || Math.abs(A.y - standY) > 10) {
        A.dashing = true;
        await this.moveTo(A, standX, standY, (motion === 'lunge' ? 100 : 130) * MOVE[A.art].dash, 'in');
        A.dashing = false;
      }
      const tipX = A.x + dir * reach, hy = L.y - 72;
      switch (motion) {
        case 'thrust': case 'lunge': {
          // estocada: recolhe, projeta o corpo e a ponta da lança (rastro linear)
          // nivela a lança (arm ≈ 1.3 = horizontal), recolhe e projeta
          await this.tween(A, { arm: 1.0, lean: -0.1 }, motion === 'lunge' ? 70 : 90, 'out');
          this.tween(A, { arm: 1.3, lean: 0.3, x: A.x + dir * (motion === 'lunge' ? 26 : 14) }, 60, 'in');
          await this.wait(40);
          this.addFx({ kind: 'thrust', dur: 220, x0: A.x + dir * 40, y0: A.y - 82, x1: L.x - dir * 6, y1: hy, color: motion === 'lunge' ? '#ffe9b0' : '#e8f2ff', w: motion === 'lunge' ? 9 : 6 });
          SFX('thrust', { vol: motion === 'lunge' ? 1 : 0.8 });
          return dir;
        }
        case 'sweep':
          await this.tween(A, { arm: -1.4, lean: -0.15 }, 140, 'out');
          this.tween(A, { arm: 1.0, lean: 0.2 }, 110, 'in');
          SFX('swish', { pitch: 0.8 });
          await this.wait(70);
          this.addFx({ kind: 'slash', dur: 300, x: L.x - dir * 50, y: hy + 6, dir, heavy: true, rot: 0.25, r: 115, color: '#e8f2ff' });
          return dir;
        case 'punch': case 'punch2': {
          // passos curtos, ombro e soco rápido
          this.tween(A, { x: A.x + dir * 8, lean: 0.12 }, 50, 'out');
          await this.tween(A, { arm: -0.3 }, 45, 'out');
          this.tween(A, { arm: 1.0, lean: 0.22 }, 50, 'in');
          await this.wait(35);
          this.addFx({ kind: 'punch', dur: 180, x: L.x - dir * 24, y: hy + (motion === 'punch2' ? 14 : -6), dir, color: '#fff0d6' });
          this.tween(A, { arm: 0.2, lean: 0.05 }, 110, 'out');
          return dir;
        }
        case 'upper':
          await this.tween(A, { crouch: 0.22, arm: -0.7, lean: -0.05 }, 140, 'out');
          this.tween(A, { crouch: 0, arm: 1.3, lean: -0.15, hop: 14 }, 90, 'in').then(() => this.tween(A, { hop: 0 }, 150, 'in'));
          await this.wait(60);
          this.addFx({ kind: 'slash', dur: 260, x: L.x - dir * 20, y: hy + 10, dir, heavy: true, rot: -1.25, r: 60, color: '#ffe9b0' });
          return dir;
      }
      const heavy = motion === 'over';
      await this.tween(A, { arm: heavy ? -1.7 : -1.2, lean: heavy ? -0.2 : 0.05 }, heavy ? 120 : 60, 'out');
      this.tween(A, { arm: 1.3, lean: 0.25 }, 70, 'in');
      SFX('swish', { vol: 0.7, pitch: heavy ? 0.75 : 1 });
      await this.wait(45);
      if (motion === 'bash') {
        this.tween(A, { x: A.x + dir * 20, guard: 1 }, 80, 'out');
        this.addFx({ kind: 'ring', dur: 260, x: L.x - dir * 28, y: hy, color: '#cfe3ff', r: 40 });
      } else {
        const rot = motion === 'd' ? 0.55 : motion === 'over' ? -0.85 : 0;
        this.addFx({ kind: 'slash', dur: 240, x: L.x - dir * 30, y: L.y - 70, dir, heavy, rot, flip: motion === 'h2', color: '#fff3d6' });
      }
      return dir;
    }
    // Crítico: flash e partículas mais fortes, número destacado, som próprio (varia pelo tipo de golpe)
    _critFx(L, dir, motion) {
      SFX('crit');
      const x = L.x - dir * 18, y = L.y - 74;
      this.flashAt(x, y, '#ffcf6a', 120);
      this.sparks(x, y, '#ffcf6a', 26, 0.8);
      this.float(L.x, L.y - 168, 'CRÍTICO', '#ffb347', 20, 1000);
      if (motion === 'proj') this.addFx({ kind: 'ring', dur: 480, x, y, color: '#ffcf6a', r: 95 });
      else if (motion === 'punch' || motion === 'punch2' || motion === 'upper') this.addFx({ kind: 'star', dur: 380, x, y, color: '#ffcf6a' });
      else if (motion === 'arrow' || motion === 'arrowp' || motion === 'thrust' || motion === 'lunge') this.addFx({ kind: 'thrust', dur: 260, x0: x - dir * 120, y0: y, x1: x + dir * 40, y1: y, color: '#ffcf6a', w: 10 });
      else this.addFx({ kind: 'slash', dur: 300, x: L.x - dir * 30, y: L.y - 70, dir, heavy: true, rot: 0.9, flip: true, color: '#ffcf6a' });
    }
    // som do contato conforme o tipo de golpe
    _hitSound(motion, blocked, last, heavy) {
      if (blocked) return SFX('block');
      const m = { proj: 'magicHit', arrow: 'arrowHit', arrowp: 'arrowHit', bash: 'shield', punch: 'punch', punch2: 'punch', upper: 'punch' }[motion] || 'slash';
      SFX(m, { vol: last ? 1 : 0.75 });
      if (heavy && last) SFX('heavy', { vol: 0.7 });
    }
    // Executa a sequência de golpes de uma habilidade (ou combinação) já vencida/acertada.
    // total/hpBefore/hpAfter vêm da lógica: a soma dos impactos é exatamente o dano real.
    async _sequence(attackers, L, sk, hit, finalLv, opts = {}) {
      const steps = this._steps(sk);
      const dmgs = this._splitDamage(hit.damage, steps.map(s => s.share));
      const dmgColor = L.side === 'ally' ? '#ff6a5a' : '#ffe08a';
      let hp = hit.hpBefore, lv = finalLv;
      // Postura: um único orçamento de Pressão, distribuído pelos golpes na ordem real
      const pz = opts.posture && !hit.killed ? opts.posture : null;
      const pDrops = pz ? this._splitDamage(pz.before - pz.after, steps.map(s => s.share)) : null;
      let pNow = pz ? pz.before : 0, pBrokeShown = false;
      if (pz) L.post = pz.before;
      for (let i = 0; i < steps.length; i++) {
        const st = steps[i], last = i === steps.length - 1;
        let A = attackers[st.by] || attackers[0];
        if (!A || A.dead) A = attackers.find(a => a && !a.dead) || attackers[0];
        const ranged = ['proj', 'arrow', 'arrowp'].includes(st.motion);
        if (attackers.length > 1) this.focusOn([...attackers.filter(a => !a.dead), L], 0.05);
        else if (!ranged) this.focusOn([A, L], 0.05);
        let dir = L.x >= A.x ? 1 : -1;
        if (i > 0 || !opts.firstDone) dir = await this._strikeMotion(A, L, st.motion, attackers, i === 0 && opts.prepped);
        // contato: só agora o dano aparece
        hp = last ? hit.hpAfter : Math.max(hit.hpAfter, hp - dmgs[i]);
        L.hp = hp;
        L.flash = 1;
        const lvHere = st.react === 'final' ? finalLv : st.react;
        const strong = last && (lvHere === 'heavy' || lvHere === 'extreme' || hit.killed);
        this._hitSound(st.motion, opts.blocked, last, strong);
        { const kind = opts.blocked ? 'metal' : st.motion === 'proj' ? 'magic' : /punch|upper/.test(st.motion) ? 'body' : /thrust|lunge|arrow/.test(st.motion) ? 'pierce' : 'metal';
          this._impactBurst(L.x - dir * 18, L.y - 72, dir > 0 ? 0 : Math.PI, opts.blocked ? '#cfe3ff' : kind === 'magic' ? (A.side === 'ally' ? '#9ad8ff' : '#d38bff') : '#ffd2a0', last ? (strong ? 1.25 : 0.95) : 0.7, kind);
          if (last && strong) this.dust(L, 8); }
        if (last && hit.elem) this.float(L.x + 50, L.y - 112, hit.elem > 0 ? '▲ VANTAGEM' : '▼ DESVANTAGEM', hit.elem > 0 ? '#7fe0a0' : '#ff9a8a', 12, 1000);
        if (st.motion === 'proj' || strong) this.flashAt(L.x - dir * 18, L.y - 72, st.motion === 'proj' ? (A.side === 'ally' ? '#8fd3ff' : '#c86bff') : '#ffe2b0', strong ? 90 : 60);
        const big = last && (hit.killed || steps.length === 1);
        const crit = hit.crit && last; // crítico: decidido uma vez pela lógica; destacado no golpe final
        if (crit) this._critFx(L, dir, st.motion);
        this.float(L.x + (i % 2 ? 14 : -14), L.y - 128 - i * 10, String(dmgs[i]), crit ? '#ffb347' : dmgColor, crit ? 50 : big ? (hit.killed ? 46 : 32) : 24, big || crit ? 1400 : 900);
        // hit-stop: quase nada nos golpes intermediários, mais forte no golpe final pesado
        this.hitStop(crit ? G.CONFIG.crit.hitstop : last ? (strong ? 110 : 65) : 22);
        this.hurtShake(last ? 2 + dmgs[i] * 0.35 + (crit ? 5 : 0) : 0, dir);
        // Postura do perdedor do Clash cai junto com o contato
        if (pz) {
          pNow = last ? pz.after : Math.max(pz.after, pNow - pDrops[i]);
          L.post = pNow;
          if (last && pz.before - pz.after >= 25) { L.postFlash = 1; this.tween(L, { guard: 0, arm: 0.6 }, 90, 'out'); } // guarda cede
          if (pz.broke && !pBrokeShown && pNow <= 0) { pBrokeShown = true; this.wait(crit ? 140 : 0).then(() => this._postureBreak(L, dir)); }
          if (last) {
            this.float(L.x + 62, L.y - 140, `−${pz.before - pz.after}`, '#d9b85c', 15, 1100); // perto da barra de Postura
            if (!pz.broke) SFX('pressure', { vol: 0.6 });
            if (pz.held) this.statusIcon(L, 'stable', '#9fe0c8');
          }
        }
        lv = lvHere;
        if (opts.blocked) lv = LEVELS[Math.max(0, LEVELS.indexOf(lv) - 1)];
        if (!last) {
          // reação intermediária sincronizada com o contato (sem travar a sequência)
          const push = lv === 'light' ? 14 : 34;
          this.tween(L, { x: clamp(L.x + dir * push * MOVE[L.art].knock, ARENA.minX, ARENA.maxX), lean: lv === 'light' ? -0.25 : -0.4 }, 90, 'out')
            .then(() => this.tween(L, { lean: -0.1 }, 120));
          if (lv !== 'light') this.dust(L, 4);
          await this.wait(ranged ? 40 : 70);
        } else if (opts.blocked) {
          const slide = lv === 'heavy' || lv === 'extreme' ? 60 : lv === 'medium' ? 35 : 18;
          this.routine(L, async () => {
            this.dust(L, 5);
            await this.tween(L, { x: clamp(L.x + dir * slide * MOVE[L.art].knock, ARENA.minX, ARENA.maxX), lean: -0.12, crouch: 0.08 }, 220, 'out');
            await this.tween(L, { lean: 0, crouch: 0 }, 200);
            this.setState(L, 'BLOCKING');
          });
          if (hit.killed) this.react(L, 'heavy', dir, true);
        } else this.react(L, lv, dir, hit.killed);
      }
      if (steps.length > 1) this.float(L.x, L.y - 205, `Total ${hit.damage}`, '#ffe9b0', 18, 1200);
      // depois de golpes fortes o atacante mostra o esforço (recuperação mais lenta)
      for (const a of attackers) if (a && !a.dead) this.followThrough(a, finalLv === 'extreme' || finalLv === 'heavy');
      return lv;
    }

    // ============================================================ CLASH EM BATIDAS — EMBLEMAS + COREOGRAFIA
    // Só REPRODUZ o registro da lógica (ev.a.steps / ev.b.steps / ev.beats): nada é sorteado aqui.
    // ClashBadgeRenderer: emblema com número grande, marcadores de batida, "+N" e faixa com o nome da habilidade.
    // ClashBeatAnimator: cada batida tem um padrão diferente (alto / baixo / investida), com pressão visual.
    _material(sk, v) {
      const m = (sk.hits || [])[0] ? sk.hits[0].motion : '';
      if (sk.tags.includes('magic')) return 'magic';
      if (/punch|upper/.test(m)) return 'body';
      if (/thrust|lunge|arrow/.test(m) || sk.tags.includes('ranged')) return 'pierce';
      if (v.art === 'knight' || v.art === 'brute') return 'shield';
      return 'metal';
    }
    async _clashBeats(ev, A, B, P, hy, skA, skB) {
      const left = A.x <= B.x;
      const name = (sd, v, sk) => sk.combo ? [v, ...(sd.partners || []).map(id => this.vis[id])].map(x => x.name).join(' + ') : v.name;
      const mk = (sd, v, sk) => ({ team: v.side, name: name(sd, v, sk), skill: sk.name, combo: !!sk.combo, val: sd.start, disp: sd.start,
        imp: null, impA: 0, impY: 0, pips: sd.beats, used: 0, lead: 0, win: 0, a: 0, s: 0.4, pulse: 0, flash: 0, hold: false, shake: 0 });
      const pa = mk(ev.a, A, skA), pb = mk(ev.b, B, skB);
      // ClashBadgePositioner: cada emblema fica ancorado no SEU personagem (acima das barras, fora do rosto);
      // a faixa do nome cresce para fora do confronto; a posição é recalculada a cada quadro (_placeHud)
      const badges = [pa, pb];
      // AdaptiveClashHUD: UMA barra compartilhada (esquerda = aliado, direita = inimigo)
      const hud = { hud: true, L: pa.team === 'ally' ? pa : pb, R: pa.team === 'ally' ? pb : pa, w: 0, x: (A.x + B.x) / 2, y: null, ten: 0 };
      pa.ref = A; pb.ref = B;
      if (!this.skipping) this.plates.push(hud);
      const ranged = [skA, skB].some(sk => sk.tags.includes('magic') || sk.tags.includes('ranged'));
      // RangedClashController: melee × ranged = o melee intercepta/desvia os projéteis no lugar
      const mixed = isRanged(skA) !== isRanged(skB);
      const MV = mixed ? (isRanged(skA) ? B : A) : null, RV = mixed ? (MV === A ? B : A) : null;
      const RS = mixed ? (RV === A ? skA : skB) : null;
      const mSide = mixed ? (MV === A ? 'a' : 'b') : null;
      const matA = this._material(skA, A), matB = this._material(skB, B);
      const mats = [matA, matB];
      const mat = mats.includes('magic') ? 'magic' : mats.includes('body') ? 'body' : mats.includes('pierce') ? 'pierce' : mats.includes('shield') ? 'shield' : 'metal';
      SFX('clashTense', { vol: 0.6 });
      await Promise.all(badges.map(b => this.tween(b, { a: 1, s: 1 }, 130, 'back')));
      const dirOf = v => (v === A ? (B.x >= A.x ? 1 : -1) : (A.x >= B.x ? 1 : -1));
      const PAT = [
        { dy: -26, wind: { arm: -1.5, lean: -0.2 }, strike: { arm: 1.15, lean: 0.3 }, step: 14 },               // alto
        { dy: 16, wind: { arm: 0.5, lean: -0.1, crouch: 0.14 }, strike: { arm: -0.9, lean: 0.24, crouch: 0.06 }, step: 10 }, // baixo / mudança de direção
        { dy: -6, wind: { arm: -1.7, lean: -0.28, crouch: 0.08 }, strike: { arm: 1.35, lean: 0.42 }, step: 26 },  // investida (mais agressiva)
      ];
      let lastLead = null;
      const n = ev.beats.length;
      for (let i = 0; i < n; i++) {
        const last = i === n - 1, bt = ev.beats[i], sa = ev.a.steps[i], sb = ev.b.steps[i];
        const pat = last && n > 1 ? PAT[2] : PAT[i % 2];
        const contact = mixed ? { x: MV.x + dirOf(MV) * 46, y: MV.y - 86 + pat.dy * 0.6 } : { x: P.x, y: hy + pat.dy };
        if (mixed) { await this._deflectBeat(MV, RV, RS, contact, i, last, bt, mSide, dirOf); }
        else {
        // 1. preparação (quem perdeu terreno na batida anterior arma um golpe maior para recuperar)
        const prep = [];
        for (const [v, st, isA] of [[A, sa, true], [B, sb, false]]) {
          const d = dirOf(v), wasBehind = lastLead && lastLead !== (isA ? 'a' : 'b');
          if (st.imp == null) prep.push(this.tween(v, { crouch: 0.14, guard: 1, lean: 0.1, arm: -0.4 }, 80, 'out'));   // sustenta a guarda
          else prep.push(this.tween(v, Object.assign({}, pat.wind, { x: v.x - d * (8 + (wasBehind ? 8 : 0)) }), last ? 95 : 70, 'out'));
        }
        await Promise.all(prep);
        // 2. golpe/disparo até o contato
        if (ranged) {
          for (const [v, st] of [[A, sa], [B, sb]]) {
            if (st.imp == null) continue;
            const arrow = (v === A ? skA : skB).tags.includes('ranged'), magic = (v === A ? skA : skB).tags.includes('magic');
            if (arrow || magic) this.addFx({ kind: arrow ? 'arrow' : 'proj', dur: 130, x0: v.x + dirOf(v) * 30, y0: v.y - 110, x1: contact.x, y1: contact.y, color: magic ? (v.side === 'ally' ? '#8fd3ff' : '#c86bff') : '#e8dcc0', arc: 6 });
            this.tween(v, Object.assign({}, pat.strike, { x: v.x + dirOf(v) * (arrow || magic ? 4 : pat.step) }), 70, 'in');
          }
          await this.wait(130);
        } else {
          for (const [v, st] of [[A, sa], [B, sb]]) if (st.imp != null) this.tween(v, Object.assign({}, pat.strike, { x: v.x + dirOf(v) * pat.step }), 60, 'in');
          await this.wait(55);
        }
        }
        // 3. CONTATO: impacto + som + micro-pausa (mais forte na última batida)
        SFX(last && n > 1 ? 'beatFinal' : ({ magic: 'beatMagic', body: 'beatThud', pierce: 'beatPierce', shield: 'beatShield' }[mat] || (i % 2 ? 'beatClang' : 'beatTin')), { vol: last ? 1 : 0.8, pitch: 1 + i * 0.07 });
        this.hitStop(last ? 60 : 28);
        const leadSide = bt.lead === 'a' ? A : bt.lead === 'b' ? B : null;
        const ang = leadSide ? (dirOf(leadSide) > 0 ? 0 : Math.PI) : -Math.PI / 2;
        if (!mixed) this._impactBurst(contact.x, contact.y, ang, mat === 'magic' ? '#c8a0ff' : mat === 'body' ? '#ffe2c0' : '#fff2c0', last ? 1.2 : 0.8, mat);
        this.hurtShake(last ? 5 : 2, leadSide ? dirOf(leadSide) : 0);
        // 4. revelação do impulso (pequeno, acima do emblema) e atualização rápida do número
        await this.wait(40);
        let maxImp = 0;
        for (const [bd, st] of [[pa, sa], [pb, sb]]) {
          bd.hold = st.imp == null;
          if (st.imp == null) continue;
          bd.used = i + 1; bd.imp = `+${st.imp}`; bd.impA = 1; bd.impY = 0; maxImp = Math.max(maxImp, st.imp);
          this.tween(bd, { impY: 1 }, 90, 'out').then(() => { bd.val = st.total; bd.pulse = 1; return this.tween(bd, { disp: st.total }, 70, 'out'); }).then(() => this.tween(bd, { impA: 0 }, 140));
        }
        SFX('reveal', { vol: 0.55, pitch: 1 + maxImp * 0.12 });
        await this.wait(95);
        SFX('tick', { vol: 0.45, pitch: 1.1 + i * 0.08 });
        // 5. domínio parcial: quem lidera pressiona; quem perde recua e a guarda sofre (sem dano nem Postura)
        const lead = bt.lead, margin = Math.abs(bt.a - bt.b);
        pa.lead = lead === 'a' ? 1 : lead ? -1 : 0; pb.lead = lead === 'b' ? 1 : lead ? -1 : 0;
        if (lead && lastLead && lead !== lastLead) { SFX('leadSwap', { vol: 0.7 }); (lead === 'a' ? pa : pb).flash = 1; }
        if (mixed) {
          // à distância: só quem está no lugar reage (o atirador não é empurrado do outro lado da arena)
          if (lead && lead !== mSide) { const d = dirOf(RV); this.tween(MV, { x: clamp(MV.x + d * Math.min(26, 8 + margin * 5), ARENA.minX, ARENA.maxX), lean: -0.3, crouch: 0.1 }, 100, 'out'); (mSide === 'a' ? pa : pb).shake = 1; this.dust(MV, 3); }
          else if (lead === mSide) { this.tween(MV, { lean: 0.2, x: MV.x + dirOf(MV) * 6 }, 90, 'out'); (mSide === 'a' ? pb : pa).shake = 1; }
        } else if (lead) {
          const W = lead === 'a' ? A : B, Lz = lead === 'a' ? B : A, d = dirOf(W), push = Math.min(30, 8 + margin * 5);
          this.tween(W, { x: W.x + d * push * 0.6, lean: 0.36 }, 90, 'out');
          this.tween(Lz, { x: clamp(Lz.x + d * push, ARENA.minX, ARENA.maxX), lean: -0.22 - margin * 0.03, guard: Lz.art === 'knight' ? 0.5 : Lz.guard, crouch: 0.08 }, 100, 'out');
          (lead === 'a' ? pb : pa).shake = 1;
          if (margin >= 3) this.dust(Lz, 4);
        } else {
          // empate na batida: armas travadas, os dois fazem força
          this.tween(A, { lean: 0.26 }, 70); this.tween(B, { lean: 0.26 }, 70);
          this.sparks(contact.x, contact.y, '#ffe28a', 4, 0.25);
        }
        lastLead = lead || lastLead;
        await this.wait(last ? 110 : 55);
      }
      // conclusão: maior força acumulada vence (sem tela de resultado)
      SFX('clashFinal', { vol: ev.close ? 1 : 0.85 });
      if (ev.winner) {
        const bw = ev.winner === A.id ? pa : pb, bl = bw === pa ? pb : pa;
        bw.win = 1; bl.win = -1; bw.flash = 1; bl.shake = 1;
        this.tween(bw, { s: 1.22 }, 130, 'back'); this.tween(bl, { s: 0.86 }, 130, 'out');
      } else { pa.win = pb.win = 2; this.sparks(P.x, hy, '#e8dccb', 10, 0.4); }
      await this.wait(ev.winner ? 150 : 220);
      return badges;
    }

    // ProjectileDeflectionAnimator: o projétil vem, o melee intercepta com a SUA arma/corpo e o projétil
    // é desviado (melee lidera), passa pela defesa (ranged lidera) ou se dissipa (empate na batida).
    async _deflectBeat(MV, RV, RS, contact, i, last, bt, mSide, dirOf) {
      const arrow = RS.tags.includes('ranged');
      const color = arrow ? '#e8dcc0' : (RV.side === 'ally' ? '#8fd3ff' : '#c86bff');
      const dur = clamp(150 + Math.abs(contact.x - RV.x) * 0.12, 160, 260);
      // atirador dispara (variações: arco do projétil e intensidade na última batida)
      if (arrow) { this.tween(RV, { cast: 1 }, 60).then(() => this.tween(RV, { cast: 0, lean: -0.1 }, 60)); SFX('bowRelease', { vol: 0.6 }); }
      else { this.tween(RV, { cast: 1, arm: 0.3 }, 70); SFX('magicCast', { vol: 0.5 }); }
      this.addFx({ kind: arrow ? 'arrow' : 'proj', dur, x0: RV.x + dirOf(RV) * 30, y0: RV.y - (arrow ? 96 : 112), x1: contact.x, y1: contact.y, color, arc: (i % 2 ? -1 : 1) * (arrow ? 6 : 18), heavy: last });
      // o melee se prepara e intercepta exatamente na chegada
      const G = { // pose de interceptação por classe: [preparo, golpe]
        swordsman: [{ arm: -1.5, lean: -0.08 }, { arm: 1.1, lean: 0.22 }], duelist: [{ arm: -1.2 }, { arm: 1.0, lean: 0.2 }],
        knight: i % 2 ? [{ arm: -1.3 }, { arm: 1.0, lean: 0.2 }] : [{ guard: 1.2, crouch: 0.1 }, { guard: 1.3, lean: 0.12 }], // escudo / espada
        brute: [{ guard: 1, crouch: 0.12 }, { arm: 0.9, lean: 0.2 }],
        lancer: i % 2 ? [{ arm: 0.4 }, { arm: 1.6, lean: 0.22 }] : [{ arm: 1.8 }, { arm: 0.6, lean: 0.18 }],  // estocada / varredura com a haste
        brawler: [{ arm: -0.4, crouch: 0.12, lean: -0.12 }, { arm: 0.6, lean: 0.12, crouch: 0.05 }],       // antebraço + desvio
      }[MV.art] || [{ guard: 1 }, { guard: 1.2 }];
      this.tween(MV, Object.assign({}, G[0]), Math.max(60, dur - 90), 'out');
      await this.wait(dur - 55);
      this.tween(MV, Object.assign({}, G[1]), 55, 'in');
      await this.wait(55);
      const melLead = bt.lead === mSide, rngLead = bt.lead && !melLead;
      if (melLead) {
        // desviado: muda de trajetória (para cima ou para o chão) e se apaga — nada atravessa o defensor
        const up = (i % 2 === 0), ang = (dirOf(RV) > 0 ? Math.PI : 0) + (up ? -0.9 : 0.75) * dirOf(MV);
        this.addFx({ kind: 'deflect', dur: 260, x: contact.x, y: contact.y, ang, color, size: last ? 1.3 : 1 });
        this._impactBurst(contact.x, contact.y, ang, '#fff2c0', last ? 1 : 0.7, MV.art === 'brawler' ? 'body' : 'metal');
      } else if (rngLead) {
        // passa pela defesa: impacto na guarda/corpo, recuo
        this._impactBurst(MV.x, MV.y - 80, dirOf(RV) > 0 ? 0 : Math.PI, color, last ? 1.2 : 0.85, arrow ? 'pierce' : 'magic');
        MV.flash = 0.5;
      } else {
        // empate na batida: dissipa na arma, com esforço
        this.addFx({ kind: 'ring', dur: 240, x: contact.x, y: contact.y, color, r: 30 });
        this._impactBurst(contact.x, contact.y, -Math.PI / 2, color, 0.6, 'magic');
      }
    }

    // CombatImpactFX: clarão direcional + estilhaços em cone + (pesado) onda de choque e poeira
    _impactBurst(x, y, ang, color, size = 1, kind = 'metal') {
      if (this.skipping) return;
      this.addFx({ kind: 'burst', dur: kind === 'magic' ? 220 : 150, x, y, ang, color, size, rays: kind === 'body' ? 6 : kind === 'magic' ? 10 : 8 });
      const n = Math.round((kind === 'magic' ? 10 : 12) * size);
      for (let i = 0; i < n; i++) {
        const a = ang + (Math.random() - 0.5) * (kind === 'magic' ? 3.2 : 1.3), sp = (0.35 + Math.random() * 0.55) * size;
        this.particles.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 0.1, g: kind === 'magic' ? -0.0002 : 0.0011, life: 180 + Math.random() * 220, color: kind === 'magic' ? color : (i % 3 ? '#ffe7b0' : '#ffffff'), r: 1.4 + Math.random() * 1.8 });
      }
      if (size >= 1.1) this.addFx({ kind: 'shock', dur: 260, x, y, r: 70 * size, color });
    }

    // ClashHUDPositioner: centro entre os combatentes, acima das barras, sempre dentro da tela;
    // largura acompanha a distância NA TELA (zoom incluso) com limites e interpolação suave.
    _placeHud(h) {
      const A = h.L.ref, B = h.R.ref, k = this.pxPerWorld || 1;
      const W = this.canvas.clientWidth, H = this.canvas.clientHeight;
      const tl = this.toWorld(0, 0), br = this.toWorld(W, H);
      const dxs = Math.abs(A.x - B.x) * k;
      const want = clamp(dxs * 0.78, 230, Math.min(620, W - 60));
      h.w = h.w ? h.w + (want - h.w) * 0.12 : want;
      const half = h.w / 2 / k;
      const top = Math.min(A.y - (A.hop || 0), B.y - (B.hop || 0)) - 228;
      let x = (A.x + B.x) / 2, y = top;
      if ((y - tl.y) * k < 104) y = tl.y + 104 / k; // espaço superior ocupado (HUD do topo): desce um pouco
      x = clamp(x, tl.x + half + 40 / k, br.x - half - 40 / k);
      y = Math.min(y, br.y - 150 / k);
      h.x = h.y == null ? x : h.x + (x - h.x) * 0.2; h.y = h.y == null ? y : h.y + (y - h.y) * 0.2;
      // vínculo com quem saiu do quadro
      h.edgeL = A.x < tl.x + 10 / k ? -1 : A.x > br.x - 10 / k ? 1 : 0;
      h.edgeR = B.x < tl.x + 10 / k ? -1 : B.x > br.x - 10 / k ? 1 : 0;
    }
    _drawClashHud(ctx, h) {
      const L = h.L, R = h.R, al = Math.min(L.a, R.a);
      if (al <= 0.01) return;
      this._placeHud(h);
      const k = this.pxPerWorld || 1, w = h.w, half = w / 2 - 34;
      const COL = { ally: { main: '#4fc8ff', glow: '#9fe8ff', dark: '#0e2433' }, enemy: { main: '#ff6a3c', glow: '#ffb070', dark: '#331208' } };
      const tie = L.win === 2;
      // marcador de tensão: aliado vencendo → esquerda; inimigo → direita
      const tgt = tie ? 0 : clamp((R.disp - L.disp) / 6, -1, 1);
      h.ten += (tgt - h.ten) * 0.18;
      ctx.save(); ctx.globalAlpha = al;
      ctx.translate(h.x, h.y); ctx.scale(1 / k, 1 / k); const sc = 0.92 + 0.08 * Math.min(L.s, 1); ctx.scale(sc, sc);
      // conexão central: duas linhas finas + rebites
      const lx = -half + 30, rx = half - 30;
      const g = ctx.createLinearGradient(lx, 0, rx, 0);
      g.addColorStop(0, COL.ally.main); g.addColorStop(0.5, tie ? '#e8dccb' : '#d8c8a8'); g.addColorStop(1, COL.enemy.main);
      ctx.fillStyle = 'rgba(8,5,12,0.72)'; ctx.fillRect(lx, -7, rx - lx, 14);
      ctx.strokeStyle = g; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(lx, -5); ctx.lineTo(rx, -5); ctx.moveTo(lx, 5); ctx.lineTo(rx, 5); ctx.stroke();
      ctx.fillStyle = 'rgba(200,190,170,0.5)';
      for (let x = lx + 18; x < rx - 10; x += 26) ctx.fillRect(x - 1, -1, 2, 2);
      // domínio: o lado que lidera "enche" o seu trecho com um brilho discreto
      const mx = -h.ten * (half - 60);
      if (Math.abs(h.ten) > 0.04) {
        const c = h.ten < 0 ? COL.ally : COL.enemy;
        const gg = ctx.createLinearGradient(h.ten < 0 ? lx : rx, 0, mx, 0); gg.addColorStop(0, c.main); gg.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.globalAlpha = al * 0.55; ctx.fillStyle = gg; ctx.fillRect(Math.min(h.ten < 0 ? lx : rx, mx), -3, Math.abs(mx - (h.ten < 0 ? lx : rx)), 6); ctx.globalAlpha = al;
      }
      // marcador de tensão (losango)
      const shk = (L.shake + R.shake) > 0.05 ? Math.sin(this.time * 0.1) * 2 : 0;
      ctx.save(); ctx.translate(mx + shk, 0); ctx.rotate(Math.PI / 4);
      ctx.fillStyle = tie ? '#e8dccb' : h.ten < -0.04 ? COL.ally.glow : h.ten > 0.04 ? COL.enemy.glow : '#f0e2c0';
      ctx.strokeStyle = '#0a0610'; ctx.lineWidth = 2; ctx.fillRect(-6, -6, 12, 12); ctx.strokeRect(-6, -6, 12, 12); ctx.restore();
      if (tie) { ctx.font = '800 10px "Trebuchet MS", sans-serif'; ctx.textAlign = 'center'; ctx.fillStyle = '#e8dccb'; ctx.fillText('EMPATE', 0, -14); }
      // extremidades
      for (const [p, side, d, edge] of [[L, 'ally', -1, h.edgeL], [R, 'enemy', 1, h.edgeR]]) {
        const C = tie ? { main: '#c8c0b8', glow: '#e8dccb', dark: '#2a2628' } : COL[side];
        const dim = p.win === -1 ? 0.5 : p.lead === -1 ? 0.8 : 1;
        const sh = p.shake > 0.05 ? Math.sin(this.time * 0.09) * 3 * p.shake : 0;
        ctx.save(); ctx.globalAlpha = al * dim; ctx.translate(d * half + sh, 0);
        const s2 = (p.win === 1 ? 1.12 : p.win === -1 ? 0.9 : 1) * (1 + p.pulse * 0.14); ctx.scale(s2, s2);
        const Rr = 25;
        ctx.beginPath(); for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4 + Math.PI / 8; ctx.lineTo(Math.cos(a) * (Rr + 5), Math.sin(a) * (Rr + 5)); } ctx.closePath();
        const mg = ctx.createLinearGradient(0, -Rr, 0, Rr); mg.addColorStop(0, '#5a5560'); mg.addColorStop(0.5, '#2a2530'); mg.addColorStop(1, '#4a4450');
        ctx.fillStyle = mg; ctx.fill(); ctx.lineWidth = 2; ctx.strokeStyle = C.main;
        if (p.lead === 1 || p.win === 1 || p.flash > 0.05) { ctx.shadowColor = p.win === 1 ? '#ffd36a' : C.glow; ctx.shadowBlur = 10 + p.flash * 16; }
        ctx.stroke(); ctx.shadowBlur = 0;
        const dg = ctx.createRadialGradient(0, -5, 3, 0, 0, Rr); dg.addColorStop(0, C.main); dg.addColorStop(0.55, C.dark); dg.addColorStop(1, '#08060a');
        ctx.fillStyle = dg; ctx.beginPath(); ctx.arc(0, 0, Rr - 2, 0, 7); ctx.fill();
        ctx.textAlign = 'center'; ctx.font = '900 27px "Trebuchet MS", sans-serif';
        ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(5,3,8,0.9)'; ctx.strokeText(String(Math.round(p.disp)), 0, 10);
        ctx.fillStyle = p.win === 1 ? '#ffe9a0' : '#fff'; ctx.shadowColor = C.glow; ctx.shadowBlur = 6 + p.pulse * 12;
        ctx.fillText(String(Math.round(p.disp)), 0, 10); ctx.shadowBlur = 0;
        // símbolo da equipe (inicial do personagem) na ponta externa
        ctx.fillStyle = C.dark; ctx.strokeStyle = C.main; ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.arc(d * 40, -14, 10, 0, 7); ctx.fill(); ctx.stroke();
        ctx.font = '900 11px "Trebuchet MS", sans-serif'; ctx.fillStyle = C.glow; ctx.fillText(p.name[0], d * 40, -10);
        // marcadores de batida
        for (let i = 0; i < p.pips; i++) {
          const px = (i - (p.pips - 1) / 2) * 10, used = i < p.used;
          ctx.save(); ctx.translate(px, Rr + 11); ctx.rotate(Math.PI / 4);
          ctx.fillStyle = used ? 'rgba(120,110,120,0.5)' : C.main; ctx.fillRect(-3, -3, 6, 6); ctx.restore();
        }
        // rótulo pequeno com a habilidade (fora da barra, para o lado externo)
        ctx.font = '800 10px "Trebuchet MS", sans-serif'; ctx.textAlign = d < 0 ? 'right' : 'left';
        ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(5,3,8,0.85)';
        const lbl = p.skill + (p.combo ? ' ⚔' : '');
        ctx.strokeText(lbl, d * 34, 30); ctx.fillStyle = '#f2e6cc'; ctx.fillText(lbl, d * 34, 30);
        // owner fora do quadro: seta na ponta
        if (edge) { ctx.fillStyle = C.main; ctx.beginPath(); ctx.moveTo(edge * 52, 4); ctx.lineTo(edge * 44, -2); ctx.lineTo(edge * 44, 10); ctx.fill(); }
        // "+N" do impulso
        if (p.impA > 0.01 && p.imp) {
          ctx.globalAlpha = al * p.impA; ctx.textAlign = 'center'; ctx.font = '900 15px "Trebuchet MS", sans-serif';
          const iy = -Rr - 12 + p.impY * 10;
          ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(5,3,8,0.9)'; ctx.strokeText(p.imp, 0, iy); ctx.fillStyle = '#9fffb0'; ctx.fillText(p.imp, 0, iy);
        }
        ctx.restore();
        p.flash = Math.max(0, p.flash - 0.05); p.pulse = Math.max(0, p.pulse - 0.08); p.shake = Math.max(0, p.shake - 0.06);
      }
      ctx.restore();
    }

    // ------------------------------------------------------------ CLASH
    async playClash(ev) {
      const A = this.vis[ev.a.actorId], B = this.vis[ev.b.actorId];
      const skA = G.SKILLS[ev.a.skillId], skB = G.SKILLS[ev.b.skillId];
      const magA = isRanged(skA), magB = isRanged(skB);
      const T = ev.intercept ? this.vis[ev.originalTargetId] : null;
      const pA = (ev.a.partners || []).map(id => this.vis[id]), pB = (ev.b.partners || []).map(id => this.vis[id]);
      const margin = ev.winner ? Math.abs(ev.a.total - ev.b.total) : 0;
      const variant = (this._eventIndex * 7 + (ev.a.roll + ev.b.roll)) % 3; // variação visual estável
      const names = (v, ps) => [v, ...ps].map(x => x.name).join(' + ');
      this.caption = `${skA.combo || skB.combo ? 'CLASH COMBINADO' : 'CLASH'}  ·  ${names(A, pA)} (${skA.name})  ×  ${names(B, pB)} (${skB.name})`;
      if (skA.combo || skB.combo) this.showBanner('ATAQUE COMBINADO', '#ffd36a', 900, (skA.combo ? names(A, pA) : names(B, pB)));

      // 1-2. participantes e posições ATUAIS
      this.focusOn([...(T ? [A, B, T] : [A, B]), ...pA, ...pB]);
      await this.sync(A, B, ...pA, ...pB);
      this.faceTo(A, B); this.faceTo(B, A);

      // 3. ponto de choque calculado dinamicamente
      let P;
      if (T) { const dir = B.x >= T.x ? 1 : -1; P = { x: T.x + dir * 120, y: T.y + 4 }; }
      else if (magA !== magB) { const M = magA ? B : A, O = magA ? A : B, d = O.x >= M.x ? 1 : -1; P = { x: M.x + d * MOVE[M.art].reach, y: M.y }; } // melee × ranged: o melee intercepta no lugar
      else P = { x: (A.x + B.x) / 2, y: (A.y + B.y) / 2 };
      P = this.clampPos(P.x, P.y);

      // antecipação (cada personagem com seu peso)
      const melee = v => !(v === A ? magA : magB);
      for (const v of [A, B]) {
        this.setState(v, 'PREPARING');
        this.tween(v, melee(v) ? { lean: -0.24, arm: -1.5, crouch: 0.1 } : { cast: 1, arm: -0.5, lean: -0.1 }, 200 * MOVE[v.art].dash);
      }
      if (T) {
        if (!magB) { this.setState(B, 'APPROACHING'); B.dashing = true; this.tween(B, { x: lerp(B.x, P.x, 0.45) }, 260, 'in'); }
        await this.wait(190);
        this.statusIcon(T, 'protect', '#9fd0ff', 1200); this.caption = `INTERCEPTAÇÃO  ·  ${A.name} protege ${T.name}  ·  ${skA.name} × ${skB.name}`;
        this.slowMo(0.5, 420);
      } else await this.wait(230);

      // 4. aproximação / projéteis
      const go = [];
      for (const v of [A, B]) {
        const dir = v === A ? (P.x >= A.x ? 1 : -1) : (P.x >= B.x ? 1 : -1);
        if (!melee(v) && magA !== magB) { this.tween(v, { cast: 0.8, arm: -0.3 }, 160); go.push(this.wait(160)); } // misto: só arma; os disparos são as batidas
        else if (!melee(v)) {
          this.tween(v, { arm: 0.3, lean: 0.08 }, 120);
          const arrow = (v === A ? skA : skB).tags.includes('ranged');
          if (arrow) { SFX('bowRelease'); this.tween(v, { cast: 0 }, 70); } else SFX('magicCast', { vol: 0.6 });
          this.addFx({ kind: arrow ? 'arrow' : 'proj', dur: 300, x0: v.x + v.face * 30, y0: v.y - (arrow ? 96 : 115), x1: P.x, y1: P.y - 75, color: arrow ? '#e8dcc0' : (v.side === 'ally' ? '#8fd3ff' : '#c86bff') });
          go.push(this.wait(300));
        } else {
          this.setState(v, 'APPROACHING');
          v.dashing = true;
          const reach = MOVE[v.art].reach;
          go.push(this.moveTo(v, P.x - dir * reach, P.y + (v === A ? 5 : -5), (v === A && T ? 220 : 210) * MOVE[v.art].dash, 'in')
            .then(() => { v.dashing = false; this.tween(v, { arm: variant === 1 ? 0.6 : 1.1, lean: 0.25 }, 70, 'in'); }));
        }
      }
      // parceiros de combinação chegam junto, logo atrás do líder
      if (pA.length) go.push(this._bringPartners(pA, A, P.x, P.y));
      if (pB.length) go.push(this._bringPartners(pB, B, P.x, P.y));
      await Promise.all(go);
      for (const v of [A, B]) this.setState(v, 'CLASHING');
      this.focusOn([A, B], 0.1);

      // 5–6. batidas do Clash (choques sucessivos, força acumulada, sons sincronizados)
      const hy = P.y - (variant === 0 ? 95 : variant === 1 ? 55 : 75);
      const plates = await this._clashBeats(ev, A, B, P, hy, skA, skB);
      const fadePlates = (ms) => plates.forEach(p => this.tween(p, { a: 0 }, ms, 'in'));

      if (!ev.winner) {
        // empate: as forças se anulam e os dois são repelidos
        SFX('block');
        fadePlates(320);
        this.sparks(P.x, hy, '#ffe28a', 14, 0.5);
        this.react(A, 'medium', A.x < P.x ? -1 : 1);
        this.react(B, 'medium', B.x < P.x ? -1 : 1);
        [...pA, ...pB].forEach(p => this.react(p, 'light', p.x < P.x ? -1 : 1));
        await this.wait(380);
      } else {
        const aWins = ev.winner === A.id;
        const [W, L, skW, pW, pL] = aWins ? [A, B, skA, pA, pB] : [B, A, skB, pB, pA];
        pL.forEach(p => this.react(p, 'light', p.x < P.x ? -1 : 1)); // a combinação perdida é interrompida
        const dirL = L.x >= W.x ? 1 : -1;
        SFX(W.side === 'ally' ? 'clashWin' : 'clashLose', { vol: 0.6 });
        fadePlates(420); // as placas saem enquanto o vencedor parte para o golpe
        // 7. intensidade visual pela margem (não muda o dano)
        if (margin <= 2) {
          // por pouco: o vencedor empurra a guarda devagar
          await Promise.all([this.tween(W, { x: W.x + dirL * 22, lean: 0.35 }, 260, 'inOut'), this.tween(L, { x: L.x + dirL * 26, lean: -0.15 }, 260, 'inOut')]);
        } else if (margin <= 4) {
          this.sparks(P.x, hy, '#ffe28a', 10, 0.5);
          await this.tween(L, { x: clamp(L.x + dirL * 50, ARENA.minX, ARENA.maxX), lean: -0.4, arm: -0.3 }, 180, 'out');
        } else {
          // domina: rompe a guarda
          this.addFx({ kind: 'ring', dur: 300, x: P.x, y: hy, color: '#ffe28a', r: 50 });
          this.hurtShake(6);
          await this.tween(L, { x: clamp(L.x + dirL * 70, ARENA.minX, ARENA.maxX), lean: -0.6, arm: 0.4, crouch: 0.12 }, 160, 'out');
        }
        // golpe(s) do vencedor: sequência configurada da habilidade/combinação
        const h = ev.hit;
        const marginLv = margin >= 5 ? 'heavy' : margin >= 3 ? 'medium' : 'light';
        const lv = LEVELS[Math.max(LEVELS.indexOf(h.impact || 'light'), LEVELS.indexOf(marginLv))];
        await this._sequence([W, ...pW], L, skW, h, lv, { posture: ev.posture });
        if (h.applied) { const st = G.STATUS[h.applied]; this.float(L.x, L.y - 165, st.name.toUpperCase(), st.color, 20, 1300); }
        if (h.killed || lv === 'extreme') await this._decisive(L, h.killed);
        await this.wait(lv === 'light' ? 220 : 320);
      }
      this.plates = this.plates.filter(p => !(p.L && plates.includes(p.L)));
      this.caption = null;
    }

    // ------------------------------------------------------------ ATAQUE SEM OPOSIÇÃO
    async playConfrontation(c) {
      const sk = c.skill;
      const A = this.vis[c.attackerId], T = this.vis[c.targetId], D = this.vis[c.defenderId];
      const P = c.protectorId ? this.vis[c.protectorId] : null;
      const partners = (c.partners || []).map(id => this.vis[id]);
      const magic = isRanged(sk), heavy = sk.tags.includes('heavy'), fast = sk.tags.includes('fast');
      const arrow = sk.tags.includes('ranged');
      this.caption = `${[A, ...partners].map(v => v.name).join(' + ')}  ·  ${sk.name}  →  ${T.name}`;
      if (sk.combo) this.showBanner('ATAQUE COMBINADO', '#ffd36a', 900, [A, ...partners].map(v => v.name).join(' + '));

      this.focusOn([A, T, ...partners]);
      await this.sync(A, ...partners);
      this.faceTo(A, T);

      // antecipação
      this.setState(A, 'PREPARING');
      if (arrow) {
        // prepara o arco e puxa a corda (mais tempo para a Flecha Perfurante)
        SFX('bowDraw', { vol: 0.6 });
        await this.tween(A, { cast: 1, lean: -0.06, arm: -0.1 }, 230 * (sk.windup || 1), 'out');
        await this.wait(80 * (sk.windup || 1));
      } else if (magic) {
        SFX('magicCharge', { vol: 0.5 });
        this.tween(A, { cast: 1, lean: -0.1, arm: -0.5 }, 260);
        for (let i = 0; i < 3; i++) { this.sparks(A.x + A.face * 26, A.y - 112, '#9ad8ff', 6, 0.18, -0.0005); await this.wait(90); }
      } else {
        // variação cosmética da preparação (o peso do personagem é mantido)
        const vr = (this._eventIndex % 3) * 0.04;
        const wu = (sk.windup || 1) * (heavy ? 380 : fast ? 130 : 220) * MOVE[A.art].dash;
        await this.tween(A, { lean: -0.18 - vr, arm: -1.4 - vr * 2, crouch: 0.06 + vr }, wu, 'out');
        if (heavy) await this.wait(90 * (sk.windup || 1));
      }

      // intervenção: o protetor entra fisicamente no caminho
      if (P) {
        await this.sync(P);
        this.statusIcon(T, 'protect', '#9fd0ff', 1100);
        this.slowMo(0.45, 480);
        this.focusOn([A, P, T]);
        const dir = A.x >= T.x ? 1 : -1;
        P.dashing = true;
        this.setState(P, 'APPROACHING');
        this.faceTo(P, A);
        await Promise.all([this.moveTo(P, T.x + dir * 78, T.y + 6, 260, 'out'), this.tween(P, { guard: 1, lean: 0.15 }, 200)]);
        P.dashing = false;
        this.sparks(P.x, P.y - 10, '#c8d6ff', 10, 0.3);
        await this.wait(90);
      }
      await this.sync(D);
      this.faceTo(D, A);

      // avanço / projétil + reação do defensor
      const dirD = D.x >= A.x ? 1 : -1;
      let fired = true;
      if (magic) {
        this.tween(A, { arm: 0.3, lean: 0.08 }, 120);
        if (['dodged', 'parried'].includes(c.outcome)) {
          // o projétil chega e é evitado: dispara aqui (câmera acompanha até o alvo)
          this._react(c, D, A, 200);
          if (arrow) { SFX('bowRelease'); this.tween(A, { cast: 0 }, 70); }
          await this._fireProjectile(A, D, arrow ? 'arrow' : 'magic');
        } else {
          // quem acerta dispara dentro da sequência (cada impacto no seu contato)
          fired = false;
          if (c.reaction === 'block') this._react(c, D, A, 120);
        }
      } else {
        this.setState(A, 'APPROACHING');
        A.dashing = true;
        const dash = this.moveTo(A, D.x - dirD * MOVE[A.art].reach, D.y + 2, (fast ? 130 : heavy ? 230 : 175) * MOVE[A.art].dash, 'in');
        this.tween(A, { lean: 0.25, crouch: 0 }, 150);
        this._react(c, D, A, fast ? 80 : 120);
        if (partners.length) this._bringPartners(partners, A, D.x, D.y);
        await dash;
        A.dashing = false;
        this.setState(A, 'ATTACKING');
        this.tween(A, { arm: 1.3 }, fast ? 70 : 100, 'in');
        await this.wait(fast ? 45 : 70);
        // primeiro golpe: usa o movimento da habilidade (estocada, soco, corte...)
        const m0 = this._steps(sk)[0].motion;
        if (['thrust', 'lunge', 'punch', 'punch2', 'upper', 'sweep'].includes(m0)) { await this._strikeMotion(A, D, m0, [A, ...partners]); }
        else { SFX('swish', { vol: 0.7 }); this.addFx({ kind: 'slash', dur: 260, x: D.x - dirD * 30, y: D.y - 70, dir: dirD, heavy, color: c.outcome === 'dodged' ? 'rgba(255,255,255,0.5)' : '#fff3d6' }); }
      }

      await this._impact(c, A, D, magic, dirD, [A, ...partners], fired);

      this._applySnapshot(c.after, false);
      if (c.applied) {
        const st = G.STATUS[c.applied];
        this.float(D.x, D.y - 150, st.name.toUpperCase(), st.color, 20, 1300);
        this.sparks(D.x, D.y - 70, st.color, 10, 0.2, -0.0003);
      }
      if (!['blocked', 'hit', 'dodgeFail', 'parryFail', 'guardBroken'].includes(c.outcome) && !A.dead && A.state !== 'HIT_LIGHT' && A.state !== 'HIT_HEAVY') this.followThrough(A);
      this.caption = null;
    }

    async _react(c, D, A, delay) {
      await this.wait(delay);
      const away = D.x >= A.x ? 1 : -1;
      switch (c.reaction) {
        case 'block': this.setState(D, 'BLOCKING'); this.tween(D, { guard: 1, lean: -0.08, crouch: 0.06 }, 110); break;
        case 'dodge': {
          this.setState(D, 'DODGING');
          // esquiva para trás e para o lado (muda de profundidade)
          const side = D.y > (ARENA.minY + ARENA.maxY) / 2 ? -1 : 1;
          if (c.outcome === 'dodged') {
            D.dashing = true;
            this.moveTo(D, D.x + away * 80, D.y + side * 42, 200, 'out').then(() => { D.dashing = false; });
            this.tween(D, { hop: 30, lean: -0.35 }, 110, 'out').then(() => this.tween(D, { hop: 0, lean: 0 }, 160, 'in'));
          } else this.tween(D, { x: clamp(D.x + away * 18, ARENA.minX, ARENA.maxX), hop: 10, lean: -0.2 }, 150, 'out').then(() => this.tween(D, { hop: 0 }, 100));
          break;
        }
        case 'parry': this.setState(D, 'PARRYING'); this.tween(D, { arm: -1.1, lean: 0.05 }, 90); break;
      }
    }

    async _impact(c, A, D, magic, dir, attackers = [A], fired = true) {
      const hx = D.x - dir * 18, hy = D.y - 72;
      const dmgColor = D.side === 'ally' ? '#ff6a5a' : '#ffe08a';
      const showDamage = (v, n, big) => this.float(v.x + (Math.random() * 20 - 10), v.y - 130, String(n), dmgColor, big ? 46 : 32, big ? 1500 : 1100);

      switch (c.outcome) {
        case 'dodged':
          SFX('dodge');
          this.statusIcon(D, 'dodge', '#cfe9ff');
          this.sparks(D.x, D.y - 40, 'rgba(220,230,255,0.6)', 8, 0.25, 0);
          await this.wait(220);
          return;
        case 'parried': {
          // aparo: personagens ficam próximos no choque
          this.tween(D, { arm: 1.1 }, 60, 'in');
          SFX('parry');
          this.hitStop(120);
          this.addFx({ kind: 'star', dur: 420, x: hx, y: hy, color: '#fff2a8' });
          this.sparks(hx, hy, '#ffe28a', 26, 0.7);
          this.hurtShake(6);
          this.statusIcon(D, 'parry', '#ffe28a');
          this.slowMo(0.4, 450);
          this.focusOn([A, D], 0.18);
          this.setState(A, 'STAGGERING');
          this.tween(A, { x: clamp(A.x - dir * 40, ARENA.minX, ARENA.maxX), lean: -0.4, arm: -0.4 }, 200, 'out');
          await this.wait(300);
          D.dashing = true;
          this.setState(D, 'ATTACKING');
          await this.moveTo(D, D.x - dir * 40, D.y, 110, 'in');
          await this.tween(D, { arm: -1.4, lean: 0.2 }, 60, 'in');
          D.dashing = false;
          this.tween(D, { arm: 1.2 }, 80, 'in');
          await this.wait(60);
          this.addFx({ kind: 'slash', dur: 240, x: A.x + dir * 10, y: A.y - 70, dir: -dir, heavy: false, color: '#fff3d6' });
          SFX('slash');
          A.flash = 1;
          this.sparks(A.x, A.y - 70, '#ff8a6a', 14, 0.5);
          const cd = c.counter;
          this.float(A.x, A.y - 130, String(cd.damage), A.side === 'ally' ? '#ff6a5a' : '#ffe08a', cd.killed ? 46 : 32);
          A.hp = cd.hpAfter;
          this.react(A, 'medium', -dir, cd.killed);
          this.followThrough(D);
          if (cd.killed) await this._decisive(A, true);
          else this.hurtShake(5);
          await this.wait(cd.killed ? 380 : 220);
          return;
        }
        case 'blocked': {
          this.addFx({ kind: 'ring', dur: 260, x: hx + D.face * 12, y: hy, color: '#cfe3ff', r: 36 });
          this.statusIcon(D, 'block', '#9fd0ff');
          await this._sequence(attackers, D, c.skill, c, c.impact || 'light', { firstDone: fired, prepped: true, blocked: true });
          if (c.killed) await this._decisive(D, true);
          await this.wait(180);
          return;
        }
        default: { // hit, dodgeFail, parryFail, guardBroken — todos os golpes da sequência acertam
          if (c.outcome === 'parryFail') this.statusIcon(D, 'fail', '#ff8a6a');
          else if (c.outcome === 'dodgeFail') this.statusIcon(D, 'fail', '#ff8a6a');
          if (magic) this.addFx({ kind: 'ring', dur: 360, x: hx, y: hy, color: A.side === 'ally' ? '#8fd3ff' : '#c86bff', r: 50 });
          const lv = await this._sequence(attackers, D, c.skill, c, c.impact || 'light', { firstDone: fired, prepped: true });
          if (c.killed || lv === 'extreme') await this._decisive(D, c.killed);
          await this.wait(lv === 'light' ? 180 : 280);
        }
      }
    }

    // Momento decisivo: aproximação extra + câmera lenta curta
    async _decisive(D, killed) {
      this.hitStop(130);
      this.slowMo(0.32, killed ? 750 : 550);
      this.hurtShake(killed ? 12 : 8);
      if (killed) this.screenFlash = 0.3;
      this.focusOn([D], 0.2);
      this.addFx({ kind: 'ring', dur: 600, x: D.x, y: D.y - 70, color: '#ffffff', r: 110 });
      this.statusIcon(D, killed ? 'skull' : 'down', killed ? '#ff6a5a' : '#ffb36a', 1300);
      await this.wait(220);
    }

    // ============================================================ DESENHO
    // Arena de pedra em ruínas, em 4 camadas maiores que a área de combate.
    _buildBackground() {
      const BW = W + BG_M.x * 2, BH = H + BG_M.y * 2, X = BG_M.x, Y = BG_M.y;
      const mk = () => { const c = document.createElement('canvas'); c.width = BW; c.height = BH; return [c, c.getContext('2d')]; };
      const rnd = G.makeRng(7);
      // céu
      const [sky, g0] = mk();
      const sg = g0.createLinearGradient(0, 0, 0, Y + GROUND);
      sg.addColorStop(0, '#07060f'); sg.addColorStop(0.45, '#1c1228'); sg.addColorStop(0.8, '#3a2234'); sg.addColorStop(1, '#4e2c36');
      g0.fillStyle = sg; g0.fillRect(0, 0, BW, BH);
      for (let i = 0; i < 160; i++) { g0.fillStyle = `rgba(255,240,230,${0.15 + rnd() * 0.5})`; g0.fillRect(rnd() * BW, rnd() * (Y + 300), 1.5, 1.5); }
      const mx = X + 930, my = Y + 150;
      const moon = g0.createRadialGradient(mx, my, 10, mx, my, 200);
      moon.addColorStop(0, 'rgba(255,230,210,0.9)'); moon.addColorStop(0.22, 'rgba(255,200,180,0.3)'); moon.addColorStop(1, 'rgba(255,200,180,0)');
      g0.fillStyle = moon; g0.fillRect(mx - 220, my - 220, 440, 440);
      g0.fillStyle = '#f3dccb'; g0.beginPath(); g0.arc(mx, my, 44, 0, 7); g0.fill();
      g0.fillStyle = 'rgba(70,50,80,0.35)';
      for (let i = 0; i < 7; i++) { g0.beginPath(); g0.ellipse(rnd() * BW, Y + 60 + rnd() * 200, 160 + rnd() * 200, 18 + rnd() * 14, 0, 0, 7); g0.fill(); }
      // montanhas e ruínas distantes
      const [far, g1] = mk();
      g1.fillStyle = '#20162a';
      g1.beginPath(); g1.moveTo(0, Y + GROUND);
      for (let x = 0; x <= BW; x += 60) g1.lineTo(x, Y + GROUND - 150 - Math.sin(x * 0.004) * 70 - rnd() * 50);
      g1.lineTo(BW, BH); g1.lineTo(0, BH); g1.fill();
      g1.fillStyle = '#1a1222';
      for (let i = 0; i < 26; i++) {
        const x = i * 90 - 20 + rnd() * 40, h = 90 + rnd() * 170, w = 26 + rnd() * 30;
        g1.fillRect(x, Y + GROUND - 60 - h, w, h + 60);
        if (rnd() < 0.5) { g1.beginPath(); g1.moveTo(x - 6, Y + GROUND - 60 - h); g1.lineTo(x + w / 2, Y + GROUND - 100 - h); g1.lineTo(x + w + 6, Y + GROUND - 60 - h); g1.fill(); }
        if (rnd() < 0.35) { g1.fillStyle = 'rgba(255,170,90,0.3)'; g1.fillRect(x + w / 2 - 3, Y + GROUND - 40 - h * 0.6, 6, 10); g1.fillStyle = '#1a1222'; }
      }
      // plano intermediário: colunas e muros quebrados (fora da área central)
      const [mid, g2] = mk();
      const column = (x, h, broken) => {
        g2.fillStyle = '#251a2c'; g2.fillRect(x, Y + GROUND - 40 - h, 46, h);
        g2.fillStyle = '#2f2236'; g2.fillRect(x + 6, Y + GROUND - 40 - h, 8, h);
        g2.fillStyle = '#1b1320'; g2.fillRect(x - 8, Y + GROUND - 52, 62, 14); g2.fillRect(x - 6, Y + GROUND - 40 - h - 10, 58, 12);
        if (broken) { g2.fillStyle = '#251a2c'; g2.beginPath(); g2.moveTo(x, Y + GROUND - 40 - h); g2.lineTo(x + 20, Y + GROUND - 70 - h); g2.lineTo(x + 46, Y + GROUND - 48 - h); g2.fill(); }
      };
      [[X - 420, 300, 0], [X - 250, 220, 1], [X + 30, 260, 1], [X + 1190, 280, 0], [X + 1380, 200, 1], [X + 1560, 320, 0]].forEach(c => column(...c));
      g2.fillStyle = '#21172a';
      [[X - 160, 120], [X + 1290, 90]].forEach(([x, h]) => { g2.beginPath(); g2.moveTo(x, Y + GROUND - 40); g2.lineTo(x, Y + GROUND - 40 - h); g2.lineTo(x + 40, Y + GROUND - 40 - h + 20); g2.lineTo(x + 80, Y + GROUND - 40 - h - 10); g2.lineTo(x + 130, Y + GROUND - 40 - h + 30); g2.lineTo(x + 140, Y + GROUND - 40); g2.fill(); });
      // braseiros (luz quente discreta)
      [[X + 60, 0], [X + 1180, 0]].forEach(([x]) => {
        const gl = g2.createRadialGradient(x, Y + GROUND - 120, 2, x, Y + GROUND - 120, 90);
        gl.addColorStop(0, 'rgba(255,160,80,0.35)'); gl.addColorStop(1, 'rgba(255,160,80,0)');
        g2.fillStyle = gl; g2.fillRect(x - 90, Y + GROUND - 210, 180, 180);
        g2.fillStyle = '#ffb05a'; g2.beginPath(); g2.ellipse(x, Y + GROUND - 118, 6, 10, 0, 0, 7); g2.fill();
        g2.fillStyle = '#1b1320'; g2.fillRect(x - 10, Y + GROUND - 108, 20, 68);
      });
      // chão da arena (primeiro plano): pedra com rachaduras e pedrinhas
      const [floor, g3] = mk();
      const fg = g3.createLinearGradient(0, Y + GROUND - 40, 0, BH);
      fg.addColorStop(0, '#2e2230'); fg.addColorStop(0.5, '#1d1520'); fg.addColorStop(1, '#0f0b12');
      g3.fillStyle = fg; g3.fillRect(0, Y + GROUND - 40, BW, BH);
      g3.strokeStyle = 'rgba(255,255,255,0.045)'; g3.lineWidth = 2;
      for (let i = 0; i < 12; i++) { const y = Y + GROUND - 20 + i * i * 2.6; g3.beginPath(); g3.moveTo(0, y); g3.lineTo(BW, y); g3.stroke(); }
      for (let i = -24; i < 40; i++) { g3.beginPath(); g3.moveTo(X + W / 2 + i * 40, Y + GROUND - 40); g3.lineTo(X + W / 2 + i * 120, BH); g3.stroke(); }
      g3.strokeStyle = 'rgba(0,0,0,0.35)'; g3.lineWidth = 1.5;
      for (let i = 0; i < 40; i++) { let x = rnd() * BW, y = Y + GROUND - 20 + rnd() * 220; g3.beginPath(); g3.moveTo(x, y); for (let k = 0; k < 4; k++) { x += 8 + rnd() * 16; y += (rnd() - 0.5) * 10; g3.lineTo(x, y); } g3.stroke(); }
      for (let i = 0; i < 70; i++) { g3.fillStyle = `rgba(${90 + rnd() * 40},${70 + rnd() * 30},${90 + rnd() * 30},0.5)`; g3.beginPath(); g3.ellipse(rnd() * BW, Y + GROUND - 10 + rnd() * 240, 2 + rnd() * 5, 1.5 + rnd() * 2.5, 0, 0, 7); g3.fill(); }
      return { sky, far, mid, floor };
    }

    _draw() {
      const ctx = this.ctx;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.fillStyle = '#1a1220'; ctx.fillRect(0, 0, this.canvas.width, this.canvas.height); // mesmo tom do cenário
      const s = this.scale * this.dpr;
      ctx.setTransform(s, 0, 0, s, this.offX * this.dpr, this.offY * this.dpr);
      // mundo
      ctx.save();
      const sh = this.shake;
      const sd = this.shakeDir || 0, jx = (Math.random() - 0.5) * sh * (sd ? 0.5 : 1) + sd * sh * 0.5 * Math.sin(this.time * 0.09);
      ctx.translate(W / 2 + jx, this.viewCY + (Math.random() - 0.5) * sh * 0.6);
      ctx.scale(this.cam.z, this.cam.z);
      ctx.translate(-this.cam.x, -this.cam.y);
      // parallax discreto: céu/ruínas distantes andam menos que o chão
      const ox = this.cam.x - W / 2, oy = this.cam.y - H / 2;
      ctx.drawImage(this.bg.sky, -BG_M.x + ox * 0.85, -BG_M.y + oy * 0.85);
      ctx.drawImage(this.bg.far, -BG_M.x + ox * 0.45, -BG_M.y + oy * 0.3);
      ctx.drawImage(this.bg.mid, -BG_M.x + ox * 0.15, -BG_M.y);
      ctx.drawImage(this.bg.floor, -BG_M.x, -BG_M.y);
      for (const f of this.fog) {
        const gr = ctx.createRadialGradient(f.x, f.y, 0, f.x, f.y, f.r);
        gr.addColorStop(0, 'rgba(140,110,160,0.08)'); gr.addColorStop(1, 'rgba(140,110,160,0)');
        ctx.fillStyle = gr; ctx.fillRect(f.x - f.r, f.y - f.r, f.r * 2, f.r * 2);
      }
      if (!this.vis) { ctx.restore(); return; }
      this._drawMarkers(ctx);
      if (this.ui) this.ui.drawUnder(ctx);
      const list = Object.values(this.vis).sort((a, b) => (a.dead - b.dead) || (a.y - b.y));
      for (const v of list) this._drawUnit(ctx, v);
      this._drawFx(ctx);
      for (const v of list) this._drawHud(ctx, v);
      if (this.ui) this.ui.drawOver(ctx);
      this._drawNums(ctx);
      for (const pl of this.plates) this._drawClashHud(ctx, pl);
      for (const p of this.particles) {
        ctx.globalAlpha = clamp(p.life / 300, 0, 1);
        ctx.fillStyle = p.color; ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, 7); ctx.fill();
      }
      ctx.globalAlpha = 1;
      for (const t of this.texts) {
        const a = clamp(t.life / (t.max * 0.4), 0, 1), pop = 1 + Math.max(0, (t.max - t.life) < 120 ? (1 - (t.max - t.life) / 120) * 0.5 : 0);
        ctx.globalAlpha = a;
        ctx.font = `900 ${t.size * pop}px "Trebuchet MS", sans-serif`;
        ctx.textAlign = 'center'; ctx.lineWidth = 5; ctx.strokeStyle = 'rgba(10,5,15,0.9)';
        ctx.strokeText(t.text, t.x, t.y); ctx.fillStyle = t.color; ctx.fillText(t.text, t.x, t.y);
      }
      ctx.globalAlpha = 1;
      ctx.restore();

      // tela (vinheta, faixas cinematográficas, banner, legenda)
      const focusing = !!this.spot;
      const vg = ctx.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 0.95);
      vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, `rgba(0,0,0,${focusing ? 0.7 : 0.5})`);
      ctx.fillStyle = vg; ctx.fillRect(0, 0, W, H);
      if (this.screenFlash > 0) { ctx.fillStyle = `rgba(255,245,235,${this.screenFlash})`; ctx.fillRect(0, 0, W, H); }
      if (this.caption) {
        ctx.font = '600 20px "Trebuchet MS", sans-serif'; ctx.textAlign = 'center';
        const w = ctx.measureText(this.caption).width + 40;
        ctx.fillStyle = 'rgba(10,6,14,0.75)'; ctx.fillRect(W / 2 - w / 2, 58, w, 34);
        ctx.fillStyle = '#efe3d0'; ctx.fillText(this.caption, W / 2, 82);
      }
      if (this.banner) this._drawBanner(ctx, this.banner);
    }

    _drawBanner(ctx, b) {
      const p = b.t / b.dur;
      const inP = clamp(p / 0.15, 0, 1), outP = clamp((p - 0.8) / 0.2, 0, 1);
      const x = W / 2 + (1 - ease.out(inP)) * -300 + ease.in(outP) * 300;
      ctx.globalAlpha = 1 - outP;
      ctx.save(); ctx.translate(x, 210); ctx.transform(1, 0, -0.25, 1, 0, 0);
      ctx.fillStyle = 'rgba(8,4,10,0.85)'; ctx.fillRect(-260, -42, 520, 72);
      ctx.fillStyle = b.color; ctx.fillRect(-260, -42, 8, 72); ctx.fillRect(252, -42, 8, 72);
      ctx.restore();
      ctx.font = '900 46px "Trebuchet MS", sans-serif'; ctx.textAlign = 'center';
      ctx.fillStyle = b.color; ctx.fillText(b.text, x, 210 + 8);
      if (b.sub) { ctx.font = '600 16px "Trebuchet MS", sans-serif'; ctx.fillStyle = '#e8dccb'; ctx.fillText(b.sub, x, 210 + 26); }
      ctx.globalAlpha = 1;
    }

    _drawMarkers(ctx) {
      // anéis no chão: vermelho = alvo de inimigo, dourado = selecionável
      for (const id in this.vis) {
        const v = this.vis[id];
        if (v.dead) continue;
        const targeted = this.threatened && this.threatened.has(id);
        const hl = this.highlight && this.highlight.has(id);
        if (!targeted && !hl) continue;
        const pulse = 0.6 + Math.sin(this.time * 0.008) * 0.25;
        ctx.save(); ctx.translate(v.x, v.y + 4); ctx.scale(1, 0.32);
        ctx.lineWidth = 6;
        ctx.strokeStyle = hl ? `rgba(255,226,140,${pulse})` : `rgba(255,70,70,${pulse})`;
        ctx.beginPath(); ctx.arc(0, 0, 58, 0, 7); ctx.stroke();
        ctx.restore();
      }
    }

    _drawNums(ctx) {
      for (const n of this.nums) {
        if (n.a <= 0.01) continue;
        ctx.save(); ctx.globalAlpha = n.a; ctx.translate(n.x, n.y + n.dy); ctx.scale(n.s, n.s);
        ctx.font = '900 30px "Trebuchet MS", sans-serif'; ctx.textAlign = 'center';
        ctx.lineWidth = 6; ctx.strokeStyle = 'rgba(10,5,15,0.95)'; ctx.strokeText(n.text, 0, 0);
        ctx.fillStyle = n.color; ctx.fillText(n.text, 0, 0);
        ctx.restore();
      }
    }

    _drawHud(ctx, v) {
      if (v.dead && v.alpha < 0.5) return;
      const dim = this.spot && !this.spot.has(v.id);
      if (dim && !this.showLabels) return; // menos ruído durante as animações
      const x = v.x, y = v.y - 150 - v.hop + (Math.abs(v.tilt) > 1 ? 95 : Math.abs(v.tilt) * 40 + v.crouch * 60);
      const w = 74, ratio = clamp(v.dispHp / v.maxHp, 0, 1), real = clamp(v.hp / v.maxHp, 0, 1);
      ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(x - w / 2 - 2, y - 2, w + 4, 11);
      ctx.fillStyle = '#ffe9b0'; ctx.fillRect(x - w / 2, y, w * ratio, 7);
      ctx.fillStyle = v.side === 'ally' ? '#5fd08a' : '#d8484a'; // cor = equipe (nunca muda com a Vida)
      ctx.fillRect(x - w / 2, y, w * Math.min(ratio, real), 7);
      // elemento: gema colorida à esquerda das barras (sempre visível)
      const el = G.ELEMENTS && G.UNITS[v.id] && G.ELEMENTS[G.UNITS[v.id].element];
      if (el) { ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.beginPath(); ctx.arc(x - w / 2 - 9, y + 5, 7, 0, 7); ctx.fill(); ctx.fillStyle = el.color; ctx.beginPath(); ctx.arc(x - w / 2 - 9, y + 5, 4.6, 0, 7); ctx.fill(); }
      if (this.showLabels) {
        ctx.font = '700 13px "Trebuchet MS", sans-serif'; ctx.textAlign = 'center';
        // aliados em tom claro/azulado, inimigos em tom avermelhado: separação imediata
        ctx.fillStyle = v.side === 'ally' ? '#dfeaf5' : '#f5c9bd';
        ctx.fillText(`${v.name}  ${Math.max(0, Math.round(v.hp))}`, x, y - 6);
      }
      // Postura: barra secundária âmbar, mais fina, logo abaixo da Vida
      const pr = clamp(v.dispPost / v.postMax, 0, 1), preal = clamp(v.post / v.postMax, 0, 1), py = y + 9;
      ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(x - w / 2 - 2, py - 1, w + 4, 6);
      ctx.fillStyle = 'rgba(255,240,200,0.55)'; ctx.fillRect(x - w / 2, py, w * pr, 4);
      const pulse = preal < 0.25 && !v.broken ? 0.6 + 0.4 * Math.sin(this.time * 0.012) : 1;
      ctx.fillStyle = v.broken ? '#8a5a3a' : `rgba(217,184,92,${pulse})`;
      ctx.fillRect(x - w / 2, py, w * Math.min(pr, preal), 4);
      if (v.postFlash > 0.02) { ctx.fillStyle = `rgba(255,240,180,${v.postFlash})`; ctx.fillRect(x - w / 2 - 2, py - 2, w + 4, 8); } // desgaste grande: a barra pisca
      if (v.broken) {
        // barra rompida + ícone de Quebra
        ctx.strokeStyle = '#ffd36a'; ctx.lineWidth = 1.5; ctx.beginPath();
        ctx.moveTo(x - 6, py - 3); ctx.lineTo(x - 1, py + 3); ctx.lineTo(x + 3, py - 2); ctx.lineTo(x + 8, py + 5); ctx.stroke();
        ctx.font = '900 10px "Trebuchet MS", sans-serif'; ctx.textAlign = 'left'; ctx.fillStyle = '#ffd36a';
        ctx.fillText('QUEBRA', x + w / 2 + 5, py + 5);
      } else if (v.stable) {
        ctx.fillStyle = '#9fe0c8'; ctx.beginPath(); ctx.moveTo(x + w / 2 + 6, py - 3); ctx.lineTo(x + w / 2 + 11, py + 2); ctx.lineTo(x + w / 2 + 6, py + 7); ctx.lineTo(x + w / 2 + 1, py + 2); ctx.fill();
      }
      // indicador discreto: o golpe escolhido pode quebrar a Postura deste alvo (se vencer o Clash)
      if (this.breakHint && this.breakHint.has(v.id)) {
        ctx.globalAlpha = 0.6 + 0.4 * Math.sin(this.time * 0.01);
        ctx.font = '800 10px "Trebuchet MS", sans-serif'; ctx.textAlign = 'right'; ctx.fillStyle = '#ffd36a';
        ctx.fillText('⚡ QUEBRA?', x - w / 2 - 4, py + 5); ctx.globalAlpha = 1;
      }
      ctx.textAlign = 'center';
      let i = 0;
      for (const k in v.statuses) {
        const st = G.STATUS[k]; if (!st) continue;
        const sx = x - w / 2 + 8 + i * 20, sy = y + 24;
        ctx.fillStyle = st.color; ctx.beginPath(); ctx.arc(sx, sy, 8, 0, 7); ctx.fill();
        ctx.fillStyle = '#140c14'; ctx.font = '900 11px sans-serif'; ctx.fillText(st.icon, sx, sy + 4);
        i++;
      }
    }

    _statusGlyph(ctx, ic, c) {
      ctx.strokeStyle = c; ctx.fillStyle = c; ctx.lineWidth = 2; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      const shield = () => { ctx.beginPath(); ctx.moveTo(0, -7); ctx.lineTo(6, -5); ctx.lineTo(5, 2); ctx.lineTo(0, 7); ctx.lineTo(-5, 2); ctx.lineTo(-6, -5); ctx.closePath(); };
      ctx.beginPath();
      switch (ic) {
        case 'block': case 'protect': shield(); ctx.stroke(); if (ic === 'protect') { ctx.beginPath(); ctx.moveTo(0, -3); ctx.lineTo(0, 3); ctx.moveTo(-3, 0); ctx.lineTo(3, 0); ctx.stroke(); } break;
        case 'break': shield(); ctx.stroke(); ctx.beginPath(); ctx.moveTo(-1, -8); ctx.lineTo(2, -2); ctx.lineTo(-2, 1); ctx.lineTo(1, 8); ctx.strokeStyle = '#fff'; ctx.stroke(); break;
        case 'dodge': for (const y of [-4, 0, 4]) { ctx.moveTo(-7 + Math.abs(y), y); ctx.lineTo(5, y); } ctx.stroke(); ctx.beginPath(); ctx.moveTo(3, -3); ctx.lineTo(7, 0); ctx.lineTo(3, 3); ctx.stroke(); break;
        case 'parry': ctx.moveTo(-6, -6); ctx.lineTo(6, 6); ctx.moveTo(6, -6); ctx.lineTo(-6, 6); ctx.stroke(); ctx.beginPath(); ctx.arc(0, 0, 2.2, 0, 7); ctx.fillStyle = '#fff'; ctx.fill(); break;
        case 'fail': case 'lost': ctx.moveTo(-5, -5); ctx.lineTo(5, 5); ctx.moveTo(5, -5); ctx.lineTo(-5, 5); ctx.stroke(); break;
        case 'restore': case 'stable': ctx.arc(0, 0, 5.5, -2.4, 2.2); ctx.stroke(); ctx.beginPath(); ctx.moveTo(4, -6); ctx.lineTo(4.5, -1.5); ctx.lineTo(0, -2.5); ctx.stroke(); break;
        case 'down': ctx.moveTo(0, -7); ctx.lineTo(0, 5); ctx.moveTo(-5, 0); ctx.lineTo(0, 6); ctx.lineTo(5, 0); ctx.stroke(); break;
        case 'skull': ctx.arc(0, -1.5, 6, 0, 7); ctx.fill(); ctx.fillRect(-3.5, 3, 7, 4); ctx.fillStyle = '#0a0610'; ctx.beginPath(); ctx.arc(-2.3, -1.5, 1.7, 0, 7); ctx.arc(2.3, -1.5, 1.7, 0, 7); ctx.fill(); break;
        default: ctx.arc(0, 0, 4, 0, 7); ctx.fill();
      }
    }
    _drawFx(ctx) {
      for (const f of this.fx) {
        const p = f.t / f.dur;
        ctx.save();
        if (f.kind === 'slash') {
          ctx.translate(f.x, f.y); ctx.scale(f.dir, f.flip ? -1 : 1); ctx.rotate(f.rot || 0);
          ctx.globalAlpha = 1 - p;
          ctx.strokeStyle = f.color; ctx.lineWidth = (f.heavy ? 16 : 9) * (1 - p * 0.6); ctx.lineCap = 'round';
          const r = f.r || (f.heavy ? 85 : 65), a0 = -1.9, a1 = -1.9 + 2.6 * Math.min(1, p * 2.5);
          // rastro da lâmina: faixa mais larga e translúcida atrás do arco
          ctx.save(); ctx.globalAlpha *= 0.35; ctx.lineWidth = (f.heavy ? 30 : 18) * (1 - p); ctx.strokeStyle = f.color;
          ctx.beginPath(); ctx.arc(-20, 0, r - 6, Math.max(a0, a1 - 1.2), a1); ctx.stroke(); ctx.restore();
          ctx.beginPath(); ctx.arc(-20, 0, r, a0, a1); ctx.stroke();
          ctx.lineWidth = 2; ctx.strokeStyle = '#fff'; ctx.beginPath(); ctx.arc(-20, 0, r + 6, a0 + 0.2, a1); ctx.stroke();
        } else if (f.kind === 'thrust') {
          // estocada: rastro linear com brilho concentrado na ponta
          const e = ease.out(Math.min(1, p * 2.2));
          const xe = lerp(f.x0, f.x1, e), ye = lerp(f.y0, f.y1, e);
          ctx.globalAlpha = 1 - p; ctx.lineCap = 'round';
          ctx.strokeStyle = f.color; ctx.lineWidth = f.w * (1 - p * 0.7);
          ctx.beginPath(); ctx.moveTo(lerp(f.x0, xe, 0.4), lerp(f.y0, ye, 0.4)); ctx.lineTo(xe, ye); ctx.stroke();
          ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(xe, ye, f.w * 0.9 * (1 - p), 0, 7); ctx.fill();
        } else if (f.kind === 'punch') {
          ctx.translate(f.x, f.y); ctx.scale(f.dir, 1);
          ctx.globalAlpha = 1 - p; ctx.strokeStyle = f.color; ctx.lineWidth = 4 * (1 - p); ctx.lineCap = 'round';
          for (let i = -1; i <= 1; i++) { ctx.beginPath(); ctx.moveTo(-34 + p * 10, i * 9); ctx.lineTo(-12 + p * 10, i * 7); ctx.stroke(); }
          ctx.beginPath(); ctx.arc(0, 0, 10 + p * 22, 0, 7); ctx.stroke();
        } else if (f.kind === 'arrow') {
          const e = ease.in(p);
          const x = lerp(f.x0, f.x1, e), y = lerp(f.y0, f.y1, e) - Math.sin(p * Math.PI) * (f.arc || 0);
          const ang = Math.atan2(f.y1 - f.y0, f.x1 - f.x0);
          ctx.globalAlpha = 0.5; ctx.strokeStyle = 'rgba(255,240,210,0.6)'; ctx.lineWidth = f.heavy ? 3 : 2;
          ctx.beginPath(); ctx.moveTo(lerp(f.x0, x, 0.55), lerp(f.y0, y, 0.55)); ctx.lineTo(x, y); ctx.stroke();   // rastro
          ctx.globalAlpha = 1; ctx.translate(x, y); ctx.rotate(ang);
          ctx.strokeStyle = '#d9c39a'; ctx.lineWidth = f.heavy ? 3.5 : 2.5; ctx.beginPath(); ctx.moveTo(-30, 0); ctx.lineTo(6, 0); ctx.stroke();
          ctx.fillStyle = f.heavy ? '#ffe9b0' : '#e8eef5'; ctx.beginPath(); ctx.moveTo(14, 0); ctx.lineTo(4, -4); ctx.lineTo(4, 4); ctx.fill();
          ctx.fillStyle = '#c84a4a'; ctx.beginPath(); ctx.moveTo(-30, 0); ctx.lineTo(-38, -5); ctx.lineTo(-24, 0); ctx.lineTo(-38, 5); ctx.fill();
          if (f.heavy) { ctx.shadowColor = '#ffe9b0'; ctx.shadowBlur = 14; ctx.fillRect(2, -1, 10, 2); }
        } else if (f.kind === 'burst') {
          // clarão direcional: raios alongados na direção do golpe + núcleo branco curto
          const e = 1 - p, L = 60 * f.size;
          ctx.translate(f.x, f.y); ctx.rotate(f.ang);
          ctx.globalCompositeOperation = 'lighter';
          for (let i = 0; i < f.rays; i++) {
            const a = (i / f.rays) * Math.PI * 2, len = (i % 2 ? 0.45 : 1) * L * (0.6 + 0.6 * Math.abs(Math.cos(a))) * (0.6 + 0.4 * p);
            ctx.globalAlpha = e * 0.9; ctx.fillStyle = f.color;
            ctx.beginPath(); ctx.moveTo(Math.cos(a - 0.09) * 6, Math.sin(a - 0.09) * 6); ctx.lineTo(Math.cos(a) * len, Math.sin(a) * len); ctx.lineTo(Math.cos(a + 0.09) * 6, Math.sin(a + 0.09) * 6); ctx.fill();
          }
          ctx.globalAlpha = e; ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(0, 0, 10 * f.size * e + 3, 0, 7); ctx.fill();
        } else if (f.kind === 'deflect') {
          // projétil rebatido: segue para fora da linha de ataque, perdendo intensidade
          const dist = 140 * f.size * ease.out(p), x = f.x + Math.cos(f.ang) * dist, y = f.y + Math.sin(f.ang) * dist;
          ctx.globalAlpha = 1 - p; ctx.strokeStyle = f.color; ctx.lineWidth = 3 * (1 - p) + 1;
          ctx.beginPath(); ctx.moveTo(f.x + Math.cos(f.ang) * dist * 0.4, f.y + Math.sin(f.ang) * dist * 0.4); ctx.lineTo(x, y); ctx.stroke();
          ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(x, y, 6 * (1 - p) + 1, 0, 7); ctx.fill();
        } else if (f.kind === 'shock') {
          // onda de choque fina (pequena "distorção" no ponto de contato)
          ctx.globalAlpha = (1 - p) * 0.6; ctx.strokeStyle = f.color; ctx.lineWidth = 3 * (1 - p) + 0.5;
          ctx.beginPath(); ctx.ellipse(f.x, f.y, f.r * ease.out(p), f.r * 0.55 * ease.out(p), 0, 0, 7); ctx.stroke();
        } else if (f.kind === 'shatter') {
          // ruptura da guarda: estilhaços que se afastam do centro
          ctx.globalAlpha = 1 - p; ctx.strokeStyle = f.color; ctx.lineWidth = 3;
          for (let i = 0; i < 9; i++) {
            const a = i * 0.7 + 0.3, r0 = 14 + p * 70, r1 = r0 + 14 * (1 - p);
            ctx.beginPath(); ctx.moveTo(f.x + Math.cos(a) * r0, f.y + Math.sin(a) * r0); ctx.lineTo(f.x + Math.cos(a + 0.12) * r1, f.y + Math.sin(a + 0.12) * r1); ctx.stroke();
          }
          ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(f.x, f.y, 20 + p * 30, 0, 7); ctx.stroke();
        } else if (f.kind === 'flash') {
          ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = 0.55 * (1 - p);
          const gr = ctx.createRadialGradient(f.x, f.y, 0, f.x, f.y, f.r);
          gr.addColorStop(0, f.color); gr.addColorStop(1, 'rgba(0,0,0,0)');
          ctx.fillStyle = gr; ctx.fillRect(f.x - f.r, f.y - f.r, f.r * 2, f.r * 2);
        } else if (f.kind === 'sicon') {
          // ícone de estado: pequeno disco ao lado da barra de Vida, sobe e some rápido
          const v = f.ref, k = this.pxPerWorld || 1;
          ctx.translate(v.x + 70, v.y - 168 - (v.hop || 0) - p * 10); ctx.scale(1 / k, 1 / k);
          const pop = p < 0.15 ? 0.6 + p / 0.15 * 0.5 : p < 0.25 ? 1.1 - (p - 0.15) : 1;
          ctx.scale(pop, pop); ctx.globalAlpha = p > 0.7 ? (1 - p) / 0.3 : 1;
          ctx.fillStyle = 'rgba(10,6,14,0.85)'; ctx.strokeStyle = f.color; ctx.lineWidth = 2;
          ctx.beginPath(); ctx.arc(0, 0, 13, 0, 7); ctx.fill(); ctx.stroke();
          this._statusGlyph(ctx, f.icon, f.color);
        } else if (f.kind === 'ring') {
          ctx.globalAlpha = 1 - p; ctx.strokeStyle = f.color; ctx.lineWidth = 6 * (1 - p) + 1;
          ctx.beginPath(); ctx.ellipse(f.x, f.y, f.r * (0.3 + p), f.r * (0.3 + p) * 1.1, 0, 0, 7); ctx.stroke();
        } else if (f.kind === 'star') {
          ctx.translate(f.x, f.y); ctx.rotate(p * 0.6);
          ctx.globalAlpha = 1 - p; ctx.fillStyle = f.color;
          const r = 70 * ease.out(Math.min(1, p * 3));
          ctx.beginPath();
          for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4, rr = i % 2 ? r * 0.25 : r; ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr); }
          ctx.fill();
        } else if (f.kind === 'proj') {
          const e = ease.in(p);
          const x = lerp(f.x0, f.x1, e), y = lerp(f.y0, f.y1, e) - Math.sin(p * Math.PI) * (f.arc == null ? 30 : f.arc);
          for (let i = 6; i >= 0; i--) {
            const q = Math.max(0, e - i * 0.04);
            const tx = lerp(f.x0, f.x1, q), ty = lerp(f.y0, f.y1, q) - Math.sin(Math.max(0, p - i * 0.04) * Math.PI) * (f.arc == null ? 30 : f.arc);
            ctx.globalAlpha = 0.5 * (1 - i / 7); ctx.fillStyle = f.color;
            ctx.beginPath(); ctx.arc(tx, ty, 12 - i * 1.3, 0, 7); ctx.fill();
          }
          ctx.globalAlpha = 1; ctx.shadowColor = f.color; ctx.shadowBlur = 25;
          ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(x, y, 8, 0, 7); ctx.fill();
          if (Math.random() < 0.5) this.particles.push({ x, y, vx: (Math.random() - 0.5) * 0.1, vy: (Math.random() - 0.5) * 0.1, life: 250, color: f.color, r: 2.5 });
        }
        ctx.restore();
      }
    }

    // ------------------------------------------------------------ personagens
    _drawUnit(ctx, v) {
      const t = this.time;
      const dim = (this.spot && !this.spot.has(v.id)) || (this.dimIds && this.dimIds.has(v.id));
      // rastro do avanço
      if (v.trail.length > 1) {
        for (let i = 0; i < v.trail.length; i++) {
          const tr = v.trail[i]; ctx.globalAlpha = 0.12 * (i / v.trail.length);
          ctx.fillStyle = v.side === 'ally' ? '#9fd8ff' : '#ff8a8a';
          ctx.beginPath(); ctx.ellipse(tr.x, tr.y - 60, 26, 58, 0, 0, 7); ctx.fill();
        }
        ctx.globalAlpha = 1;
      }
      ctx.save();
      ctx.translate(v.x, v.y);
      // profundidade: mais abaixo na arena = levemente maior (e desenhado na frente)
      const ds = 0.93 + clamp((v.y - ARENA.minY) / (ARENA.maxY - ARENA.minY), 0, 1) * 0.12;
      ctx.scale(ds, ds);
      // sombra (encolhe quando o personagem sai do chão)
      ctx.fillStyle = 'rgba(0,0,0,0.45)';
      ctx.beginPath(); ctx.ellipse(0, 2, 44 - v.hop * 0.3, 10 - v.hop * 0.05, 0, 0, 7); ctx.fill();
      const down = v.dead || v.state === 'KNOCKDOWN';
      const idle = down ? 0 : Math.sin(t * 0.004 + v.phase);
      // animações secundárias contextuais
      let ctxLean = 0, ctxCrouch = 0;
      if (v.state === 'PREPARING') ctxLean = Math.sin(t * 0.0035 + v.phase) * 0.012;   // respiração tensa, lenta
      else if (v.state === 'STAGGERING' || v.state === 'GETTING_UP') ctxLean = Math.sin(t * 0.012) * 0.04;
      else if (v.state === 'IDLE' && v.threat) ctxCrouch = 0.04;                          // ameaçado: abaixa a guarda
      ctx.translate(0, -v.hop);
      ctx.scale(v.face, 1);
      const wv = down ? 0 : v.wound;
      const pqv = down || v.broken ? 0 : clamp((0.5 - v.post / v.postMax) / 0.5, 0, 1);
      const brokenWob = v.state === 'BROKEN' ? Math.sin(t * 0.007) * 0.04 : 0;
      ctx.rotate(v.lean * 0.6 + v.tilt + ctxLean + wv * 0.11 + (wv > 0.6 ? Math.sin(t * 0.0021 + v.phase) * 0.03 * wv : 0)
        - pqv * pqv * 0.05 * (0.5 + 0.5 * Math.sin(t * 0.0042 + v.phase)) + brokenWob); // postura baixa: recua o tronco (perde o equilíbrio)
      ctx.scale(1 + (v.crouch + ctxCrouch + wv * 0.05) * 0.5, 1 - v.crouch - ctxCrouch - wv * 0.05);
      const filters = [];
      if (v.flash > 0.05) filters.push(`brightness(${1 + v.flash * 1.1})`);
      if (dim) filters.push('brightness(0.45)');
      if (v.dead) filters.push('grayscale(0.9) brightness(0.6)');
      ctx.filter = filters.length ? filters.join(' ') : 'none';
      ctx.globalAlpha = v.alpha;
      const threatGuard = v.threat && v.state === 'IDLE' ? 0.45 : 0;
      // Postura comprometida (<50%) / crítica (<25%): guarda oscila, pequenos recuos de equilíbrio
      const pq = down || v.broken ? 0 : clamp((0.5 - v.post / v.postMax) / 0.5, 0, 1);
      const unsteady = pq * Math.sin(t * 0.0055 + v.phase * 2);
      // condição física: ferido (25–50%) e crítico (<25%) — curva, respira mais forte, arma pesa
      const w = down ? 0 : v.wound;
      const breath = Math.sin(t * (0.004 + w * 0.004) + v.phase);
      const pose = { idle: breath * (1 + w * 1.4), t, wound: w,
        arm: v.arm + (down ? 0 : breath * 0.05) + w * 0.3 + (v.ready ? Math.sin(t * 0.0035 + v.phase) * 0.04 : 0),
        guard: Math.max(v.guard, threatGuard) * (1 - w * 0.25) + unsteady * 0.18, cast: v.cast * (1 - w * 0.2) + (v.ready ? 0.12 * Math.sin(t * 0.004) : 0) };
      pose.arm += unsteady * 0.12;
      ART[v.art](ctx, pose);
      // apoio da mão no chão durante o desequilíbrio
      if (v.kneel > 0.4 && !v.dead) { ctx.fillStyle = '#d9c3a8'; ctx.beginPath(); ctx.arc(30, -6, 6, 0, 7); ctx.fill(); }
      ctx.restore();
      ctx.filter = 'none'; ctx.globalAlpha = 1;
      if (v.barrier > 0.05) {
        ctx.save(); ctx.globalAlpha = v.barrier * (0.35 + 0.15 * Math.sin(t * 0.02));
        ctx.strokeStyle = '#8fd3ff'; ctx.fillStyle = 'rgba(120,200,255,0.15)'; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.ellipse(v.x + v.face * 34, v.y - 70, 26, 78, 0, 0, 7); ctx.fill(); ctx.stroke();
        ctx.restore();
      }
    }
  }

  // ------------------------------------------------------------ ARTE
  // Todos desenhados virados para a direita, pés em (0,0).
  function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); ctx.fill(); }
  function poly(ctx, pts) { ctx.beginPath(); ctx.moveTo(pts[0], pts[1]); for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i], pts[i + 1]); ctx.closePath(); ctx.fill(); }

  const ART = {
    knight(ctx, p) {
      const b = p.idle * 1.5;
      // capa
      ctx.fillStyle = '#23457a';
      ctx.beginPath(); ctx.moveTo(-14, -92 + b); ctx.quadraticCurveTo(-46, -50, -40 + Math.sin(p.t * 0.003) * 4, -6);
      ctx.lineTo(-10, -10); ctx.closePath(); ctx.fill();
      // pernas
      ctx.fillStyle = '#3a4250'; rr(ctx, -20, -38, 15, 38, 4); rr(ctx, 4, -38, 15, 38, 4);
      ctx.fillStyle = '#5b6575'; rr(ctx, -22, -8, 19, 8, 3); rr(ctx, 2, -8, 19, 8, 3);
      // braço da espada (atrás)
      ctx.save(); ctx.translate(-6, -84 + b); ctx.rotate(-0.4 + p.arm);
      ctx.fillStyle = '#6e7a8c'; rr(ctx, -6, -4, 12, 30, 5);
      ctx.translate(0, 26); ctx.fillStyle = '#d8b45a'; rr(ctx, -12, -3, 24, 6, 2);
      ctx.fillStyle = '#dfe6ef'; poly(ctx, [-4, 0, 4, 0, 3, 64, 0, 74, -3, 64]);
      ctx.restore();
      // tronco
      ctx.fillStyle = '#8a96a8'; rr(ctx, -28, -96 + b, 56, 62, 14);
      ctx.fillStyle = '#a9b4c4'; rr(ctx, -22, -90 + b, 30, 22, 8);
      ctx.fillStyle = '#d8b45a'; ctx.fillRect(-28, -44 + b, 56, 6);
      // ombreiras
      ctx.fillStyle = '#9ba7b8'; ctx.beginPath(); ctx.ellipse(-20, -92 + b, 15, 11, 0, 0, 7); ctx.fill();
      ctx.beginPath(); ctx.ellipse(20, -92 + b, 15, 11, 0, 0, 7); ctx.fill();
      // elmo
      ctx.fillStyle = '#7f8b9c'; rr(ctx, -17, -128 + b, 36, 36, 11);
      ctx.fillStyle = '#1a1e26'; ctx.fillRect(-2, -114 + b, 20, 6);
      ctx.fillStyle = '#9fe3ff'; ctx.fillRect(4, -112 + b, 12, 2);
      ctx.fillStyle = '#b8322f'; ctx.beginPath(); ctx.moveTo(-4, -128 + b); ctx.quadraticCurveTo(-24, -150 + b, -30, -118 + b); ctx.quadraticCurveTo(-16, -132 + b, -4, -124 + b); ctx.fill();
      // escudo (frente)
      const gx = 24 + p.guard * 16, gy = -70 + b - p.guard * 8 + (p.wound || 0) * 22;
      ctx.save(); ctx.translate(gx, gy); ctx.rotate(-0.08 + p.guard * 0.12);
      ctx.fillStyle = '#2f5d9b'; ctx.beginPath(); ctx.moveTo(-20, -32); ctx.lineTo(20, -32); ctx.lineTo(20, 8); ctx.quadraticCurveTo(10, 30, 0, 38); ctx.quadraticCurveTo(-10, 30, -20, 8); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = '#d8b45a'; ctx.lineWidth = 4; ctx.stroke();
      ctx.fillStyle = '#d8b45a'; ctx.fillRect(-3, -24, 6, 52); ctx.fillRect(-14, -8, 28, 6);
      ctx.restore();
    },
    swordsman(ctx, p) {
      const b = p.idle * 2;
      // cachecol esvoaçante
      ctx.fillStyle = '#e0484a';
      const w = Math.sin(p.t * 0.006) * 6;
      ctx.beginPath(); ctx.moveTo(-4, -104 + b); ctx.quadraticCurveTo(-40, -110 + w, -62, -96 + w * 1.5); ctx.lineTo(-58, -88 + w); ctx.quadraticCurveTo(-36, -96, -4, -96 + b); ctx.fill();
      // pernas (postura aberta)
      ctx.fillStyle = '#1d2430';
      poly(ctx, [-6, -48, 4, -48, -14, 0, -26, 0]); poly(ctx, [0, -48, 10, -48, 26, 0, 14, 0]);
      // tronco
      ctx.fillStyle = '#2bb3a3'; poly(ctx, [-14, -100 + b, 14, -100 + b, 10, -46, -10, -46]);
      ctx.fillStyle = '#1b6f66'; ctx.fillRect(-11, -58, 22, 6);
      // cabeça
      ctx.fillStyle = '#e8c9a8'; ctx.beginPath(); ctx.arc(2, -114 + b, 12, 0, 7); ctx.fill();
      ctx.fillStyle = '#20182a'; ctx.beginPath(); ctx.arc(0, -118 + b, 12.5, Math.PI * 0.95, Math.PI * 2.1); ctx.fill();
      ctx.beginPath(); ctx.moveTo(-10, -120 + b); ctx.quadraticCurveTo(-30, -122 + b + w * 0.5, -34, -104 + b + w); ctx.lineTo(-8, -112 + b); ctx.fill();
      ctx.fillStyle = '#20182a'; ctx.fillRect(6, -116 + b, 5, 2);
      // braço + katana
      ctx.save(); ctx.translate(6, -92 + b); ctx.rotate(0.5 + p.arm);
      ctx.fillStyle = '#e8c9a8'; rr(ctx, -4, -3, 8, 26, 4);
      ctx.translate(0, 24); ctx.fillStyle = '#e0a63a'; ctx.fillRect(-7, -2, 14, 4);
      ctx.fillStyle = '#20182a'; ctx.fillRect(-2, -14, 4, 12);
      ctx.fillStyle = '#eef6ff'; poly(ctx, [-2, 2, 2, 2, 4, 70, 0, 86, -1.5, 70]);
      ctx.restore();
    },
    mage(ctx, p) {
      const b = p.idle * 2.5;
      // manto
      ctx.fillStyle = '#3c3f9e'; poly(ctx, [-12, -96 + b, 12, -96 + b, 30, 0, -30, 0]);
      ctx.fillStyle = '#2a2c6e'; poly(ctx, [-30, 0, 30, 0, 26, -10, -26, -10]);
      ctx.fillStyle = '#d8b45a'; ctx.fillRect(-14, -60 + b * 0.5, 28, 4);
      // rosto sombreado
      ctx.fillStyle = '#16142c'; ctx.beginPath(); ctx.arc(2, -104 + b, 13, 0, 7); ctx.fill();
      ctx.fillStyle = '#9fe3ff'; ctx.fillRect(4, -106 + b, 4, 3); ctx.fillRect(11, -106 + b, 3, 3);
      // barba
      ctx.fillStyle = '#c9c6d8'; poly(ctx, [-4, -98 + b, 14, -98 + b, 6, -78 + b]);
      // chapéu
      ctx.fillStyle = '#2a2c6e';
      ctx.beginPath(); ctx.ellipse(2, -114 + b, 26, 6, 0, 0, 7); ctx.fill();
      ctx.beginPath(); ctx.moveTo(-14, -114 + b); ctx.lineTo(16, -114 + b); ctx.quadraticCurveTo(6, -150 + b, -18 + Math.sin(p.t * 0.003) * 3, -166 + b); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#d8b45a'; ctx.fillRect(-12, -120 + b, 26, 4);
      // cajado
      ctx.save(); ctx.translate(20, -66 + b); ctx.rotate(p.arm * 0.35);
      ctx.fillStyle = '#e8c9a8'; ctx.beginPath(); ctx.arc(0, 0, 5, 0, 7); ctx.fill();
      ctx.strokeStyle = '#6b4a2e'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(0, 56); ctx.lineTo(4, -48); ctx.stroke();
      const r = 7 + p.cast * 6;
      ctx.shadowColor = '#7fd1ff'; ctx.shadowBlur = 10 + p.cast * 25;
      ctx.fillStyle = '#9fe0ff'; ctx.beginPath(); ctx.arc(4, -54, r, 0, 7); ctx.fill();
      ctx.restore();
    },
    brute(ctx, p) {
      const b = p.idle * 2;
      // pernas grossas
      ctx.fillStyle = '#3d3229'; rr(ctx, -30, -40, 24, 40, 8); rr(ctx, 6, -40, 24, 40, 8);
      // clava (atrás, segurada alto)
      ctx.save(); ctx.translate(-4, -96 + b); ctx.rotate(-0.6 + p.arm);
      ctx.fillStyle = '#7a6d5c'; rr(ctx, -9, -5, 18, 40, 8);
      ctx.translate(0, 34); ctx.fillStyle = '#5a3a24'; rr(ctx, -5, 0, 10, 26, 3);
      ctx.fillStyle = '#4a2f1d'; rr(ctx, -15, 22, 30, 66, 14);
      ctx.fillStyle = '#b7b1a3'; for (let i = 0; i < 4; i++) { poly(ctx, [15, 34 + i * 14, 26, 38 + i * 14, 15, 44 + i * 14]); poly(ctx, [-15, 34 + i * 14, -26, 38 + i * 14, -15, 44 + i * 14]); }
      ctx.restore();
      // corpo enorme
      ctx.fillStyle = '#7a6d5c'; ctx.beginPath(); ctx.ellipse(0, -72 + b, 46, 44, 0, 0, 7); ctx.fill();
      ctx.fillStyle = '#8a4b32'; ctx.beginPath(); ctx.ellipse(-6, -96 + b, 40, 20, -0.15, 0, 7); ctx.fill();
      ctx.fillStyle = '#5c3020'; ctx.fillRect(-40, -48 + b, 80, 10);
      // cabeça pequena com chifres
      ctx.fillStyle = '#6a5e4e'; ctx.beginPath(); ctx.arc(26, -110 + b, 15, 0, 7); ctx.fill();
      ctx.fillStyle = '#d9cfb8'; poly(ctx, [16, -120 + b, 8, -142 + b, 22, -124 + b]); poly(ctx, [32, -122 + b, 44, -140 + b, 38, -118 + b]);
      ctx.fillStyle = '#ff5a3a'; ctx.fillRect(30, -112 + b, 6, 3);
      // braço da frente
      ctx.fillStyle = '#6a5e4e'; ctx.beginPath(); ctx.ellipse(34, -66 + b, 12, 24, -0.3 + p.guard * 0.6, 0, 7); ctx.fill();
    },
    duelist(ctx, p) {
      const b = p.idle * 2;
      // capa
      ctx.fillStyle = '#5a1420';
      ctx.beginPath(); ctx.moveTo(-10, -100 + b); ctx.quadraticCurveTo(-40, -60, -34 + Math.sin(p.t * 0.005) * 5, -14); ctx.lineTo(-6, -40); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#1a1218';
      poly(ctx, [-6, -50, 4, -50, -10, 0, -22, 0]); poly(ctx, [0, -50, 10, -50, 24, 0, 12, 0]);
      ctx.fillStyle = '#9e2b3a'; poly(ctx, [-14, -102 + b, 14, -102 + b, 14, -44, -16, -44]);
      ctx.fillStyle = '#e0c060'; ctx.fillRect(-2, -100 + b, 3, 54);
      // máscara e chapéu de pluma
      ctx.fillStyle = '#efe7da'; ctx.beginPath(); ctx.arc(2, -116 + b, 12, 0, 7); ctx.fill();
      ctx.fillStyle = '#1a1218'; ctx.fillRect(4, -119 + b, 4, 3); ctx.fillRect(10, -119 + b, 3, 3);
      ctx.fillStyle = '#2a1520'; ctx.beginPath(); ctx.ellipse(0, -126 + b, 22, 6, -0.15, 0, 7); ctx.fill();
      rr(ctx, -10, -142 + b, 20, 16, 4);
      ctx.fillStyle = '#d8484a'; ctx.beginPath(); ctx.moveTo(-6, -138 + b); ctx.quadraticCurveTo(-30, -160 + b, -36, -130 + b); ctx.quadraticCurveTo(-20, -142 + b, -6, -132 + b); ctx.fill();
      // florete
      ctx.save(); ctx.translate(8, -92 + b); ctx.rotate(0.9 + p.arm);
      ctx.fillStyle = '#9e2b3a'; rr(ctx, -4, -3, 8, 26, 4);
      ctx.translate(0, 24); ctx.strokeStyle = '#e0c060'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(0, 0, 7, Math.PI, 0); ctx.stroke();
      ctx.fillStyle = '#e8eef5'; poly(ctx, [-1.5, 0, 1.5, 0, 0.6, 92, -0.6, 92]);
      ctx.restore();
    },
    conjurer(ctx, p) {
      const f = Math.sin(p.t * 0.003) * 5 - 12; // flutua
      // robe esfarrapado
      ctx.fillStyle = '#3a2547';
      ctx.beginPath(); ctx.moveTo(-12, -104 + f); ctx.lineTo(14, -104 + f); ctx.lineTo(30, -10 + f);
      for (let i = 0; i < 6; i++) ctx.lineTo(30 - i * 12 - 6, (i % 2 ? -4 : -18) + f + Math.sin(p.t * 0.006 + i) * 3);
      ctx.lineTo(-32, -10 + f); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#251733'; poly(ctx, [-12, -104 + f, 14, -104 + f, 4, -40 + f]);
      // capuz
      ctx.fillStyle = '#2c1b38'; ctx.beginPath(); ctx.moveTo(-18, -96 + f); ctx.quadraticCurveTo(-14, -140 + f, 10, -138 + f); ctx.quadraticCurveTo(24, -120 + f, 18, -96 + f); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#07040a'; ctx.beginPath(); ctx.ellipse(6, -112 + f, 9, 13, 0, 0, 7); ctx.fill();
      ctx.fillStyle = '#d68bff'; ctx.fillRect(4, -114 + f, 3, 3); ctx.fillRect(10, -114 + f, 3, 3);
      // mão com orbe
      ctx.save(); ctx.translate(18, -78 + f); ctx.rotate(p.arm * 0.3);
      ctx.fillStyle = '#4a3058'; rr(ctx, -4, -4, 26, 9, 4);
      const r = 8 + p.cast * 7;
      ctx.shadowColor = '#c86bff'; ctx.shadowBlur = 12 + p.cast * 28;
      ctx.fillStyle = '#d99bff'; ctx.beginPath(); ctx.arc(30, -6, r, 0, 7); ctx.fill();
      ctx.restore();
    },
  };

  Object.assign(ART, {
    // Lanceiro: elmo com crista, tabardo verde, lança longa projetada à FRENTE do corpo
    lancer(ctx, p) {
      const b = p.idle * 1.8;
      ctx.fillStyle = '#2a2f26'; poly(ctx, [-8, -50, 2, -50, -14, 0, -26, 0]); poly(ctx, [2, -50, 12, -50, 22, 0, 10, 0]);
      ctx.fillStyle = '#5c6b5a'; rr(ctx, -15, -100 + b, 30, 56, 8);
      ctx.fillStyle = '#3f6b4f'; poly(ctx, [-13, -96 + b, 13, -96 + b, 10, -40, -10, -40]);
      ctx.fillStyle = '#d8b45a'; ctx.fillRect(-2, -96 + b, 4, 56);
      ctx.fillStyle = '#8a96a8'; rr(ctx, -12, -128 + b, 26, 28, 9);
      ctx.fillStyle = '#1a1e26'; ctx.fillRect(2, -116 + b, 12, 4);
      ctx.fillStyle = '#3f6b4f'; ctx.beginPath(); ctx.moveTo(-6, -128 + b); ctx.quadraticCurveTo(-4, -146 + b, 10, -140 + b); ctx.lineTo(4, -126 + b); ctx.fill();
      // lança: segura com as duas mãos na frente do tronco; p.arm gira a haste
      ctx.save(); ctx.translate(8, -78 + b); ctx.rotate(-0.78 + p.arm * 0.6);
      ctx.strokeStyle = '#7a5532'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(-34, 0); ctx.lineTo(118, 0); ctx.stroke();
      ctx.fillStyle = '#e8eef5'; poly(ctx, [118, -6, 146, 0, 118, 6, 112, 0]);
      ctx.fillStyle = '#b8322f'; poly(ctx, [110, -3, 104, 8, 100, -2]);
      ctx.fillStyle = '#e0c9a8'; ctx.beginPath(); ctx.arc(-6, 0, 5, 0, 7); ctx.fill(); ctx.beginPath(); ctx.arc(22, 0, 5, 0, 7); ctx.fill();
      ctx.restore();
    },
    // Lutador: sem arma, faixas nas mãos, guarda alta; p.arm estende o soco da frente
    brawler(ctx, p) {
      const b = p.idle * 2.2, bounce = Math.abs(Math.sin(p.t * 0.006)) * 2;
      ctx.fillStyle = '#26202a'; poly(ctx, [-8, -46, 2, -46, -16, 0, -27, 0]); poly(ctx, [2, -46, 12, -46, 22, 0, 10, 0]);
      ctx.fillStyle = '#6a2a2a'; ctx.fillRect(-14, -50 - bounce, 28, 8);
      ctx.fillStyle = '#c98f6a'; poly(ctx, [-17, -98 + b, 17, -98 + b, 12, -48, -12, -48]);
      ctx.fillStyle = '#2a2430'; poly(ctx, [-17, -98 + b, -6, -98 + b, -8, -50, -14, -50]);
      ctx.fillStyle = '#c98f6a'; ctx.beginPath(); ctx.arc(3, -112 + b, 12, 0, 7); ctx.fill();
      ctx.fillStyle = '#2a1a14'; ctx.beginPath(); ctx.arc(1, -117 + b, 12, Math.PI * 1.0, Math.PI * 1.95); ctx.fill();
      ctx.fillStyle = '#c0382f'; ctx.fillRect(-10, -120 + b, 24, 4); poly(ctx, [-10, -120 + b, -24, -114 + b + Math.sin(p.t * 0.008) * 3, -10, -116 + b]);
      ctx.fillStyle = '#1a1210'; ctx.fillRect(8, -114 + b, 4, 2);
      // braço de trás (guarda) e braço da frente (soco)
      const ext = Math.max(0, p.arm) * 30, back = Math.min(0, p.arm) * 10;
      ctx.strokeStyle = '#b57e5c'; ctx.lineWidth = 8; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(-6, -92 + b); ctx.lineTo(8, -100 + b); ctx.stroke();
      ctx.fillStyle = '#efe4d2'; ctx.beginPath(); ctx.arc(10, -102 + b, 6.5, 0, 7); ctx.fill();
      ctx.strokeStyle = '#c98f6a'; ctx.beginPath(); ctx.moveTo(10, -92 + b); ctx.lineTo(22 + ext + back, -98 + b - ext * 0.1); ctx.stroke();
      ctx.fillStyle = '#f4ead8'; ctx.beginPath(); ctx.arc(24 + ext + back, -99 + b - ext * 0.1, 7.5, 0, 7); ctx.fill();
    },
    // Arqueira: capuz, capa curta; p.cast = quanto a corda está puxada
    archer(ctx, p) {
      const b = p.idle * 2;
      ctx.fillStyle = '#243a2e'; ctx.beginPath(); ctx.moveTo(-8, -98 + b); ctx.quadraticCurveTo(-34, -60, -26 + Math.sin(p.t * 0.004) * 3, -30); ctx.lineTo(-4, -46); ctx.fill();
      ctx.fillStyle = '#2a2420'; poly(ctx, [-6, -48, 3, -48, -12, 0, -22, 0]); poly(ctx, [1, -48, 10, -48, 20, 0, 9, 0]);
      ctx.fillStyle = '#4a6a3a'; poly(ctx, [-12, -98 + b, 12, -98 + b, 9, -46, -9, -46]);
      ctx.fillStyle = '#6b4a2e'; ctx.fillRect(-10, -60, 20, 4);
      ctx.fillStyle = '#7a5532'; rr(ctx, -16, -100 + b, 7, 34, 3); // aljava
      ctx.fillStyle = '#e8dcc0'; ctx.fillRect(-15, -108 + b, 2, 9); ctx.fillRect(-12, -106 + b, 2, 7);
      ctx.fillStyle = '#e6c4a0'; ctx.beginPath(); ctx.arc(2, -112 + b, 10, 0, 7); ctx.fill();
      ctx.fillStyle = '#2f4a3a'; ctx.beginPath(); ctx.moveTo(-12, -110 + b); ctx.quadraticCurveTo(-8, -134 + b, 6, -128 + b); ctx.quadraticCurveTo(16, -122 + b, 12, -110 + b); ctx.quadraticCurveTo(2, -118 + b, -12, -110 + b); ctx.fill();
      ctx.fillStyle = '#1a1210'; ctx.fillRect(6, -113 + b, 3, 2);
      // arco à frente; corda puxada até o peito conforme p.cast
      const draw = clamp(p.cast, 0, 1), bx = 26, by = -86 + b;
      ctx.strokeStyle = '#7a5532'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(bx - 30, by, 40, -0.95, 0.95); ctx.stroke();
      const top = { x: bx - 30 + Math.cos(-0.95) * 40, y: by + Math.sin(-0.95) * 40 }, bot = { x: bx - 30 + Math.cos(0.95) * 40, y: by + Math.sin(0.95) * 40 };
      const pull = { x: (top.x + bot.x) / 2 - draw * 26, y: by };
      ctx.strokeStyle = 'rgba(240,235,220,0.9)'; ctx.lineWidth = 1.3; ctx.beginPath(); ctx.moveTo(top.x, top.y); ctx.lineTo(pull.x, pull.y); ctx.lineTo(bot.x, bot.y); ctx.stroke();
      if (draw > 0.15) { ctx.strokeStyle = '#d9c39a'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(pull.x, by); ctx.lineTo(bx + 14, by); ctx.stroke(); ctx.fillStyle = '#e8eef5'; poly(ctx, [bx + 20, by, bx + 12, by - 3, bx + 12, by + 3]); }
      ctx.strokeStyle = '#e6c4a0'; ctx.lineWidth = 6; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(4, -92 + b); ctx.lineTo(bx + 8, by); ctx.stroke();            // braço do arco
      ctx.beginPath(); ctx.moveTo(-2, -92 + b); ctx.lineTo(pull.x, pull.y); ctx.stroke();       // braço da corda
    },
  });

  // Boneco de treino (só nas prévias das fichas)
  ART.dummy = function (ctx, p) {
    ctx.fillStyle = '#5a3a24'; ctx.fillRect(-4, -40, 8, 40); ctx.fillRect(-22, -2, 44, 6);
    ctx.fillStyle = '#c9a86a'; ctx.beginPath(); ctx.ellipse(0, -70, 20, 32, 0, 0, 7); ctx.fill();
    ctx.fillStyle = '#5a3a24'; ctx.fillRect(-34, -84, 68, 6);
    ctx.fillStyle = '#d9b97a'; ctx.beginPath(); ctx.arc(0, -112, 13, 0, 7); ctx.fill();
    ctx.strokeStyle = '#a03a2a'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(4, -70, 11, 0, 7); ctx.stroke(); ctx.beginPath(); ctx.arc(4, -70, 4, 0, 7); ctx.stroke();
  };
  MOVE.dummy = { dash: 1, ease: 'out', reach: 70, knock: 0.35, width: 70 };

  // Retrato para a tela de formação (usa a mesma arte do combate)
  G.drawPortrait = function (canvas, art, opts = {}) {
    const g = canvas.getContext('2d'), w = canvas.width, h = canvas.height;
    g.clearRect(0, 0, w, h);
    const bgc = g.createRadialGradient(w / 2, h * 0.55, 4, w / 2, h * 0.55, w * 0.7);
    bgc.addColorStop(0, opts.glow || '#3a2a44'); bgc.addColorStop(1, '#140e18');
    g.fillStyle = bgc; g.fillRect(0, 0, w, h);
    g.save(); g.translate(w / 2 - 8, h * 0.98); g.scale(h / 170, h / 170);
    ART[art](g, { idle: 0, t: performance.now(), arm: 0, guard: 0, cast: art === 'archer' ? 0.6 : 0, wound: 0 });
    g.restore();
  };

  G.Presenter = Presenter;
  G.HOME = HOME;
})(window);
