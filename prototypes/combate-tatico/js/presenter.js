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
      this.plans = []; this.intents = []; this.showLabels = true; this.highlight = null;
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
          statuses: { ...u.statuses }, phase: i * 1.7, trail: [] };
      });
      this.tweens = []; this.waits = []; this.particles = []; this.texts = []; this.fx = [];
      this.banner = null; this.caption = null; this.spot = null;
      this.plans = []; this.intents = [];
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
      this.particles = []; this.texts = []; this.fx = []; this.banner = null;
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
    overview() { this.camT = { x: W / 2, y: this.viewCY || H / 2, z: 1 }; this.spot = null; }
    focusOn(vs, extraZoom = 0) {
      const xs = vs.map(v => v.x), ys = vs.map(v => v.y - 55);
      const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
      const cy = (Math.min(...ys) + Math.max(...ys)) / 2;
      const span = Math.max(...xs) - Math.min(...xs);
      const z = clamp(1.9 - span / 900, 1.15, 1.75) + extraZoom;
      // mantém o enquadramento dentro do cenário
      const hw = W / 2 / z, hh = H / 2 / z;
      this.camT = { x: clamp(cx, hw, W - hw), y: clamp(cy, hh * 0.6, H - hh), z };
      this.spot = new Set(vs.map(v => v.id));
    }
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
        if (Math.abs(p.x - v.x) < 48 && p.y < v.y + 12 && p.y > v.y - 150) {
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

    // ------------------------------------------------------------ intenções
    async announceIntents(intents, battle) {
      this.intents = [];
      for (const it of intents) {
        const A = this.vis[it.attackerId], T = this.vis[it.targetId], sk = G.SKILLS[it.skillId];
        this.focusOn([A, T], -0.1);
        this.tween(A, { ready: 1, arm: sk.tags.includes('magic') ? -0.4 : -1.0, cast: sk.tags.includes('magic') ? 0.7 : 0, lean: -0.08 }, 260);
        if (sk.tags.includes('magic')) this.sparks(A.x + A.face * 26, A.y - 110, '#c86bff', 10, 0.2, -0.0004);
        this.caption = (sk.telegraph || '{u} mira em {t}.').replace('{u}', A.name).replace('{t}', T.name);
        this.intents.push(it);
        await this.wait(950);
      }
      this.caption = null;
      this.overview();
      await this.wait(250);
    }
    clearIntents() {
      this.intents = [];
      for (const id in this.vis) this.vis[id].ready = 0;
    }

    // ------------------------------------------------------------ reprodução
    async playAll(results) {
      this.clearIntents(); this.plans = [];
      this.showLabels = false;
      for (const c of results) {
        await this.playConfrontation(c);
        this._applySnapshot(c.after);
      }
      this.caption = null;
      this.overview();
      for (const id in this.vis) this._resetPose(this.vis[id]);
      await this.wait(300);
      this.showLabels = true;
      this.skipping = false;
    }

    _applySnapshot(snap) {
      for (const id in snap) {
        const v = this.vis[id];
        v.hp = snap[id].hp; v.statuses = { ...snap[id].statuses };
        if (this.skipping) v.dispHp = v.hp;
        if (v.hp <= 0 && !v.dead) this._die(v);
      }
    }
    _resetPose(v) {
      Object.assign(v, { x: v.home.x, y: v.home.y, arm: 0, guard: 0, cast: 0, lean: v.dead ? v.lean : 0, ready: 0, barrier: 0, dashing: false, hop: 0 });
      v.trail = [];
    }
    _die(v) {
      v.dead = true;
      this.tween(v, { lean: -1.35 * 1, crouch: 0.25, alpha: 0.4 }, 520, 'out');
    }

    async playConfrontation(c) {
      const sk = c.skill;
      const A = this.vis[c.attackerId], T = this.vis[c.targetId], D = this.vis[c.defenderId];
      const P = c.protectorId ? this.vis[c.protectorId] : null;
      const magic = sk.tags.includes('magic'), heavy = sk.tags.includes('heavy'), fast = sk.tags.includes('fast');
      const reactName = G.REACTIONS[c.reaction].name;
      this.caption = `${A.name}  ·  ${sk.name}  →  ${T.name}`;

      // 1. câmera aproxima atacante e alvo
      this.focusOn([A, T]);
      await this.wait(fast ? 180 : 280);

      // 2. preparação (antecipação)
      if (magic) {
        this.tween(A, { cast: 1, lean: -0.1, arm: -0.5 }, 300);
        for (let i = 0; i < 3; i++) { this.sparks(A.x + A.face * 26, A.y - 112, '#9ad8ff', 6, 0.18, -0.0005); await this.wait(110); }
      } else {
        await this.tween(A, { lean: -0.22, arm: -1.5, crouch: 0.08 }, heavy ? 430 : fast ? 150 : 250, 'out');
        if (heavy) await this.wait(120);
      }

      // 3a. intervenção: protetor entra fisicamente no confronto
      if (P) {
        this.showBanner('PROTEÇÃO!', '#7fc4ff', 900, `${P.name} intercepta o golpe`);
        this.slowMo(0.45, 500);
        this.focusOn([A, P, T]);
        const px = T.x + T.face * 78, py = T.y + 6;
        P.dashing = true;
        await this.tween(P, { x: px, y: py, guard: 1, lean: 0.15 }, 280, 'out');
        P.dashing = false;
        this.sparks(px, py - 10, '#c8d6ff', 10, 0.3);
        await this.wait(120);
      }

      // 3b. avanço / projétil + 4. reação do defensor
      const reactAt = magic ? 300 : (fast ? 90 : heavy ? 150 : 120);
      const contact = { x: D.x - A.face * 30, y: D.y - 70 };
      if (magic) {
        this.tween(A, { arm: 0.3, lean: 0.08 }, 120);
        const sx = A.x + A.face * 30, sy = A.y - 115;
        this.addFx({ kind: 'proj', dur: 420, x0: sx, y0: sy, x1: contact.x + A.face * 10, y1: contact.y, color: A.side === 'ally' ? '#8fd3ff' : '#c86bff' });
        this._react(c, D, A, reactAt);
        await this.wait(420);
      } else {
        const standX = D.x - A.face * 82;
        A.dashing = true;
        const dash = this.tween(A, { x: standX, y: D.y + 2, lean: 0.25, crouch: 0 }, fast ? 140 : heavy ? 240 : 180, 'in');
        this._react(c, D, A, reactAt);
        await dash;
        A.dashing = false;
        // golpe
        this.tween(A, { arm: 1.3 }, fast ? 70 : 100, 'in');
        await this.wait(fast ? 50 : 80);
        this.addFx({ kind: 'slash', dur: 260, x: contact.x, y: contact.y, dir: A.face, heavy, color: c.outcome === 'dodged' ? 'rgba(255,255,255,0.5)' : '#fff3d6' });
      }

      // 5. impacto / esquiva
      await this._impact(c, A, D, magic);

      // 6. resultado (status)
      this._applySnapshot(c.after);
      if (c.consumed.includes('mark')) this.float(D.x, D.y - 165, 'Marca consumida!', '#b58cff', 18);
      if (c.consumed.includes('vulnerable') && c.damage > 0) this.float(D.x, D.y - 190, 'Vulnerável explorado!', '#ff9a3c', 18);
      if (c.applied) {
        const st = G.STATUS[c.applied];
        this.float(D.x, D.y - 150, st.name.toUpperCase(), st.color, 20, 1300);
        this.sparks(D.x, D.y - 70, st.color, 10, 0.2, -0.0003);
      }
      await this.wait(c.decisive ? 520 : 320);

      // 7. retorno às posições
      this.caption = null;
      const back = [A, D, P].filter(Boolean);
      const ps = back.map(v => {
        if (v.dead) return this.tween(v, { x: v.home.x * 0.15 + v.x * 0.85 }, 300);
        v.barrier = 0;
        return this.tween(v, { x: v.home.x, y: v.home.y, arm: 0, guard: 0, cast: 0, lean: 0, crouch: 0, hop: 0 }, 320, 'inOut');
      });
      this.overview();
      await Promise.all(ps);
      await this.wait(120);
    }

    async _react(c, D, A, delay) {
      await this.wait(delay);
      const awayX = -D.face; // afastando do atacante
      switch (c.reaction) {
        case 'block': this.tween(D, { guard: 1, lean: -0.08, crouch: 0.06 }, 110); break;
        case 'barrier': this.tween(D, { barrier: 1, cast: 0.8, arm: -0.6 }, 120); break;
        case 'dodge':
          if (c.outcome === 'dodged') {
            D.dashing = true;
            this.tween(D, { x: D.x + awayX * 95, hop: 38, lean: -0.35 }, 170, 'out').then(() => { D.dashing = false; this.tween(D, { hop: 0 }, 140, 'in'); });
          } else this.tween(D, { x: D.x + awayX * 22, hop: 10, lean: -0.2 }, 160, 'out');
          break;
        case 'parry': this.tween(D, { arm: -1.1, lean: 0.05 }, 90); break;
      }
    }

    async _impact(c, A, D, magic) {
      const hx = D.x - A.face * 18, hy = D.y - 72;
      const dmgColor = D.side === 'ally' ? '#ff6a5a' : '#ffe08a';
      const decisive = c.decisive;
      const showDamage = (v, n, big) => this.float(v.x + (Math.random() * 20 - 10), v.y - 130, String(n), dmgColor, big ? 46 : 32, big ? 1500 : 1100);
      const push = (v, dist, dur = 130) => this.tween(v, { x: v.x - v.face * dist }, dur, 'out');

      switch (c.outcome) {
        case 'dodged':
          this.float(D.x, D.y - 140, 'ESQUIVA', '#cfe9ff', 26);
          this.sparks(D.x, D.y - 40, 'rgba(220,230,255,0.6)', 8, 0.25, 0);
          await this.wait(200);
          return;
        case 'parried': {
          this.tween(D, { arm: 1.1 }, 60, 'in');
          this.hitStop(110);
          this.addFx({ kind: 'star', dur: 420, x: hx, y: hy, color: '#fff2a8' });
          this.sparks(hx, hy, '#ffe28a', 26, 0.7);
          this.hurtShake(7);
          this.showBanner('APARADO!', '#ffe28a', 900, 'contra-ataque');
          this.slowMo(0.4, 450);
          this.focusOn([A, D], 0.15);
          this.tween(A, { x: A.x - A.face * 55, lean: -0.4, arm: -0.4 }, 220, 'out');
          await this.wait(320);
          // contra-ataque (não pode ser reagido)
          D.dashing = true;
          await this.tween(D, { x: D.x + D.face * 45, arm: -1.4, lean: 0.2 }, 120, 'in');
          D.dashing = false;
          this.tween(D, { arm: 1.2 }, 80, 'in');
          await this.wait(60);
          this.addFx({ kind: 'slash', dur: 240, x: A.x + D.face * 10, y: A.y - 70, dir: D.face, heavy: false, color: '#fff3d6' });
          A.flash = 1;
          this.sparks(A.x, A.y - 70, '#ff8a6a', 14, 0.5);
          const cd = c.counter;
          this.float(A.x, A.y - 130, String(cd.damage), A.side === 'ally' ? '#ff6a5a' : '#ffe08a', cd.killed ? 46 : 32);
          this.float(A.x, A.y - 165, 'CONTRA-ATAQUE', '#ffe28a', 18);
          A.hp = cd.hpAfter;
          push(A, 30);
          if (cd.killed) { this.slowMo(0.3, 700); this.hitStop(140); this.hurtShake(14); this.screenFlash = 0.35; }
          else this.hurtShake(6);
          await this.wait(cd.killed ? 450 : 250);
          return;
        }
        case 'blocked':
          if (c.reaction === 'barrier') {
            this.addFx({ kind: 'ring', dur: 380, x: D.x + D.face * 20, y: D.y - 70, color: '#8fd3ff', r: 60 });
            this.sparks(hx, hy, '#8fd3ff', 14, 0.4);
          } else {
            this.addFx({ kind: 'ring', dur: 260, x: hx + D.face * 12, y: hy, color: '#cfe3ff', r: 36 });
            this.sparks(hx, hy, '#cfe3ff', 16, 0.55);
          }
          this.float(D.x, D.y - 165, c.reaction === 'barrier' ? 'BARREIRA' : 'BLOQUEIO', '#9fd0ff', 18);
          showDamage(D, c.damage, false);
          D.hp = c.hpAfter;
          push(D, 22);
          this.hitStop(60);
          this.hurtShake(3 + c.damage * 0.15);
          if (decisive) await this._decisive(D);
          await this.wait(220);
          return;
        default: { // hit, dodgeFail, parryFail, guardBroken
          if (c.outcome === 'guardBroken') {
            this.float(D.x, D.y - 165, 'GUARDA ATRAVESSADA', '#ff9a3c', 18);
            this.sparks(hx, hy, '#b0c4ff', 10, 0.6);
          } else if (c.outcome === 'parryFail') this.float(D.x, D.y - 165, 'APARO FALHOU', '#ff8a6a', 18);
          else if (c.outcome === 'dodgeFail') this.float(D.x, D.y - 165, 'ESQUIVA FALHOU', '#ff8a6a', 18);
          D.flash = 1;
          if (magic) this.addFx({ kind: 'ring', dur: 360, x: hx, y: hy, color: A.side === 'ally' ? '#8fd3ff' : '#c86bff', r: 50 });
          this.sparks(hx, hy, magic ? (A.side === 'ally' ? '#9ad8ff' : '#d38bff') : '#ff7a5a', 18, 0.55);
          showDamage(D, c.damage, decisive);
          D.hp = c.hpAfter;
          push(D, 30 + (decisive ? 30 : 0));
          this.tween(D, { lean: -0.25, guard: 0 }, 120);
          this.hitStop(decisive ? 0 : 70);
          this.hurtShake(4 + c.damage * 0.25);
          if (decisive) await this._decisive(D);
          await this.wait(240);
        }
      }
    }

    async _decisive(D) {
      this.hitStop(150);
      this.slowMo(0.3, 750);
      this.hurtShake(16);
      this.screenFlash = 0.35;
      this.focusOn([D], 0.25);
      this.addFx({ kind: 'ring', dur: 600, x: D.x, y: D.y - 70, color: '#ffffff', r: 110 });
      this.showBanner(D.hp <= 0 || D.dead ? 'DERRUBADO!' : 'GOLPE DECISIVO!', '#ff6a5a', 1000);
      await this.wait(260);
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
      const list = Object.values(this.vis).sort((a, b) => (a.dead - b.dead) || (a.y - b.y));
      for (const v of list) this._drawUnit(ctx, v);
      this._drawFx(ctx);
      for (const v of list) this._drawHud(ctx, v);
      this._drawArrows(ctx);
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
      // círculo no chão para seleção / alvos de intenção
      for (const id in this.vis) {
        const v = this.vis[id];
        if (v.dead) continue;
        const targeted = this.intents.some(it => it.targetId === id);
        const hl = this.highlight && this.highlight.has(id);
        if (!targeted && !hl) continue;
        const pulse = 0.6 + Math.sin(this.time * 0.008) * 0.25;
        ctx.save(); ctx.translate(v.home.x, v.home.y + 4); ctx.scale(1, 0.32);
        ctx.lineWidth = 6;
        ctx.strokeStyle = hl ? `rgba(255,226,140,${pulse})` : `rgba(255,70,70,${pulse})`;
        ctx.beginPath(); ctx.arc(0, 0, 58, 0, 7); ctx.stroke();
        ctx.restore();
      }
    }

    _arrow(ctx, from, to, color, label, order, dashed) {
      const x0 = from.x, y0 = from.y - 150, x1 = to.x, y1 = to.y - 150;
      const mx = (x0 + x1) / 2, my = Math.min(y0, y1) - 50 - Math.abs(x1 - x0) * 0.06 - (order || 0) * 14;
      ctx.save();
      ctx.strokeStyle = color; ctx.lineWidth = 3.5; ctx.globalAlpha = 0.9;
      if (dashed) { ctx.setLineDash([12, 8]); ctx.lineDashOffset = -this.time * 0.05; }
      ctx.beginPath(); ctx.moveTo(x0, y0); ctx.quadraticCurveTo(mx, my, x1, y1 - 8); ctx.stroke();
      ctx.setLineDash([]);
      const ang = Math.atan2(y1 - 8 - my, x1 - mx);
      ctx.fillStyle = color; ctx.beginPath();
      ctx.moveTo(x1, y1 - 2); ctx.lineTo(x1 - Math.cos(ang - 0.45) * 18, y1 - 8 - Math.sin(ang - 0.45) * 18);
      ctx.lineTo(x1 - Math.cos(ang + 0.45) * 18, y1 - 8 - Math.sin(ang + 0.45) * 18); ctx.fill();
      // rótulo perto da origem: cada atacante tem posição própria, então não se sobrepõem
      const q = 0.22, lx = (1 - q) * (1 - q) * x0 + 2 * q * (1 - q) * mx + q * q * x1, ly = (1 - q) * (1 - q) * y0 + 2 * q * (1 - q) * my + q * q * y1 - 6;
      ctx.font = '700 15px "Trebuchet MS", sans-serif'; ctx.textAlign = 'center';
      const text = (order ? order + '. ' : '') + label;
      const w = ctx.measureText(text).width + 16;
      ctx.fillStyle = 'rgba(10,6,14,0.85)'; ctx.fillRect(lx - w / 2, ly - 16, w, 24);
      ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.strokeRect(lx - w / 2, ly - 16, w, 24);
      ctx.fillStyle = '#f2e8da'; ctx.fillText(text, lx, ly + 1);
      ctx.restore();
    }

    _drawArrows(ctx) {
      for (const p of this.plans) this._arrow(ctx, this.vis[p.attackerId].home, this.vis[p.targetId].home, '#7fd0ff', G.SKILLS[p.skillId].name, p.order, false);
      for (const it of this.intents) {
        const pr = it.protect ? this.vis.knight : null;
        this._arrow(ctx, this.vis[it.attackerId].home, this.vis[it.targetId].home, '#ff5a5a', G.SKILLS[it.skillId].name, it.order, true);
        if (pr) this._arrow(ctx, pr.home, this.vis[it.targetId].home, '#9fd0ff', 'Proteger', null, false);
      }
    }

    _drawHud(ctx, v) {
      if (v.dead && v.alpha < 0.5) return;
      const dim = this.spot && !this.spot.has(v.id);
      if (dim && !this.showLabels) return; // menos ruído durante as animações
      const x = v.x, y = v.y - 150 - v.hop;
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
          ctx.translate(f.x, f.y); ctx.scale(f.dir, 1);
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
          const x = lerp(f.x0, f.x1, e), y = lerp(f.y0, f.y1, e) - Math.sin(p * Math.PI) * 30;
          for (let i = 6; i >= 0; i--) {
            const q = Math.max(0, e - i * 0.04);
            const tx = lerp(f.x0, f.x1, q), ty = lerp(f.y0, f.y1, q) - Math.sin(Math.max(0, p - i * 0.04) * Math.PI) * 30;
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
      const dim = this.spot && !this.spot.has(v.id);
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
      const idle = v.dead ? 0 : Math.sin(t * 0.004 + v.phase);
      ctx.translate(0, -v.hop);
      ctx.scale(v.face, 1);
      ctx.rotate(v.lean * (v.dead ? 1 : 0.6));
      ctx.scale(1 + v.crouch * 0.5, 1 - v.crouch);
      const filters = [];
      if (v.flash > 0.05) filters.push(`brightness(${1 + v.flash * 2.2})`);
      if (dim) filters.push('brightness(0.45)');
      if (v.dead) filters.push('grayscale(0.9) brightness(0.6)');
      ctx.filter = filters.length ? filters.join(' ') : 'none';
      ctx.globalAlpha = v.alpha;
      const pose = { idle, t, arm: v.arm + (v.dead ? 0.8 : idle * 0.05) + (v.ready ? Math.sin(t * 0.01) * 0.05 : 0), guard: v.guard, cast: v.cast + (v.ready ? 0.2 * Math.sin(t * 0.01) : 0) };
      ART[v.art](ctx, pose);
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
