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
  };
  const LEVELS = ['light', 'medium', 'heavy', 'extreme'];
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
      this.threatened = null; this.nums = []; this.showLabels = true; this.highlight = null;
      this.bg = this._buildBackground();
      this.fog = Array.from({ length: 14 }, (_, i) => ({ x: Math.random() * W * 1.4 - 100, y: GROUND - 40 + Math.random() * 120, r: 80 + Math.random() * 120, v: 0.004 + Math.random() * 0.01 }));
      this._last = performance.now();
      this._resize();
      new ResizeObserver(() => this._resize()).observe(canvas.parentElement);
      requestAnimationFrame(t => this._frame(t));
    }

    // ------------------------------------------------------------ setup
    reset(battle) {
      this.vis = {};
      battle.units.forEach((u, i) => {
        const h = HOME[u.id];
        this.vis[u.id] = { id: u.id, art: u.def.art, name: u.name, side: u.side,
          face: u.side === 'ally' ? 1 : -1, home: h, x: h.x, y: h.y,
          lean: 0, arm: 0, guard: 0, cast: 0, crouch: 0, flash: 0, alpha: 1, hop: 0,
          barrier: 0, ready: 0, dead: u.hp <= 0, hp: u.hp, dispHp: u.hp, maxHp: u.maxHp,
          statuses: { ...u.statuses }, phase: i * 1.7, trail: [], stance: null,
          state: u.hp > 0 ? 'IDLE' : 'DEFEATED', tilt: 0, kneel: 0, busy: null };
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
    slowMo(factor, realMs) { if (this.skipping) return; this.slow = factor; this.slowTimer = realMs; }
    hitStop(realMs) { if (this.skipping) return; this.freeze = Math.max(this.freeze, realMs); }
    skip() {
      this.skipping = true;
      for (const tw of this.tweens) { Object.assign(tw.obj, tw.to); tw.res(); }
      for (const w of this.waits) w.res();
      this.tweens = []; this.waits = [];
      this.particles = []; this.texts = []; this.fx = []; this.banner = null; this.nums = [];
      this.slow = 1; this.freeze = 0;
    }

    _frame(now) {
      const real = Math.min(50, now - this._last); this._last = now;
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
      for (const f of this.fog) { f.x += f.v * real; if (f.x > W + 250) f.x = -250; }
    }

    // ------------------------------------------------------------ câmera
    overview() { this.follow = null; this.camT = { x: W / 2, y: this.viewCY || H / 2, z: 1 }; this.spot = null; }
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
      const span = Math.max(...xs) - Math.min(...xs) + 160; // margem para armas e recuos
      const z = clamp(1.85 - span / 1000, 1.05, 1.5) + extraZoom;
      // mantém o enquadramento dentro do cenário
      const hw = W / 2 / z, hh = H / 2 / z;
      this.camT = { x: clamp(cx, hw, W - hw), y: clamp(cy, hh * 0.6, H - hh), z };
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
    showBanner(text, color, dur = 900, sub = '') { if (!this.skipping) this.banner = { text, color, t: 0, dur, sub }; }
    hurtShake(amount) { if (!this.skipping) this.shake = Math.max(this.shake, amount); }

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

    // ------------------------------------------------------------ REAÇÕES FÍSICAS
    // level: light | medium | heavy | extreme  — dir: +1/-1 (para onde é empurrado)
    // Retorna rápido (depois do impacto); a recuperação continua em segundo plano.
    react(v, level, dir, killed) {
      const P = MOVE[v.art];
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
      this.hurtShake(defeated ? 8 : 6);
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
    followThrough(v) {
      return this.routine(v, async () => {
        this.setState(v, 'ATTACKING');
        await this.wait(120);
        await this.tween(v, { arm: 0.35, lean: 0.05, crouch: 0.04, cast: 0 }, 260, 'out');
        await this.tween(v, this._stancePose(v), 300, 'inOut');
        this.setState(v, v.stance ? STANCE_STATE[v.stance] : 'IDLE');
      });
    }
    _stancePose(v) {
      return { arm: v.stance === 'parry' ? -0.7 : 0, guard: v.stance === 'block' ? 1 : 0,
        cast: v.stance === 'dodge' ? 0.4 : 0, lean: 0, crouch: v.stance === 'dodge' ? 0.06 : 0 };
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
          this.tween(A, { ready: 1, guard: 1, arm: -0.5 }, 240);
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
          this.tween(A, { ready: 1, arm: magic ? -0.4 : -1.0, cast: magic ? 0.7 : 0, lean: -0.08 }, 240);
          if (magic) this.sparks(A.x + A.face * 26, A.y - 110, '#c86bff', 10, 0.2, -0.0004);
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
        if (ev.type === 'clash') await this.playClash(ev);
        else if (ev.type === 'attack') await this.playConfrontation(ev);
        else if (ev.type === 'stances') await this.playStances(ev);
        else if (ev.type === 'support') await this.playSupport(ev);
        else if (ev.type === 'fizzle') await this.playFizzle(ev);
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

    // Fim da rodada: ninguém volta à formação original. Cada um caminha só o
    // necessário para voltar ao seu lado da linha de frente, mantendo a ordem
    // relativa e a profundidade (leitura espacial preservada entre rodadas).
    endRound(snap) {
      this._applySnapshot(snap, true);
      const targets = {};
      for (const side of ['ally', 'enemy']) {
        const dir = side === 'ally' ? -1 : 1; // para onde fica a "retaguarda"
        const alive = Object.values(this.vis).filter(v => v.side === side && !v.dead)
          .sort((a, b) => dir < 0 ? b.x - a.x : a.x - b.x); // da frente para trás
        let prev = null;
        for (const v of alive) {
          let x = side === 'ally' ? Math.min(v.x, FRONT.ally) : Math.max(v.x, FRONT.enemy);
          const gap = prev ? (MOVE[prev.art].width + MOVE[v.art].width) / 2 + 8 : 0;
          if (prev && Math.abs(x - targets[prev.id]) < gap) x = targets[prev.id] + dir * gap;
          x = clamp(x, ARENA.minX, ARENA.maxX);
          targets[v.id] = x; prev = v;
        }
        // se a fila bateu na borda, empurra o grupo de volta para dentro
        const xs = alive.map(v => targets[v.id]);
        if (xs.length) {
          const over = side === 'ally' ? ARENA.minX - (Math.min(...xs) - 0) : (Math.max(...xs)) - ARENA.maxX;
          if (over > 0) alive.forEach(v => { targets[v.id] -= dir * over; });
        }
      }
      for (const id in this.vis) {
        const v = this.vis[id];
        v.stance = null;
        if (v.dead) continue;
        v.ready = 0; v.barrier = 0;
        this.setState(v, 'REPOSITIONING');
        const tx = targets[id];
        this.faceTo(v, { x: v.side === 'ally' ? v.x + 100 : v.x - 100 });
        this.tween(v, { x: tx, arm: 0, guard: 0, cast: 0, lean: 0, crouch: 0, tilt: 0, kneel: 0 }, clamp(Math.abs(tx - v.x) * 2.2, 200, 650), 'inOut')
          .then(() => { if (v.state === 'REPOSITIONING') this.setState(v, 'IDLE'); });
      }
      this.wait(680).then(() => this.settle());
    }

    _applySnapshot(snap, final) {
      for (const id in snap) {
        const v = this.vis[id];
        v.hp = snap[id].hp; v.statuses = { ...snap[id].statuses };
        if (this.skipping) v.dispHp = v.hp;
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
          this.float(T.x, T.y - 175, 'PROTEGIDO', '#9fd0ff', 18);
          v.dashing = true;
          this.faceTo(v, foe);
          moves.push(this.moveTo(v, T.x + dir * 82, T.y + 8, 300 * MOVE[v.art].dash, 'out').then(() => { v.dashing = false; }));
          vs.push(T);
        }
        this.float(v.x, v.y - 180, st.protectId ? 'PROTEÇÃO' : NAME[st.reaction], '#9fd0ff', 18);
        moves.push(this.tween(v, this._stancePose(v), 220, 'out'));
        if (st.reaction === 'dodge') this.sparks(v.x, v.y - 60, '#cfe9ff', 8, 0.2, -0.0003);
      }
      this.focusOn(vs, -0.3);
      if (ev.list.some(st => st.protectId)) this.showBanner('PROTEÇÃO', '#7fc4ff', 800, 'o Cavaleiro guarda um aliado');
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
      this.addFx({ kind: 'proj', dur: 340, x0: A.x + A.face * 30, y0: A.y - 115, x1: T.x, y1: T.y - 80, color: '#7fe0a0' });
      await this.wait(340);
      this.addFx({ kind: 'ring', dur: 400, x: T.x, y: T.y - 70, color: '#7fe0a0', r: 60 });
      this.sparks(T.x, T.y - 70, '#7fe0a0', 14, 0.25, -0.0004);
      this.float(T.x, T.y - 165, `+${G.CONFIG.support.amount} FORÇA`, '#7fe0a0', 22);
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
      return sk.hits || [{ by: 0, share: 1, motion: sk.tags.includes('magic') ? 'proj' : (sk.tags.includes('heavy') ? 'over' : 'h'), react: 'final' }];
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
    // Um golpe individual (cosmético: varia por "motion"; não muda nada da lógica).
    async _strikeMotion(A, L, motion, others = []) {
      const dir = L.x >= A.x ? 1 : -1;
      this.faceTo(A, L);
      this.setState(A, 'ATTACKING');
      if (motion === 'proj') {
        const up = this.time % 2 < 1 ? 1 : -1; // pequena variação no arco do lançamento
        await this.tween(A, { cast: 1, arm: -0.6 + up * 0.15 }, 90);
        this.tween(A, { arm: 0.3, lean: 0.08 }, 90);
        this.addFx({ kind: 'proj', dur: 240, x0: A.x + A.face * 30, y0: A.y - 115, x1: L.x - dir * 18, y1: L.y - 70, color: A.side === 'ally' ? '#8fd3ff' : '#c86bff', arc: 22 * up });
        await this.wait(240);
        return dir;
      }
      // abre espaço: outro atacante no ponto de golpe dá um passo atrás (coreografia)
      const standX = L.x - dir * MOVE[A.art].reach;
      let standY = A.y;
      for (const o of others) {
        if (o === A || o.dead || Math.abs(o.x - standX) > 60) continue;
        this.tween(o, { x: o.x - dir * 55, lean: -0.1 }, 160, 'out');
        standY = clamp(L.y + (L.y > (ARENA.minY + ARENA.maxY) / 2 ? -34 : 34), ARENA.minY, ARENA.maxY);
      }
      if (Math.abs(A.x - standX) > 18 || Math.abs(A.y - standY) > 10) {
        A.dashing = true;
        await this.moveTo(A, standX, standY, 130 * MOVE[A.art].dash, 'in');
        A.dashing = false;
      }
      const heavy = motion === 'over';
      await this.tween(A, { arm: heavy ? -1.7 : -1.2, lean: heavy ? -0.2 : 0.05 }, heavy ? 120 : 60, 'out');
      this.tween(A, { arm: 1.3, lean: 0.25 }, 70, 'in');
      await this.wait(45);
      if (motion === 'bash') {
        this.tween(A, { x: A.x + dir * 20, guard: 1 }, 80, 'out');
        this.addFx({ kind: 'ring', dur: 260, x: L.x - dir * 28, y: L.y - 72, color: '#cfe3ff', r: 40 });
      } else {
        const rot = motion === 'd' ? 0.55 : motion === 'over' ? -0.85 : 0;
        this.addFx({ kind: 'slash', dur: 240, x: L.x - dir * 30, y: L.y - 70, dir, heavy, rot, flip: motion === 'h2', color: '#fff3d6' });
      }
      return dir;
    }
    // Executa a sequência de golpes de uma habilidade (ou combinação) já vencida/acertada.
    // total/hpBefore/hpAfter vêm da lógica: a soma dos impactos é exatamente o dano real.
    async _sequence(attackers, L, sk, hit, finalLv, opts = {}) {
      const steps = this._steps(sk);
      const dmgs = this._splitDamage(hit.damage, steps.map(s => s.share));
      const dmgColor = L.side === 'ally' ? '#ff6a5a' : '#ffe08a';
      let hp = hit.hpBefore, lv = finalLv;
      for (let i = 0; i < steps.length; i++) {
        const st = steps[i], last = i === steps.length - 1;
        let A = attackers[st.by] || attackers[0];
        if (!A || A.dead) A = attackers.find(a => a && !a.dead) || attackers[0];
        if (attackers.length > 1) this.focusOn([...attackers.filter(a => !a.dead), L], 0.05);
        let dir = L.x >= A.x ? 1 : -1;
        if (i > 0 || !opts.firstDone) dir = await this._strikeMotion(A, L, st.motion, attackers);
        hp = last ? hit.hpAfter : Math.max(hit.hpAfter, hp - dmgs[i]);
        L.hp = hp;
        L.flash = 1;
        this.sparks(L.x - dir * 18, L.y - 72, opts.blocked ? '#cfe3ff' : (st.motion === 'proj' ? (A.side === 'ally' ? '#9ad8ff' : '#d38bff') : '#ff7a5a'), last ? 16 : 9, 0.5);
        const big = last && (hit.killed || steps.length === 1);
        this.float(L.x + (i % 2 ? 14 : -14), L.y - 128 - i * 10, String(dmgs[i]), dmgColor, big ? (hit.killed ? 46 : 32) : 24, big ? 1400 : 900);
        this.hitStop(last ? 70 : 40);
        this.hurtShake(2 + dmgs[i] * 0.3);
        lv = st.react === 'final' ? finalLv : st.react;
        if (opts.blocked) lv = LEVELS[Math.max(0, LEVELS.indexOf(lv) - 1)];
        if (!last) {
          // reação intermediária sincronizada com o contato (sem travar a sequência)
          const push = lv === 'light' ? 14 : 34;
          this.tween(L, { x: clamp(L.x + dir * push * MOVE[L.art].knock, ARENA.minX, ARENA.maxX), lean: lv === 'light' ? -0.25 : -0.4 }, 90, 'out')
            .then(() => this.tween(L, { lean: -0.1 }, 120));
          if (lv !== 'light') this.dust(L, 4);
          await this.wait(70);
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
      for (const a of attackers) if (a && !a.dead) this.followThrough(a);
      return lv;
    }

    // ------------------------------------------------------------ CLASH
    async playClash(ev) {
      const A = this.vis[ev.a.actorId], B = this.vis[ev.b.actorId];
      const skA = G.SKILLS[ev.a.skillId], skB = G.SKILLS[ev.b.skillId];
      const magA = skA.tags.includes('magic'), magB = skB.tags.includes('magic');
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
      else if (magA !== magB) { const M = magA ? A : B, O = magA ? B : A; P = { x: lerp(M.x, O.x, 0.55), y: (A.y + B.y) / 2 }; }
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
        this.showBanner('INTERCEPTAÇÃO!', '#7fc4ff', 900, `${A.name} entra na frente de ${T.name}`);
        this.slowMo(0.5, 420);
      } else await this.wait(230);

      // 4. aproximação / projéteis
      const go = [];
      for (const v of [A, B]) {
        const dir = v === A ? (P.x >= A.x ? 1 : -1) : (P.x >= B.x ? 1 : -1);
        if (!melee(v)) {
          this.tween(v, { arm: 0.3, lean: 0.08 }, 120);
          this.addFx({ kind: 'proj', dur: 300, x0: v.x + v.face * 30, y0: v.y - 115, x1: P.x, y1: P.y - 75, color: v.side === 'ally' ? '#8fd3ff' : '#c86bff' });
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

      // 5. choque das armas + resistência (mais longa se for equilibrado)
      const hy = P.y - (variant === 0 ? 95 : variant === 1 ? 55 : 75);
      this.hitStop(ev.close ? 150 : 90);
      this.addFx({ kind: 'star', dur: 380, x: P.x, y: hy, color: '#fff2a8' });
      this.sparks(P.x, hy, '#ffe28a', ev.close ? 28 : 16, 0.6);
      this.hurtShake(ev.close ? 7 : 4);
      if (ev.close) this.slowMo(0.5, 650);
      const struggle = ev.close ? 520 : 260;
      const t0 = this.time;
      const jitter = async () => {
        for (let i = 0; i < 6 && !this.skipping; i++) {
          const s = i % 2 ? 1 : -1;
          await Promise.all([this.tween(A, { lean: 0.25 + 0.06 * s }, struggle / 6), this.tween(B, { lean: 0.25 - 0.06 * s }, struggle / 6)]);
          if (i % 2) this.sparks(P.x, hy, '#ffe28a', 3, 0.3);
        }
      };
      const jit = jitter();

      // 6. valores de força (no próprio combate)
      const fmt = s => `${s.base}${s.mod ? (s.mod > 0 ? ' +' + s.mod : ' −' + -s.mod) : ''} + ${s.roll} = ${s.total}`;
      const left = A.x <= B.x;
      const nA = { kind: 'num', x: P.x + (left ? -95 : 95), y: P.y - 215, text: fmt(ev.a), color: '#9fd8ff', s: 0.6, a: 1, dy: 0 };
      const nB = { kind: 'num', x: P.x + (left ? 95 : -95), y: P.y - 185, text: fmt(ev.b), color: '#ff9a8a', s: 0.6, a: 1, dy: 0 };
      if (!this.skipping) this.nums = [nA, nB];
      this.tween(nA, { s: 1 }, 140, 'back'); await this.tween(nB, { s: 1 }, 140, 'back');
      await jit;
      await this.wait(ev.close ? 280 : 200);

      if (!ev.winner) {
        // empate: as forças se anulam e os dois são repelidos
        this.float(P.x, P.y - 240, 'EMPATE', '#e8dccb', 30);
        this.tween(nA, { a: 0 }, 300); this.tween(nB, { a: 0 }, 300);
        this.sparks(P.x, hy, '#ffe28a', 14, 0.5);
        this.react(A, 'medium', A.x < P.x ? -1 : 1);
        this.react(B, 'medium', B.x < P.x ? -1 : 1);
        [...pA, ...pB].forEach(p => this.react(p, 'light', p.x < P.x ? -1 : 1));
        await this.wait(380);
      } else {
        const aWins = ev.winner === A.id;
        const [W, L, nW, nL, skW, pW, pL] = aWins ? [A, B, nA, nB, skA, pA, pB] : [B, A, nB, nA, skB, pB, pA];
        pL.forEach(p => this.react(p, 'light', p.x < P.x ? -1 : 1)); // a combinação perdida é interrompida
        const dirL = L.x >= W.x ? 1 : -1;
        nW.color = '#ffe08a';
        this.tween(nW, { s: 1.45 }, 160, 'back');
        this.tween(nL, { a: 0, dy: 30 }, 260, 'in');
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
        this.tween(nW, { a: 0 }, 600);
        await this._sequence([W, ...pW], L, skW, h, lv);
        if (h.applied) { const st = G.STATUS[h.applied]; this.float(L.x, L.y - 165, st.name.toUpperCase(), st.color, 20, 1300); }
        if (h.killed || lv === 'extreme') await this._decisive(L, h.killed);
        await this.wait(lv === 'light' ? 220 : 320);
      }
      this.nums = [];
      this.caption = null;
    }

    // ------------------------------------------------------------ ATAQUE SEM OPOSIÇÃO
    async playConfrontation(c) {
      const sk = c.skill;
      const A = this.vis[c.attackerId], T = this.vis[c.targetId], D = this.vis[c.defenderId];
      const P = c.protectorId ? this.vis[c.protectorId] : null;
      const partners = (c.partners || []).map(id => this.vis[id]);
      const magic = sk.tags.includes('magic'), heavy = sk.tags.includes('heavy'), fast = sk.tags.includes('fast');
      this.caption = `${[A, ...partners].map(v => v.name).join(' + ')}  ·  ${sk.name}  →  ${T.name}`;
      if (sk.combo) this.showBanner('ATAQUE COMBINADO', '#ffd36a', 900, [A, ...partners].map(v => v.name).join(' + '));

      this.focusOn([A, T, ...partners]);
      await this.sync(A, ...partners);
      this.faceTo(A, T);

      // antecipação
      this.setState(A, 'PREPARING');
      if (magic) {
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
        this.showBanner('PROTEÇÃO!', '#7fc4ff', 900, `${P.name} recebe o golpe no lugar de ${T.name}`);
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
      if (magic) {
        this.tween(A, { arm: 0.3, lean: 0.08 }, 120);
        this.addFx({ kind: 'proj', dur: 380, x0: A.x + A.face * 30, y0: A.y - 115, x1: D.x - dirD * 20, y1: D.y - 70, color: A.side === 'ally' ? '#8fd3ff' : '#c86bff' });
        this._react(c, D, A, 260);
        await this.wait(380);
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
        this.addFx({ kind: 'slash', dur: 260, x: D.x - dirD * 30, y: D.y - 70, dir: dirD, heavy, color: c.outcome === 'dodged' ? 'rgba(255,255,255,0.5)' : '#fff3d6' });
      }

      await this._impact(c, A, D, magic, dirD, [A, ...partners]);

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

    async _impact(c, A, D, magic, dir, attackers = [A]) {
      const hx = D.x - dir * 18, hy = D.y - 72;
      const dmgColor = D.side === 'ally' ? '#ff6a5a' : '#ffe08a';
      const showDamage = (v, n, big) => this.float(v.x + (Math.random() * 20 - 10), v.y - 130, String(n), dmgColor, big ? 46 : 32, big ? 1500 : 1100);

      switch (c.outcome) {
        case 'dodged':
          this.float(D.x, D.y - 140, 'ESQUIVA', '#cfe9ff', 26);
          this.sparks(D.x, D.y - 40, 'rgba(220,230,255,0.6)', 8, 0.25, 0);
          await this.wait(220);
          return;
        case 'parried': {
          // aparo: personagens ficam próximos no choque
          this.tween(D, { arm: 1.1 }, 60, 'in');
          this.hitStop(120);
          this.addFx({ kind: 'star', dur: 420, x: hx, y: hy, color: '#fff2a8' });
          this.sparks(hx, hy, '#ffe28a', 26, 0.7);
          this.hurtShake(6);
          this.showBanner('APARADO!', '#ffe28a', 900, 'contra-ataque');
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
          A.flash = 1;
          this.sparks(A.x, A.y - 70, '#ff8a6a', 14, 0.5);
          const cd = c.counter;
          this.float(A.x, A.y - 130, String(cd.damage), A.side === 'ally' ? '#ff6a5a' : '#ffe08a', cd.killed ? 46 : 32);
          this.float(A.x, A.y - 165, 'CONTRA-ATAQUE', '#ffe28a', 18);
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
          this.float(D.x, D.y - 165, 'BLOQUEIO', '#9fd0ff', 18);
          await this._sequence(attackers, D, c.skill, c, c.impact || 'light', { firstDone: true, blocked: true });
          if (c.killed) await this._decisive(D, true);
          await this.wait(180);
          return;
        }
        default: { // hit, dodgeFail, parryFail, guardBroken — todos os golpes da sequência acertam
          if (c.outcome === 'parryFail') this.float(D.x, D.y - 165, 'APARO FALHOU', '#ff8a6a', 18);
          else if (c.outcome === 'dodgeFail') this.float(D.x, D.y - 165, 'ESQUIVA FALHOU', '#ff8a6a', 18);
          if (magic) this.addFx({ kind: 'ring', dur: 360, x: hx, y: hy, color: A.side === 'ally' ? '#8fd3ff' : '#c86bff', r: 50 });
          const lv = await this._sequence(attackers, D, c.skill, c, c.impact || 'light', { firstDone: true });
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
      this.showBanner(killed ? 'DERROTADO!' : 'DERRUBADA!', killed ? '#ff6a5a' : '#ffb36a', 950);
      await this.wait(220);
    }

    // ============================================================ DESENHO
    _buildBackground() {
      const c = document.createElement('canvas'); c.width = W; c.height = H;
      const g = c.getContext('2d');
      const sky = g.createLinearGradient(0, 0, 0, GROUND);
      sky.addColorStop(0, '#0d0a18'); sky.addColorStop(0.6, '#2a1830'); sky.addColorStop(1, '#4a2a35');
      g.fillStyle = sky; g.fillRect(0, 0, W, H);
      // lua
      const moon = g.createRadialGradient(930, 150, 10, 930, 150, 160);
      moon.addColorStop(0, 'rgba(255,230,210,0.95)'); moon.addColorStop(0.25, 'rgba(255,200,180,0.35)'); moon.addColorStop(1, 'rgba(255,200,180,0)');
      g.fillStyle = moon; g.fillRect(700, 0, 460, 360);
      g.fillStyle = '#f3dccb'; g.beginPath(); g.arc(930, 150, 44, 0, 7); g.fill();
      // ruínas distantes
      const rnd = G.makeRng(7);
      g.fillStyle = '#1c1224';
      for (let i = 0; i < 16; i++) {
        const x = i * 90 - 20 + rnd() * 40, h = 90 + rnd() * 170, w = 26 + rnd() * 30;
        g.fillRect(x, GROUND - 60 - h, w, h + 60);
        if (rnd() < 0.5) { g.beginPath(); g.moveTo(x - 6, GROUND - 60 - h); g.lineTo(x + w / 2, GROUND - 100 - h); g.lineTo(x + w + 6, GROUND - 60 - h); g.fill(); }
        if (rnd() < 0.4) { g.fillStyle = 'rgba(255,170,90,0.35)'; g.fillRect(x + w / 2 - 3, GROUND - 40 - h * 0.6, 6, 10); g.fillStyle = '#1c1224'; }
      }
      // arco em ruínas mais próximo
      g.fillStyle = '#150d1b';
      g.fillRect(40, GROUND - 250, 40, 250); g.fillRect(1200, GROUND - 280, 44, 280);
      // chão
      const gr = g.createLinearGradient(0, GROUND - 40, 0, H);
      gr.addColorStop(0, '#2b1f2a'); gr.addColorStop(1, '#0e0a10');
      g.fillStyle = gr; g.fillRect(0, GROUND - 40, W, H);
      g.strokeStyle = 'rgba(255,255,255,0.05)'; g.lineWidth = 2;
      for (let i = 0; i < 9; i++) { const y = GROUND - 20 + i * i * 2.4; g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke(); }
      for (let i = -12; i < 26; i++) { g.beginPath(); g.moveTo(W / 2 + i * 40, GROUND - 40); g.lineTo(W / 2 + i * 120, H); g.stroke(); }
      return c;
    }

    _draw() {
      const ctx = this.ctx;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.fillStyle = '#07050a'; ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
      const s = this.scale * this.dpr;
      ctx.setTransform(s, 0, 0, s, this.offX * this.dpr, this.offY * this.dpr);
      // mundo
      ctx.save();
      const sh = this.shake;
      ctx.translate(W / 2 + (Math.random() - 0.5) * sh, this.viewCY + (Math.random() - 0.5) * sh);
      ctx.scale(this.cam.z, this.cam.z);
      ctx.translate(-this.cam.x, -this.cam.y);
      ctx.drawImage(this.bg, 0, 0);
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
      this._bars = lerp(this._bars || 0, focusing ? 1 : 0, 0.08);
      if (this._bars > 0.01) { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, 46 * this._bars); ctx.fillRect(0, H - 46 * this._bars, W, 46 * this._bars); }
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
      ctx.fillStyle = v.side === 'ally' ? (real < 0.3 ? '#ff6a4a' : '#5fd08a') : '#d8484a';
      ctx.fillRect(x - w / 2, y, w * Math.min(ratio, real), 7);
      if (this.showLabels) {
        ctx.font = '700 13px "Trebuchet MS", sans-serif'; ctx.textAlign = 'center';
        ctx.fillStyle = '#e9dfcf'; ctx.fillText(`${v.name}  ${Math.max(0, Math.round(v.hp))}`, x, y - 6);
      }
      let i = 0;
      for (const k in v.statuses) {
        const st = G.STATUS[k]; if (!st) continue;
        const sx = x - w / 2 + 8 + i * 20, sy = y + 20;
        ctx.fillStyle = st.color; ctx.beginPath(); ctx.arc(sx, sy, 8, 0, 7); ctx.fill();
        ctx.fillStyle = '#140c14'; ctx.font = '900 11px sans-serif'; ctx.fillText(st.icon, sx, sy + 4);
        i++;
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
          const r = f.heavy ? 85 : 65, a0 = -1.9, a1 = -1.9 + 2.6 * Math.min(1, p * 2.5);
          ctx.beginPath(); ctx.arc(-20, 0, r, a0, a1); ctx.stroke();
          ctx.lineWidth = 2; ctx.strokeStyle = '#fff'; ctx.beginPath(); ctx.arc(-20, 0, r + 6, a0 + 0.2, a1); ctx.stroke();
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
      // sombra
      ctx.fillStyle = 'rgba(0,0,0,0.45)';
      ctx.beginPath(); ctx.ellipse(0, 2, 44 - v.hop * 0.3, 10, 0, 0, 7); ctx.fill();
      const down = v.dead || v.state === 'KNOCKDOWN';
      const idle = down ? 0 : Math.sin(t * 0.004 + v.phase);
      // animações secundárias contextuais
      let ctxLean = 0, ctxCrouch = 0;
      if (v.state === 'PREPARING') ctxLean = Math.sin(t * 0.03) * 0.015;               // tensão antes do golpe
      else if (v.state === 'STAGGERING' || v.state === 'GETTING_UP') ctxLean = Math.sin(t * 0.012) * 0.04;
      else if (v.state === 'IDLE' && v.threat) ctxCrouch = 0.04;                          // ameaçado: abaixa a guarda
      ctx.translate(0, -v.hop);
      ctx.scale(v.face, 1);
      ctx.rotate(v.lean * 0.6 + v.tilt + ctxLean);
      ctx.scale(1 + (v.crouch + ctxCrouch) * 0.5, 1 - v.crouch - ctxCrouch);
      const filters = [];
      if (v.flash > 0.05) filters.push(`brightness(${1 + v.flash * 1.1})`);
      if (dim) filters.push('brightness(0.45)');
      if (v.dead) filters.push('grayscale(0.9) brightness(0.6)');
      ctx.filter = filters.length ? filters.join(' ') : 'none';
      ctx.globalAlpha = v.alpha;
      const threatGuard = v.threat && v.state === 'IDLE' ? 0.45 : 0;
      const pose = { idle, t, arm: v.arm + (down ? 0 : idle * 0.05) + (v.ready ? Math.sin(t * 0.01) * 0.05 : 0), guard: Math.max(v.guard, threatGuard), cast: v.cast + (v.ready ? 0.2 * Math.sin(t * 0.01) : 0) };
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
      const gx = 24 + p.guard * 16, gy = -70 + b - p.guard * 8;
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

  G.Presenter = Presenter;
  G.HOME = HOME;
})(window);
