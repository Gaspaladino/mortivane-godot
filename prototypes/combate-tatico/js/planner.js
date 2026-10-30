// =====================================================================
// PLANEJAMENTO NA ARENA — seleção direta, menu radial e correntes.
//   SelectionController + RadialAbilityMenu + TargetingController +
//   InputController + ChainRenderer + ClashPreview, num só módulo.
// Não decide nada de combate: registra escolhas via callbacks e pede a
// prévia à lógica real (battle.buildPlan / previewPlan).
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS } = G;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const DRAG_PX = 8;
  const KIND_STYLE = {
    attack:  { color: '#d8664a', dark: '#5a1f16', link: 'oval',   label: 'Ataque' },
    support: { color: '#72d18f', dark: '#16452a', link: 'round',  label: 'Suporte' },
    protect: { color: '#8fc0ec', dark: '#1a3552', link: 'square', label: 'Proteção' },
    defense: { color: '#8fc0ec', dark: '#1a3552', link: 'square', label: 'Defesa' },
    combo:   { color: '#e8c060', dark: '#4a3810', link: 'double', label: 'Ataque combinado' },
  };
  const styleOf = sk => sk.combo ? 'combo' : sk.kind;
  const CAT_COLOR = { favorable: '#6fd890', even: '#ffd36a', unfavorable: '#ff7a6a', certain: '#7fffb0', doomed: '#ff5050' };
  const CAT_NAME = { favorable: 'Favorável', even: 'Equilibrado', unfavorable: 'Desfavorável', certain: 'Vitória certa', doomed: 'Derrota certa' };

  class Planner {
    // cb: { battle(), choices(), plan(), preview(), commit(uid, skillId, targetId), cancel(uid), toggleIntercept(uid) }
    constructor(presenter, cb) {
      this.p = presenter; this.cb = cb;
      this.enabled = false; this.showIntents = false; this.fade = 1;
      this.sel = null;      // { uid, skillId, openAt }
      this.drag = null;     // { uid, skillId }
      this.press = null;    // { kind, id, sx, sy }
      this.mouse = { x: 0, y: 0, sx: 0, sy: 0 };
      this.hover = { unit: null, item: null, badge: null };
      this.connectAt = {}; this.retracts = []; this.items = []; this.badges = [];
      this.previewCache = { key: null, lines: null };
      presenter.ui = this;
      this._bindInput(presenter.canvas);
    }

    get battle() { return this.cb.battle(); }
    setEnabled(on) {
      this.enabled = on;
      if (!on) { this.sel = null; this.drag = null; this.press = null; this._applyHighlights(); }
      this.p.canvas.style.cursor = 'default';
      this.p.tween(this, { fade: on ? 1 : 0 }, on ? 200 : 320);
    }

    // ------------------------------------------------------------ TargetingController
    validTargets(uid, skillId) {
      const b = this.battle, sk = SKILLS[skillId];
      if (!sk) return [];
      if (sk.kind === 'attack') return b.alive('enemy').map(u => u.id);
      if (sk.kind === 'support' || sk.kind === 'protect') return b.alive('ally').filter(u => u.id !== uid).map(u => u.id);
      return []; // defesa: sem alvo
    }
    needsTarget(skillId) { return SKILLS[skillId].kind !== 'defense'; }
    // habilidade planejada deste personagem (parceiro de combinação mostra a combinação)
    _plannedSkill(uid) {
      const c = this.cb.choices()[uid];
      if (!c) return null;
      return c.comboWith ? (this.cb.choices()[c.comboWith] || {}).skillId : c.skillId;
    }
    _activeSkill() { return this.drag ? this.drag.skillId : this.sel && this.sel.skillId; }
    _activeUid() { return this.drag ? this.drag.uid : this.sel && this.sel.uid; }
    _applyHighlights() {
      const uid = this._activeUid(), sid = this._activeSkill();
      if (this.enabled && uid && sid && this.needsTarget(sid)) {
        const valid = new Set(this.validTargets(uid, sid));
        this.p.highlight = valid;
        this.p.dimIds = new Set(Object.keys(this.p.vis).filter(id => !valid.has(id) && id !== uid));
        const pr = SKILLS[sid].pressure || 0;
        this.p.breakHint = new Set([...valid].filter(id => { const t = this.battle.unit(id); return t.side === 'enemy' && pr && !t.stable && !t.broken && t.post <= pr; }));
      } else {
        this.p.highlight = this.enabled && uid ? new Set([uid]) : null;
        this.p.dimIds = null;
        this.p.breakHint = null;
      }
    }

    // ------------------------------------------------------------ AbilityArcSelector (carrossel em arco)
    // Um trecho de uma roda maior, com o eixo no personagem: o arco visível fica À FRENTE dele.
    // O item em foco fica no centro (maior). Roda do mouse / setas giram; Enter escolhe; clique em qualquer item.
    _menuIds(u) { return [...u.def.skills.filter(id => SKILLS[id].kind === 'attack'), ...u.def.skills.filter(id => SKILLS[id].kind !== 'attack'), ...this.battle.combosFor(u.id)]; }
    _layoutMenu() {
      this.items = []; this.arc = null;
      if (!this.enabled || !this.sel) return;
      const b = this.battle, u = b.unit(this.sel.uid), v = this.p.vis[this.sel.uid];
      if (!u || u.hp <= 0) { this.sel = null; return; }
      const k = this.p.pxPerWorld;
      const cw = this.p.canvas.clientWidth, ch = this.p.canvas.clientHeight;
      let f = v.face || 1;
      const sx = this.p.toScreen(v.x, 0).x;
      if (f > 0 && sx + 260 > cw) f = -1; else if (f < 0 && sx - 260 < 0) f = 1;
      const ids = this._menuIds(u);
      const step = 30, R = 150;
      if (this.sel.focus == null) this.sel.focus = Math.min(1, ids.length - 1);
      this.sel.focus = clamp(this.sel.focus, 0, ids.length - 1);
      // animação: entra girando e deslizando para baixo, e se acomoda (leve passada do ponto)
      const t = clamp((this.p.time - this.sel.openAt) / 340, 0, 1);
      const back = t => { const c = 1.6; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); };
      const e = back(t);
      const now = this.p.time, dt = Math.min(50, now - (this.sel.lastT || now)); this.sel.lastT = now;
      const goal = this.sel.focus * step;
      this.sel.rot = this.sel.rot == null ? goal : lerp(this.sel.rot, goal, 1 - Math.exp(-dt * 0.018));
      const spin = (1 - e) * -70, slide = (1 - e) * -60;
      let C = { x: v.x, y: v.y - 92 + slide / k };
      // mantém o arco dentro da tela (desloca na vertical)
      const sy = this.p.toScreen(0, C.y).y;
      if (sy - R * 0.9 < 30) C.y += (30 - (sy - R * 0.9)) / k; else if (sy + R * 0.9 > ch - 30) C.y -= (sy + R * 0.9 - (ch - 30)) / k;
      this.arc = { C, f, R: R / k, k, open: clamp(t * 1.4, 0, 1), spin };
      ids.forEach((id, i) => {
        const sk = SKILLS[id];
        const angDeg = i * step - this.sel.rot + spin;               // 0 = à frente, horizontal
        if (Math.abs(angDeg) > 80) return;                           // fora do trecho visível da roda
        const a = angDeg * Math.PI / 180, focusAmt = clamp(1 - Math.abs(angDeg) / step, 0, 1);
        const ownerId = sk.combo ? sk.members[0] : u.id;
        this.items.push({ skillId: id, idx: i, kind: styleOf(sk), main: sk.kind === 'attack' && !sk.combo, focus: focusAmt, ang: a,
          x: C.x + f * Math.cos(a) * R / k, y: C.y + Math.sin(a) * R / k, r: (20 + 7 * focusAmt) / k,
          disabled: !b.skillReady(b.unit(ownerId), id) || (this.needsTarget(id) && !this.validTargets(u.id, id).length),
          cd: b.unit(ownerId).cooldowns[id], open: this.arc.open, fade: clamp(1 - (Math.abs(angDeg) - 50) / 30, 0.15, 1) });
      });
      if (this.cb.choices()[u.id]) this.items.push({ cancel: true, skillId: null, kind: 'cancel', x: C.x - f * 18 / k, y: C.y - 70 / k, r: 13 / k, open: this.arc.open, fade: 1 });
    }
    _rotateMenu(d) {
      if (!this.sel) return;
      const u = this.battle.unit(this.sel.uid), n = this._menuIds(u).length;
      const nf = clamp(this.sel.focus + d, 0, n - 1);
      if (nf !== this.sel.focus) { this.sel.focus = nf; G.SFX && G.SFX.play('chainTick'); }
    }

    // ------------------------------------------------------------ InputController
    _bindInput(canvas) {
      const pos = e => { const r = canvas.getBoundingClientRect(); return { sx: e.clientX - r.left, sy: e.clientY - r.top }; };
      canvas.addEventListener('pointerdown', e => {
        if (!this.enabled || e.button === 2) return;
        const { sx, sy } = pos(e); this._move(sx, sy);
        canvas.setPointerCapture(e.pointerId);
        this.press = this._hitAt() ; this.press.sx = sx; this.press.sy = sy;
        if (this.press.kind === 'ally' && this.battle.unit(this.press.id).broken) { G.SFX && G.SFX.play('uiCancel'); this.press = null; return; }
        if (this.press.kind === 'ally' && !(this.sel && this.sel.skillId && this.validTargets(this.sel.uid, this.sel.skillId).includes(this.press.id))) {
          if (!this.sel || this.sel.uid !== this.press.id || this.sel.skillId) this._select(this.press.id);
        }
      });
      canvas.addEventListener('pointermove', e => {
        const { sx, sy } = pos(e); this._move(sx, sy);
        if (!this.enabled) return;
        const pr = this.press;
        if (pr && !this.drag && Math.hypot(sx - pr.sx, sy - pr.sy) > DRAG_PX) {
          // vira arrasto: a partir do personagem ou de um círculo de habilidade
          if (pr.kind === 'ally' && this.sel && this.sel.uid === pr.id) this.drag = { uid: pr.id, skillId: null };
          else if (pr.kind === 'item' && !pr.item.cancel && !pr.item.disabled) this.drag = { uid: this.sel.uid, skillId: pr.item.skillId };
        }
        if (this.drag) {
          // a primeira habilidade tocada é a escolhida; passar rapidamente por outros
          // círculos a caminho do alvo não troca. Para trocar, pare ~0,25 s sobre outra.
          const it = this._itemAt();
          const ok = it && !it.cancel && !it.disabled;
          if (!this.drag.skillId) { if (ok) { this.drag.skillId = it.skillId; G.SFX && G.SFX.play('uiSkill'); } }
          else if (ok && it.skillId !== this.drag.skillId) {
            if (this.drag.dwell !== it.skillId) { this.drag.dwell = it.skillId; this.drag.dwellAt = this.p.time; }
            else if (this.p.time - this.drag.dwellAt > 250) this.drag.skillId = it.skillId;
          } else this.drag.dwell = null;
        }
        this._hoverUpdate();
        this._applyHighlights();
      });
      canvas.addEventListener('pointerup', e => {
        if (!this.enabled) { this.press = null; return; }
        const { sx, sy } = pos(e); this._move(sx, sy);
        const pr = this.press; this.press = null;
        if (this.drag) { this._endDrag(); return; }
        if (pr) this._click(pr);
        this._applyHighlights();
      });
      canvas.addEventListener('contextmenu', e => {
        e.preventDefault();
        if (!this.enabled) return;
        const { sx, sy } = pos(e); this._move(sx, sy);
        const h = this._hitAt();
        if (h.kind === 'ally' && this.cb.choices()[h.id]) { this.cb.cancel(h.id); this._retract(h.id); }
        this._cancelSelection();
      });
      canvas.addEventListener('wheel', e => { if (!this.enabled || !this.sel || this.sel.skillId) return; e.preventDefault(); this._rotateMenu(e.deltaY > 0 ? 1 : -1); }, { passive: false });
      window.addEventListener('keydown', e => {
        if (this.enabled && this.sel && !this.sel.skillId && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) { e.preventDefault(); this._rotateMenu(e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : -1); return; }
        if (this.enabled && this.sel && !this.sel.skillId && e.key === 'Enter') {
          e.preventDefault(); e.stopImmediatePropagation();
          this._layoutMenu(); const it = this.items.find(x => x.idx === this.sel.focus);
          if (it) this._click({ kind: 'item', item: it });
          return;
        }
        if (e.key !== 'Escape' || !this.enabled) return;
        if (this.drag) { this._retractDrag(); this.drag = null; }
        else if (this.sel && this.sel.skillId) this.sel.skillId = null;
        else this._cancelSelection();
        this._applyHighlights();
      });
      canvas.addEventListener('pointerleave', () => { this.hover = { unit: null, item: null, badge: null }; });
    }
    _move(sx, sy) { const w = this.p.toWorld(sx, sy); this.mouse = { x: w.x, y: w.y, sx, sy }; }
    _itemAt() {
      this._layoutMenu();
      return this.items.find(it => Math.hypot(this.mouse.x - it.x, this.mouse.y - it.y) <= it.r * 1.25) || null;
    }
    _badgeAt() { return this.badges.find(b => Math.hypot(this.mouse.x - b.x, this.mouse.y - b.y) <= b.r * 1.3) || null; }
    _hitAt() {
      const it = this._itemAt();
      if (it) return { kind: 'item', item: it };
      const bd = this._badgeAt();
      if (bd) return { kind: 'badge', badge: bd };
      const id = this.p.pick(this.mouse.sx, this.mouse.sy);
      if (id) { const u = this.battle.unit(id); return { kind: u.side === 'ally' ? 'ally' : 'enemy', id }; }
      return { kind: 'empty' };
    }
    _hoverUpdate() {
      const h = this._hitAt();
      // durante a mira, o alvo é sempre o personagem sob o cursor
      const unit = h.id || (this._activeSkill() ? this.p.pick(this.mouse.sx, this.mouse.sy) : null);
      this.hover = { unit, item: h.item || null, badge: h.kind === 'badge' ? h.badge : null, intent: null };
      // EnemyIntentTooltip: mouse sobre a própria corrente curva de uma intenção inimiga
      if (h.kind === 'empty' && this.showIntents && this.routes) {
        const tol = 14 / this.p.pxPerWorld; let best = null, bd = tol;
        for (const it of this.battle.intents) {
          const cv = this.routes[it.id]; if (!cv) continue;
          for (let i = 0; i <= 32; i++) { const q = this._at(cv, i / 32), d = Math.hypot(q.x - this.mouse.x, q.y - this.mouse.y); if (d < bd) { bd = d; best = { id: it.id, x: q.x, y: q.y }; } }
        }
        this.hover.intent = best;
      }
      const c = this.p.canvas;
      c.style.cursor = this.drag ? 'grabbing' : (h.kind === 'empty' ? (this.hover.intent ? 'help' : 'default') : 'pointer');
    }
    _select(uid) {
      G.SFX && G.SFX.play('chainOpen'); // som de corrente ao abrir o seletor
      this.sel = { uid, skillId: null, openAt: this.p.time, focus: null, rot: null };
      this._applyHighlights();
    }
    _cancelSelection() { this.sel = null; this.drag = null; this._applyHighlights(); }

    _click(pr) {
      const sel = this.sel;
      if (pr.kind === 'item') {
        const it = pr.item;
        if (it.cancel) { this.cb.cancel(sel.uid); this._retract(sel.uid); this._cancelSelection(); return; }
        if (it.disabled) return;
        if (!this.needsTarget(it.skillId)) { this._commit(sel.uid, it.skillId, sel.uid); return; }
        sel.skillId = it.skillId; // modo clique: agora clique no alvo
        G.SFX && G.SFX.play('uiSkill');
        return;
      }
      if (pr.kind === 'badge' && sel && sel.skillId) { const id = this.p.pick(this.mouse.sx, this.mouse.sy); if (id) pr = { kind: this.battle.unit(id).side === 'ally' ? 'ally' : 'enemy', id }; }
      if ((pr.kind === 'enemy' || pr.kind === 'ally') && sel && sel.skillId) {
        if (this.validTargets(sel.uid, sel.skillId).includes(pr.id)) { this._commit(sel.uid, sel.skillId, pr.id); return; }
        if (pr.kind === 'ally') { this._select(pr.id); return; }
        return; // alvo inválido: ignora (fica desabilitado visualmente)
      }
      if (pr.kind === 'badge') { if (pr.badge.toggle) this.cb.toggleIntercept(pr.badge.uid); return; }
      if (pr.kind === 'ally') return; // seleção já feita no pointerdown
      if (pr.kind === 'empty') this._cancelSelection();
    }
    _endDrag() {
      const d = this.drag; this.drag = null;
      const h = this._hitAt();
      if (d.skillId) {
        if (!this.needsTarget(d.skillId)) {
          // habilidade sem alvo: confirma soltando no próprio círculo
          if (h.kind === 'item' && h.item.skillId === d.skillId) { this._commit(d.uid, d.skillId, d.uid); return; }
        } else {
          // o alvo é o personagem sob o cursor, mesmo que haja um selo/ícone por cima
          const id = this.p.pick(this.mouse.sx, this.mouse.sy);
          if (id && this.validTargets(d.uid, d.skillId).includes(id)) { this._commit(d.uid, d.skillId, id); return; }
        }
      }
      // soltou em lugar inválido: a corrente se recolhe e nada muda
      this._retractDrag(d);
      this._applyHighlights();
    }
    _commit(uid, skillId, targetId) {
      this.hover.item = null;
      G.SFX && G.SFX.play('uiConnect'); G.SFX && G.SFX.play('chainLock', { vol: 0.6 });
      this.cb.commit(uid, skillId, targetId);
      this.connectAt[uid] = this.p.time;
      this.sel = null;
      this._applyHighlights();
      const v = this.p.vis[targetId];
      if (v && targetId !== uid) this.p.sparks(v.x, v.y - 80, KIND_STYLE[SKILLS[skillId].kind].color, 8, 0.2, -0.0003);
    }
    _retract(uid) {
      const v = this.p.vis[uid];
      if (v) this.retracts.push({ x0: v.x, y0: v.y - 80, x1: v.x + v.face * 60, y1: v.y - 120, kind: 'attack', start: this.p.time });
    }
    _retractDrag(d = this.drag) {
      if (!d) return;
      G.SFX && G.SFX.play('uiCancel');
      const v = this.p.vis[d.uid];
      this.retracts.push({ x0: v.x, y0: v.y - 80, x1: this.mouse.x, y1: this.mouse.y, kind: d.skillId ? SKILLS[d.skillId].kind : 'attack', start: this.p.time });
    }

    // ------------------------------------------------------------ ClashPreview
    // Linhas da prévia para (uid, skill, alvo), usando as regras reais.
    previewLines(uid, skillId, targetId, intercept) {
      const key = [uid, skillId, targetId, intercept, JSON.stringify(this.cb.choices())].join('|');
      if (this.previewCache.key === key) return this.previewCache.lines;
      const b = this.battle, sk = SKILLS[skillId];
      const choices = JSON.parse(JSON.stringify(this.cb.choices()));
      if (sk.combo) {
        // combinação: registrada no líder; os parceiros ficam reservados
        for (const m of sk.members) { if (choices[m] && choices[m].comboWith) delete choices[m]; }
        uid = sk.members[0];
        sk.members.slice(1).forEach(m => { choices[m] = { comboWith: uid }; });
      }
      choices[uid] = { skillId, targetId, intercept: intercept == null ? true : intercept };
      let plan = b.buildPlan(choices);
      const mine = plan.actions.find(a => a.actorId === uid);
      if (intercept == null && mine && !(mine.interceptInfo && mine.interceptInfo.valid)) { choices[uid].intercept = false; plan = b.buildPlan(choices); }
      const prev = b.previewPlan(plan);
      const me = plan.actions.find(a => a.actorId === uid);
      const lines = [];
      const ev = me && prev.find(e => e.type === 'clash' && (e.a.id === me.id || e.b.id === me.id));
      if (ev && sk.combo) lines.push({ t: `Custa a ação de ${sk.members.map(m => b.unit(m).name).join(' e ')}`, c: KIND_STYLE.combo.color });
      if (ev) {
        const meFirst = ev.a.id === me.id, other = meFirst ? ev.b : ev.a;
        const sMe = meFirst ? ev.sa : ev.sb, sOt = meFirst ? ev.sb : ev.sa;
        const p = meFirst ? ev.odds.win : ev.odds.lose;
        const myOdds = meFirst ? ev.odds : { win: ev.odds.lose, tie: ev.odds.tie, lose: ev.odds.win };
        const cat = b.category(p, myOdds);
        const cad = sd => { const [lo, hi] = b.range(sd); return `${sd.base} · ${sd.beats} batida${sd.beats > 1 ? 's' : ''} (+0–${sd.imp}) → ${lo}–${hi}`; };
        lines.push({ t: ev.link.type === 'intercept' ? `⚔ INTERCEPTAÇÃO (protege ${b.unit(this.battle.intents.find(i => i.id === other.id).targetId).name})` : '⚔ CLASH', c: '#ffe9b0' });
        const who = act => [act.actorId, ...(act.partners || [])].map(id => b.unit(id).name).join(' + ');
        lines.push({ t: `${who(me)} — ${sk.name}:  ${cad(sMe)}`, c: '#9fd8ff' });
        lines.push({ t: `${who(other)} — ${SKILLS[other.skillId].name}:  ${cad(sOt)}`, c: '#ff9a8a' });
        lines.push({ t: `Previsão: ${CAT_NAME[cat]}  (vence ${Math.round(myOdds.win * 100)}% · empata ${Math.round(myOdds.tie * 100)}% · perde ${Math.round(myOdds.lose * 100)}%)`, c: CAT_COLOR[cat] });
        { const el = this.elemLine(b.unit(me.actorId), b.unit(other.actorId)); if (el) lines.push(el); }
        // Postura: o que acontece com o alvo SE vencer (e o risco para mim se perder)
        const foeU = b.unit(other.actorId), meU = b.unit(me.actorId);
        const myP = sk.pressure || 0, theirP = SKILLS[other.skillId].pressure || 0;
        lines.push({ t: `Se vencer: −${myP} Postura em ${foeU.name} (${foeU.post}/${foeU.postMax})` + (!foeU.stable && foeU.post <= myP ? '  → possível QUEBRA' : ''), c: '#d9b85c' });
        lines.push({ t: `Se perder: −${theirP} na sua Postura (${meU.post}/${meU.postMax})` + (!meU.stable && meU.post <= theirP ? '  → risco de QUEBRA' : ''), c: '#b89a70' });
      } else if (sk.kind === 'attack') {
        const info = me && me.interceptInfo;
        lines.push({ t: `${sk.name} → ${b.unit(targetId).name}`, c: '#ffe9b0' });
        if (info && !info.valid) lines.push({ t: `Lento demais para interceptar (Vel ${info.mySpeed}${info.reach ? '+' + info.reach : ''} < ${info.enemySpeed})`, c: '#ff9a8a' });
        else if (info && !choices[uid].intercept) lines.push({ t: 'Interceptação desligada', c: '#c9b' });
        const it = b.intents.find(i => i.actorId === targetId);
        if (it && SKILLS[it.skillId].kind === 'defense') lines.push({ t: `Alvo vai se defender (${SKILLS[it.skillId].name})`, c: '#9fd0ff' });
        { const el = this.elemLine(b.unit(uid), b.unit(targetId)); if (el) lines.push(el); }
        lines.push({ t: `Sem Clash · dano ${Math.round(sk.dmg * b.elementMult(b.unit(uid), b.unit(targetId)))}${sk.hits ? ` em ${sk.hits.length} golpes` : ''} se não houver defesa`, c: '#e8dccb' });
        if (sk.combo) lines.push({ t: `Custa a ação de ${sk.members.map(m => b.unit(m).name).join(' e ')}`, c: KIND_STYLE.combo.color });
      } else {
        lines.push({ t: `${sk.name} → ${b.unit(targetId).name}`, c: '#ffe9b0' });
        lines.push({ t: sk.desc, c: '#e8dccb' });
      }
      this.previewCache = { key, lines };
      return lines;
    }

    // Linhas do tooltip de uma intenção inimiga (ataque, números, elemento, combo)
    intentLines(it) {
      const b = this.battle, sk = SKILLS[it.skillId], A = b.unit(it.actorId), T = b.unit(it.targetId);
      const who = [it.actorId, ...(it.partners || [])].map(id => b.unit(id).name).join(' + ');
      const type = sk.combo ? 'Ataque combinado' : sk.tags.includes('magic') ? 'Magia' : sk.tags.includes('ranged') ? 'À distância' : 'Corpo a corpo';
      const E = G.ELEMENTS[A.def.element], rel = b.elementRel(A, T);
      const lines = [{ t: `${who} — ${sk.name}${sk.combo ? '  ⚔ COMBO' : ''}`, c: '#ff9a8a' },
        { t: `${type} · alvo: ${T.name}`, c: '#cbbfb0' },
        { t: `Força ${sk.force} · ${sk.beats || 1} batida(s) +0–${sk.impulse != null ? sk.impulse : 3} · Dano ${sk.dmg} · Pressão ${sk.pressure || 0}`, c: '#e8dccb' },
        { t: `Elemento: ${E.name}` + (rel > 0 ? '  ▲ vantagem sobre ' + T.name + ' (+20% dano)' : rel < 0 ? '  ▼ desvantagem contra ' + T.name + ' (−20% dano)' : ''), c: rel > 0 ? '#ff9a8a' : rel < 0 ? '#9fe0a0' : E.color }];
      return lines;
    }
    // Tag de elemento (vantagem/desvantagem) de um ataque
    elemLine(att, def) {
      const r = this.battle.elementRel(att, def);
      return r > 0 ? { t: `▲ Vantagem elemental (+20% de dano)`, c: '#7fe0a0' } : r < 0 ? { t: `▼ Desvantagem elemental (−20% de dano)`, c: '#ff9a8a' } : null;
    }

    // ============================================================ ClashPreviewUI (prévia rápida)
    // Só o essencial: meu golpe (azul) × golpe inimigo (vermelho) com a faixa de força final,
    // e a previsão calculada pelas probabilidades reais. O detalhe completo fica na ficha / tooltip da habilidade.
    quickPreview(uid, skillId, targetId, intercept) {
      const key = ['q', uid, skillId, targetId, intercept, JSON.stringify(this.cb.choices())].join('|');
      if (this._qp && this._qp.key === key) return this._qp.data;          // não recalcula a cada quadro
      const b = this.battle, sk = SKILLS[skillId];
      const choices = JSON.parse(JSON.stringify(this.cb.choices()));
      if (sk.combo) { for (const m of sk.members) { if (choices[m] && choices[m].comboWith) delete choices[m]; } uid = sk.members[0]; sk.members.slice(1).forEach(m => { choices[m] = { comboWith: uid }; }); }
      choices[uid] = { skillId, targetId, intercept: intercept == null ? true : intercept };
      let plan = b.buildPlan(choices);
      let me = plan.actions.find(a => a.actorId === uid);
      if (intercept == null && me && !(me.interceptInfo && me.interceptInfo.valid)) { choices[uid].intercept = false; plan = b.buildPlan(choices); me = plan.actions.find(a => a.actorId === uid); }
      const prev = b.previewPlan(plan);
      const ev = me && prev.find(e => e.type === 'clash' && (e.a.id === me.id || e.b.id === me.id));
      const T = b.unit(targetId), U = b.unit(uid);
      const side = (sd, s) => { const [lo, hi] = b.range(sd); return { icon: s.icon, name: s.name, lo, hi }; };
      let data;
      if (ev) {
        const meFirst = ev.a.id === me.id, other = meFirst ? ev.b : ev.a;
        const odds = meFirst ? ev.odds : { win: ev.odds.lose, tie: ev.odds.tie, lose: ev.odds.win };
        const foe = b.unit(other.actorId);
        data = { type: ev.link.type === 'intercept' ? 'intercept' : 'clash', me: side(meFirst ? ev.sa : ev.sb, sk), foe: side(meFirst ? ev.sb : ev.sa, SKILLS[other.skillId]),
          cat: b.category(odds.win, odds), odds,
          brk: !foe.stable && !foe.broken && foe.post <= (sk.pressure || 0), elem: b.elementRel(U, foe) };
      } else if (sk.kind === 'attack') {
        const info = me && me.interceptInfo;
        data = info && !info.valid && intercept !== false
          ? { type: 'invalid', me: { icon: sk.icon, name: sk.name }, msg: 'Interceptação indisponível', sub: `vel. ${info.mySpeed}${info.reach ? '+' + info.reach : ''} < ${info.enemySpeed}` }
          : { type: 'free', me: { icon: sk.icon, name: sk.name }, msg: 'Sem confronto', sub: `dano ${Math.round(sk.dmg * b.elementMult(U, T))}`, elem: b.elementRel(U, T) };
      } else data = { type: 'free', me: { icon: sk.icon, name: sk.name }, msg: sk.kind === 'support' ? 'Suporte' : 'Proteção', sub: T.name };
      this._qp = { key, data, t: this.p.time };
      return data;
    }
    _drawCard(ctx, x, y, d) {
      const k = this.p.pxPerWorld, u = 1 / k;
      const CAT_ICON = { favorable: 'up', even: 'clash', unfavorable: 'warn', certain: 'check', doomed: 'skull' };
      const intro = clamp((this.p.time - (this._qp ? this._qp.t : 0)) / 120, 0, 1);
      const w = 236 * u, h = (d.type === 'clash' || d.type === 'intercept' ? 112 : 58) * u;
      const tl = this.p.toWorld(8, 8), br = this.p.toWorld(this.p.canvas.clientWidth - 8, this.p.canvas.clientHeight - 8);
      let bx = clamp(x - w / 2, tl.x, br.x - w), by = clamp(y - h - 16 * u, tl.y, br.y - h);
      ctx.save(); ctx.globalAlpha = intro; ctx.translate(bx + w / 2, by + h / 2); ctx.scale(0.92 + 0.08 * intro, 0.92 + 0.08 * intro); ctx.translate(-w / 2, -h / 2);
      ctx.fillStyle = 'rgba(12,8,16,0.94)'; ctx.strokeStyle = 'rgba(216,180,90,0.55)'; ctx.lineWidth = 1.2 * u;
      ctx.beginPath(); ctx.roundRect(0, 0, w, h, 8 * u); ctx.fill(); ctx.stroke();
      const row = (yy, s, team) => {
        const col = team === 'ally' ? '#4fc8ff' : '#ff6a3c';
        this._disk(ctx, 18 * u, yy, 11 * u, '#140c14', col, s.icon, false);
        ctx.font = `700 ${12.5 * u}px "Trebuchet MS", sans-serif`; ctx.textAlign = 'left'; ctx.fillStyle = '#efe6d8';
        ctx.fillText(s.name, 36 * u, yy + 4 * u);
        if (s.lo != null) { ctx.font = `900 ${16 * u}px "Trebuchet MS", sans-serif`; ctx.textAlign = 'right'; ctx.fillStyle = col; ctx.fillText(s.lo === s.hi ? `${s.lo}` : `${s.lo}–${s.hi}`, w - 10 * u, yy + 5 * u); }
      };
      if (d.type === 'clash' || d.type === 'intercept') {
        row(20 * u, d.me, 'ally');
        ctx.font = `800 ${9.5 * u}px "Trebuchet MS", sans-serif`; ctx.textAlign = 'center'; ctx.fillStyle = '#9a8c99';
        ctx.fillText(d.type === 'intercept' ? 'VS · INTERCEPTA' : 'VS', w / 2, 41 * u);
        row(60 * u, d.foe, 'enemy');
        // previsão: ícone + rótulo (não depende só da cor)
        const col = CAT_COLOR[d.cat];
        ctx.fillStyle = 'rgba(255,255,255,0.05)'; ctx.fillRect(6 * u, 78 * u, w - 12 * u, 28 * u);
        drawIcon(ctx, CAT_ICON[d.cat], 22 * u, 92 * u, 9 * u, col);
        ctx.font = `900 ${13 * u}px "Trebuchet MS", sans-serif`; ctx.textAlign = 'left'; ctx.fillStyle = col;
        ctx.fillText(CAT_NAME[d.cat].toUpperCase(), 38 * u, 97 * u);
        // exceções discretas: possível Quebra e elemento
        let ix = w - 14 * u;
        ctx.font = `900 ${13 * u}px "Trebuchet MS", sans-serif`; ctx.textAlign = 'center';
        if (d.elem) { ctx.fillStyle = d.elem > 0 ? '#7fe0a0' : '#ff9a8a'; ctx.fillText(d.elem > 0 ? '▲' : '▼', ix, 97 * u); ix -= 18 * u; }
        if (d.brk) { ctx.fillStyle = '#ffd36a'; ctx.fillText('⚡', ix, 97 * u); }
      } else {
        row(18 * u, d.me, 'ally');
        ctx.font = `800 ${11 * u}px "Trebuchet MS", sans-serif`; ctx.textAlign = 'left';
        ctx.fillStyle = d.type === 'invalid' ? '#ff9a8a' : '#cbbfb0'; ctx.fillText(d.msg, 36 * u, 44 * u);
        ctx.textAlign = 'right'; ctx.fillStyle = '#9a8c99'; ctx.fillText(d.sub || '', w - 10 * u, 44 * u);
        if (d.elem) { ctx.textAlign = 'left'; ctx.fillStyle = d.elem > 0 ? '#7fe0a0' : '#ff9a8a'; ctx.fillText(d.elem > 0 ? '▲' : '▼', 18 * u, 44 * u); }
      }
      ctx.restore();
    }

    // ============================================================ ChainRenderer
    _chest(v) { return { x: v.x, y: v.y - 80 + (Math.abs(v.tilt) > 1 ? 60 : 0) }; }
    _head(v) { return { x: v.x, y: v.y - 138 + (Math.abs(v.tilt) > 1 ? 100 : 0) }; }
    // Arco suspenso: sobe a partir da origem, percorre o alto da arena e desce no alvo.
    _arc(p0, p1, height, seed = 0) {
      const top = this._clampTop(Math.min(p0.y, p1.y) - height);
      const sway = Math.sin(this.p.time * 0.0018 + seed) * 3;
      const dx = p1.x - p0.x;
      return { p0, p1, c1: { x: p0.x + dx * 0.06, y: top + sway }, c2: { x: p1.x - dx * 0.06, y: top - sway } };
    }
    _clampTop(y) { const wt = this.p.toWorld(0, 30).y; return Math.max(y, wt); }
    _at(cv, t) {
      const { p0, c1, c2, p1 } = cv, u = 1 - t;
      const x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p1.x;
      const y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p1.y;
      const dx = 3 * u * u * (c1.x - p0.x) + 6 * u * t * (c2.x - c1.x) + 3 * t * t * (p1.x - c2.x);
      const dy = 3 * u * u * (c1.y - p0.y) + 6 * u * t * (c2.y - c1.y) + 3 * t * t * (p1.y - c2.y);
      return { x, y, a: Math.atan2(dy, dx) };
    }
    _len(cv) { let L = 0, q = this._at(cv, 0); for (let i = 1; i <= 12; i++) { const r = this._at(cv, i / 12); L += Math.hypot(r.x - q.x, r.y - q.y); q = r; } return L; }
    // Faixas de altura: o arco mais curto fica embaixo; quem "abraça" outro sobe uma faixa.
    // Pontas que compartilham origem/destino ganham pequenos deslocamentos horizontais.
    _routesFor(conns) {
      const vis = this.p.vis;
      const fromN = {}, toN = {};
      for (const c of conns) { (fromN[c.from] = fromN[c.from] || []).push(c); (toN[c.to] = toN[c.to] || []).push(c); }
      for (const c of conns) {
        const A = vis[c.from], T = vis[c.to];
        const fi = fromN[c.from].indexOf(c), fn = fromN[c.from].length, ti = toN[c.to].indexOf(c), tn = toN[c.to].length;
        c.p0 = this._head(A); c.p0.x += (fi - (fn - 1) / 2) * 16;
        c.p1 = this._head(T); c.p1.x += (ti - (tn - 1) / 2) * 18;
        c.lo = Math.min(c.p0.x, c.p1.x); c.hi = Math.max(c.p0.x, c.p1.x); c.span = c.hi - c.lo;
      }
      const placed = [];
      for (const c of conns.slice().sort((a, b) => a.span - b.span)) {
        c.lane = 0;
        for (const p of placed) if (p.hi > c.lo - 30 && p.lo < c.hi + 30) c.lane = Math.max(c.lane, p.lane + 1);
        placed.push(c);
      }
      for (const c of conns) c.cv = this._arc(c.p0, c.p1, 90 + c.span * 0.16 + c.lane * 46 - (c.tension || 0) * 18, c.seed || 0);
      return conns;
    }
    drawChain(ctx, cv, kind, alpha, opts = {}) {
      const st = KIND_STYLE[kind] || KIND_STYLE.attack;
      const len = this._len(cv);
      const tEnd = opts.tEnd == null ? 1 : opts.tEnd;
      const n = Math.max(4, Math.floor(len * tEnd / 13));
      ctx.save();
      ctx.globalAlpha = alpha;
      if (opts.glow) { ctx.shadowColor = st.color; ctx.shadowBlur = 10; }
      for (let i = 0; i <= n; i++) {
        const q = this._at(cv, (i / n) * tEnd);
        ctx.save(); ctx.translate(q.x, q.y); ctx.rotate(q.a);
        const bright = opts.tension ? 1 + opts.tension * 0.6 : 1;
        if (i % 2 === 0) {
          ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(8,4,10,0.6)';
          this._link(ctx, st.link); ctx.stroke();
          ctx.lineWidth = 2 * bright; ctx.strokeStyle = st.color;
          this._link(ctx, st.link); ctx.stroke();
        } else {
          ctx.lineWidth = 3.5; ctx.strokeStyle = 'rgba(8,4,10,0.6)';
          ctx.beginPath(); ctx.moveTo(-4, 0); ctx.lineTo(4, 0); ctx.stroke();
          ctx.lineWidth = 1.8; ctx.strokeStyle = st.color;
          ctx.beginPath(); ctx.moveTo(-4, 0); ctx.lineTo(4, 0); ctx.stroke();
        }
        ctx.restore();
      }
      if (tEnd >= 0.999 && !opts.noEnd) {
        const q = this._at(cv, 1);
        ctx.translate(q.x, q.y); ctx.rotate(q.a);
        ctx.fillStyle = st.color; ctx.strokeStyle = 'rgba(8,4,10,0.7)'; ctx.lineWidth = 1.5;
        ctx.beginPath();
        if (kind === 'attack' || kind === 'combo') { ctx.moveTo(6, 0); ctx.lineTo(-7, -6); ctx.lineTo(-4, 0); ctx.lineTo(-7, 6); }      // ponta de lança
        else if (kind === 'support') { ctx.moveTo(6, 0); ctx.lineTo(0, -6); ctx.lineTo(-6, 0); ctx.lineTo(0, 6); } // losango
        else { ctx.moveTo(-6, -6); ctx.lineTo(6, -6); ctx.lineTo(6, 2); ctx.lineTo(0, 8); ctx.lineTo(-6, 2); }    // escudo
        ctx.closePath(); ctx.fill(); ctx.stroke();
      }
      ctx.restore();
    }
    _link(ctx, type) {
      ctx.beginPath();
      if (type === 'oval') ctx.ellipse(0, 0, 6.5, 3.4, 0, 0, 7);
      else if (type === 'double') { ctx.ellipse(0, -2, 6.5, 2.6, 0, 0, 7); ctx.moveTo(6.5, 2.4); ctx.ellipse(0, 2.4, 6.5, 2.6, 0, 0, 7); }
      else if (type === 'round') ctx.arc(0, 0, 3.6, 0, 7);
      else ctx.rect(-5, -3.2, 10, 6.4);
    }

    // ------------------------------------------------------------ desenho (atrás dos personagens)
    drawUnder(ctx) {
      if (this.fade <= 0.01 || !this.p.vis) return;
      const b = this.battle;
      this.badges = [];
      const vis = this.p.vis;
      const focus = this.sel ? this.sel.uid : this.hover.unit;
      const plan = this.cb.plan(), choices = this.cb.choices();
      const rel = (a, t) => !focus || a === focus || t === focus;

      // rotas: intenções inimigas + ações aliadas compartilham as faixas de altura
      const conns = [];
      const membersOf = a => [a.actorId, ...(a.partners || [])];
      if (this.showIntents) for (const it of b.intents) {
        const A = vis[it.actorId], sk = SKILLS[it.skillId];
        if (!A || A.dead || sk.kind !== 'attack') continue;
        const l = plan && plan.links[it.id];
        if (l && l.type === 'direct') continue; // vira o Clash da corrente aliada
        conns.push({ key: it.id, from: it.actorId, to: it.targetId, enemy: true, it, seed: A.phase, members: membersOf(it) });
      }
      const acts = plan ? plan.actions.filter(a => a.side === 'ally' && SKILLS[a.skillId].kind !== 'defense') : [];
      for (const a of acts) {
        if (this.drag && membersOf(a).includes(this.drag.uid)) continue;
        const since = this.p.time - (this.connectAt[a.actorId] || -1e9);
        conns.push({ key: a.id, from: a.actorId, to: a.targetId, a, seed: vis[a.actorId].phase, members: membersOf(a),
          tension: since < 350 ? Math.sin(Math.PI * since / 350) : 0 });
      }
      if (this.showIntents) for (const it of b.intents) {
        if (!it.partners || !vis[it.actorId] || vis[it.actorId].dead) continue;
        const on = !focus || [it.actorId, ...it.partners, it.targetId].includes(focus);
        this._tether(ctx, [it.actorId, ...it.partners].map(id => vis[id]), '#ff7a5a', this.fade * (on ? 0.8 : 0.25), true);
      }
      this.routes = {};
      for (const c of this._routesFor(conns)) {
        this.routes[c.key] = c.cv;
        const hi = this.hover.intent && this.hover.intent.id === c.key;
        const on = this.hover.intent ? hi : (!focus || c.members.includes(focus) || c.to === focus);
        if (c.enemy) {
          // intenções: tracejado fino e semitransparente (nunca confundir com corrente aliada)
          const cv = c.cv;
          ctx.save();
          ctx.globalAlpha = this.fade * (hi ? 1 : on ? 0.6 : 0.16);
          ctx.strokeStyle = SKILLS[c.it.skillId].combo ? '#ff9a5a' : '#ff5a5a'; ctx.lineWidth = hi ? 3.5 : 2; ctx.setLineDash([7, 7]); ctx.lineDashOffset = -this.p.time * 0.04;
          ctx.beginPath(); ctx.moveTo(cv.p0.x, cv.p0.y); ctx.bezierCurveTo(cv.c1.x, cv.c1.y, cv.c2.x, cv.c2.y, cv.p1.x, cv.p1.y); ctx.stroke();
          ctx.setLineDash([]);
          // seta de direção: ponta perto do alvo + chevron que percorre devagar o arco (inimigo → alvo)
          const tip = this._at(cv, 0.985), col = SKILLS[c.it.skillId].combo ? '#ff9a5a' : '#ff5a5a';
          this._arrowHead(ctx, tip.x, tip.y, tip.a, 13, col);
          const tt = ((this.p.time * 0.00028 + c.seed * 0.1) % 1) * 0.8 + 0.1, ch = this._at(cv, tt);
          ctx.globalAlpha *= 0.8; this._arrowHead(ctx, ch.x, ch.y, ch.a, 8, col, true);
          ctx.restore();
          // inimigo (ou sua corrente) sob o cursor: destaca origem e alvo
          if (hi) { const A = vis[c.from]; ctx.save(); ctx.translate(A.x, A.y + 4); ctx.scale(1, 0.32); ctx.strokeStyle = 'rgba(255,150,120,0.9)'; ctx.lineWidth = 6; ctx.beginPath(); ctx.arc(0, 0, 60, 0, 7); ctx.stroke(); ctx.restore(); }
          if (this.hover.unit === c.from || hi) {
            const T = vis[c.to]; ctx.save(); ctx.translate(T.x, T.y + 4); ctx.scale(1, 0.32);
            ctx.strokeStyle = 'rgba(255,90,90,0.9)'; ctx.lineWidth = 8; ctx.beginPath(); ctx.arc(0, 0, 64, 0, 7); ctx.stroke(); ctx.restore();
          }
        } else {
          const sk = SKILLS[c.a.skillId];
          const editing = this.sel && c.members.includes(this.sel.uid);
          this.drawChain(ctx, c.cv, styleOf(sk), this.fade * (editing ? 1 : on ? 0.92 : 0.28), { tension: c.tension, glow: editing });
          c.a._cv = c.cv;
          if (sk.combo) this._tether(ctx, c.members.map(id => vis[id]), KIND_STYLE.combo.color, this.fade * (on ? 0.9 : 0.3), false);
        }
      }

      // corrente sendo arrastada / modo clique aguardando alvo
      const uid = this._activeUid(), sid = this._activeSkill();
      if (this.enabled && uid && (this.drag || sid)) {
        const A = vis[uid];
        const hoverValid = sid && this.hover.unit && this.validTargets(uid, sid).includes(this.hover.unit);
        const p1 = hoverValid ? this._chest(vis[this.hover.unit]) : { x: this.mouse.x, y: this.mouse.y };
        const kind = sid ? styleOf(SKILLS[sid]) : 'attack';
        let p0 = this._chest(A);
        // passa pelo círculo da habilidade escolhida e sobe num arco até o alvo
        const it = sid && this.items.find(x => x.skillId === sid);
        if (it) this.drawChain(ctx, this._arc(p0, { x: it.x, y: it.y }, 14, 0), kind, 0.9, { noEnd: true, glow: true });
        if (it) p0 = { x: it.x, y: it.y };
        const tgt = hoverValid ? this._head(vis[this.hover.unit]) : p1;
        if (!it || this.needsTarget(sid)) this.drawChain(ctx, this._arc(p0, tgt, 60 + Math.abs(tgt.x - p0.x) * 0.14, 1), kind, 0.97, { glow: true });
      }

      // correntes se recolhendo
      this.retracts = this.retracts.filter(r => this.p.time - r.start < 220);
      for (const r of this.retracts) {
        const q = 1 - (this.p.time - r.start) / 220;
        this.drawChain(ctx, this._arc({ x: r.x0, y: r.y0 }, { x: r.x1, y: r.y1 }, 30, 0), r.kind, 0.7 * q, { tEnd: Math.max(0.05, q), noEnd: true });
      }

      // destaque do alvo sob o cursor
      if (this.enabled && sid && this.hover.unit && this.validTargets(uid, sid).includes(this.hover.unit)) {
        const T = vis[this.hover.unit];
        ctx.save(); ctx.translate(T.x, T.y + 4); ctx.scale(1, 0.32);
        ctx.strokeStyle = KIND_STYLE[styleOf(SKILLS[sid])].color; ctx.lineWidth = 9; ctx.globalAlpha = 0.9;
        ctx.beginPath(); ctx.arc(0, 0, 62, 0, 7); ctx.stroke(); ctx.restore();
      }
    }

    _arrowHead(ctx, x, y, a, size, color, open) {
      ctx.save(); ctx.translate(x, y); ctx.rotate(a);
      ctx.fillStyle = color; ctx.strokeStyle = color; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.moveTo(size * 0.6, 0); ctx.lineTo(-size * 0.6, -size * 0.55); ctx.lineTo(-size * 0.3, 0); ctx.lineTo(-size * 0.6, size * 0.55); ctx.closePath();
      open ? ctx.stroke() : ctx.fill();
      ctx.restore();
    }
    // Ligação secundária discreta entre os membros de uma combinação
    _tether(ctx, vs, color, alpha, dashed) {
      vs = vs.filter(Boolean);
      for (let i = 1; i < vs.length; i++) {
        const a = this._chest(vs[0]), b2 = this._chest(vs[i]);
        const top = Math.min(a.y, b2.y) - 45;
        ctx.save(); ctx.globalAlpha = alpha; ctx.strokeStyle = color; ctx.lineWidth = 2.2;
        ctx.setLineDash(dashed ? [5, 5] : [2, 4]); ctx.lineDashOffset = -this.p.time * 0.03;
        ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.quadraticCurveTo((a.x + b2.x) / 2, top, b2.x, b2.y); ctx.stroke();
        ctx.setLineDash([]);
        drawIcon(ctx, 'combo', (a.x + b2.x) / 2, (a.y + b2.y) / 2 - 22, 7, color);
        ctx.restore();
      }
    }

    // ------------------------------------------------------------ desenho (na frente)
    drawOver(ctx) {
      if (this.fade <= 0.01 || !this.p.vis) return;
      const b = this.battle, vis = this.p.vis, k = this.p.pxPerWorld;
      const plan = this.cb.plan(), preview = this.cb.preview() || [], choices = this.cb.choices();
      const focus = this.sel ? this.sel.uid : this.hover.unit;
      ctx.save();
      ctx.globalAlpha = this.fade;

      // ícones das intenções inimigas
      if (this.showIntents) {
        for (const it of b.intents) {
          const A = vis[it.actorId], sk = SKILLS[it.skillId];
          if (!A || A.dead) continue;
          const on = !focus || it.actorId === focus || it.targetId === focus;
          let x, y;
          if (sk.kind !== 'attack') { x = A.x; y = A.y - 200; }
          else {
            const cv = this.routes && this.routes[it.id];
            if (!cv) continue;
            const q = this._at(cv, 0.5); x = q.x; y = q.y;
          }
          ctx.globalAlpha = this.fade * (on ? 0.95 : 0.35);
          this._disk(ctx, x, y, 12 / k, '#2a1216', sk.combo ? '#ff9a5a' : '#ff6a5a', sk.icon, false);
          this._tag(ctx, x + 15 / k, y + 4 / k, sk.combo ? `COMBO F${sk.force}` : `F${sk.force}`, '#ffb0a8', 11 / k);
        }
        ctx.globalAlpha = this.fade;
      }

      // medalhão da habilidade + selo de Clash em cada corrente
      if (plan) {
        const orderOf = {};
        preview.forEach((ev, i) => { [ev.a, ev.b].forEach(x => { if (x) orderOf[x.id] = i + 1; }); (ev.actions || []).forEach(x => { orderOf[x.id] = i + 1; }); });
        for (const a of plan.actions.filter(x => x.side === 'ally')) {
          const A = vis[a.actorId], sk = SKILLS[a.skillId];
          const on = !focus || [a.actorId, ...(a.partners || [])].includes(focus) || a.targetId === focus;
          ctx.globalAlpha = this.fade * (on ? 1 : 0.4);
          if (sk.kind === 'defense') {
            this._disk(ctx, A.x, A.y - 200, 14 / k, '#13202e', KIND_STYLE.defense.color, sk.icon, true);
            this._tag(ctx, A.x - 22 / k, A.y - 208, String(orderOf[a.id] || ''), '#ffe9b0', 12 / k);
            continue;
          }
          if (!a._cv || !this.routes || !this.routes[a.id]) continue;
          const m = this._at(a._cv, 0.16);
          this._disk(ctx, m.x, m.y, 13 / k, '#140c14', KIND_STYLE[styleOf(sk)].color, sk.icon, true);
          this._tag(ctx, m.x - 18 / k, m.y - 12 / k, String(orderOf[a.id] || ''), '#ffe9b0', 12 / k);
          // selo de Clash / interceptação
          const link = plan.links[a.id];
          const info = a.interceptInfo;
          if (link || info) {
            const ev = link && preview.find(e => e.type === 'clash' && (e.a.id === a.id || e.b.id === a.id));
            let col = '#888', label = '';
            if (ev) { const mine = ev.a.id === a.id, o = mine ? ev.odds : { win: ev.odds.lose, tie: ev.odds.tie, lose: ev.odds.win }; const cat = b.category(o.win, o); col = CAT_COLOR[cat]; label = CAT_NAME[cat]; }
            const q = this._at(a._cv, 0.5);
            const toggle = !!(info && info.valid && (!link || link.type === 'intercept'));
            this._disk(ctx, q.x, q.y, 14 / k, '#140c14', col, link ? (link.type === 'intercept' ? 'protect' : 'clash') : 'clash', !!link);
            if (label) this._tag(ctx, q.x + 18 / k, q.y + 4 / k, label, col, 12 / k);
            else if (info) this._tag(ctx, q.x + 18 / k, q.y + 4 / k, info.valid ? 'interceptar?' : 'lento demais', '#c9b', 11 / k);
            this.badges.push({ x: q.x, y: q.y, r: 14 / k, uid: a.actorId, toggle, act: a });
          }
        }
        ctx.globalAlpha = this.fade;
      }

      // Quebra pendente: este personagem perde a ação desta rodada
      for (const id in vis) {
        const v = vis[id], u = b.unit(id);
        if (!u || u.hp <= 0 || !u.broken) continue;
        ctx.globalAlpha = this.fade;
        this._tag(ctx, v.x, v.y - 200, 'DESEQUILIBRADO · perde a ação', '#ffd36a', 12 / k, true);
      }
      ctx.globalAlpha = this.fade;
      // indicador: combinação disponível para estes personagens
      if (this.enabled) for (const id in G.COMBOS) {
        const c = G.COMBOS[id];
        if (c.side !== 'ally' || !this.battle.combosFor(c.members[0]).includes(id)) continue;
        const used = this._plannedSkill(c.members[0]) === id;
        for (const m of c.members) {
          const v = vis[m];
          ctx.globalAlpha = this.fade * (used ? 1 : 0.55 + 0.25 * Math.sin(this.p.time * 0.005));
          this._disk(ctx, v.x + 38, v.y - 152, 9 / k, '#2a2010', KIND_STYLE.combo.color, 'combo', false);
        }
      }
      ctx.globalAlpha = this.fade;

      // carrossel em arco
      this._layoutMenu();
      if (this.arc) {
        const { C, f, R, open } = this.arc;
        ctx.save(); ctx.globalAlpha = this.fade * open;
        // faixa curva (trecho de uma roda maior) com bordas douradas e marcações
        const a0 = -84 * Math.PI / 180, a1 = 84 * Math.PI / 180, th = 50 / k;
        const ang = a => f > 0 ? a : Math.PI - a;
        ctx.lineCap = 'butt';
        const gr = ctx.createRadialGradient(C.x, C.y, R - th / 2, C.x, C.y, R + th / 2);
        gr.addColorStop(0, 'rgba(18,10,22,0.0)'); gr.addColorStop(0.25, 'rgba(18,10,22,0.82)'); gr.addColorStop(0.75, 'rgba(18,10,22,0.82)'); gr.addColorStop(1, 'rgba(18,10,22,0.0)');
        ctx.strokeStyle = gr; ctx.lineWidth = th;
        ctx.beginPath(); f > 0 ? ctx.arc(C.x, C.y, R, a0, a1) : ctx.arc(C.x, C.y, R, Math.PI - a0, Math.PI - a1, true); ctx.stroke();
        ctx.strokeStyle = 'rgba(216,180,90,0.55)'; ctx.lineWidth = 1.4 / k;
        for (const rr of [R - th * 0.42, R + th * 0.42]) { ctx.beginPath(); f > 0 ? ctx.arc(C.x, C.y, rr, a0, a1) : ctx.arc(C.x, C.y, rr, Math.PI - a0, Math.PI - a1, true); ctx.stroke(); }
        for (let d = -80; d <= 80; d += 10) { const a = ang((d + (this.sel.rot % 10)) * Math.PI / 180); ctx.globalAlpha = this.fade * open * 0.35 * (1 - Math.abs(d) / 95); ctx.beginPath(); ctx.moveTo(C.x + Math.cos(a) * (R + th * 0.42), C.y + Math.sin(a) * (R + th * 0.42)); ctx.lineTo(C.x + Math.cos(a) * (R + th * 0.32), C.y + Math.sin(a) * (R + th * 0.32)); ctx.stroke(); }
        // janela de foco no centro do arco
        ctx.globalAlpha = this.fade * open * 0.9; ctx.strokeStyle = '#ffe9b0'; ctx.lineWidth = 2 / k;
        ctx.beginPath(); f > 0 ? ctx.arc(C.x, C.y, R + th * 0.5, -0.13, 0.13) : ctx.arc(C.x, C.y, R + th * 0.5, Math.PI - 0.13, Math.PI + 0.13); ctx.stroke();
        ctx.restore();
        const sel = this.sel, active = this._activeSkill(), planned = this._plannedSkill(sel.uid);
        for (const it of this.items.slice().sort((a, b) => (a.focus || 0) - (b.focus || 0))) {
          const hov = this.hover.item && (this.hover.item === it || (it.skillId && this.hover.item.skillId === it.skillId));
          const r = it.r * (hov ? 1.12 : 1);
          ctx.globalAlpha = this.fade * it.open * it.fade * (it.disabled ? 0.45 : 1);
          if (it.cancel) { this._disk(ctx, it.x, it.y, r, '#2a1414', '#ff8a7a', 'cancel', false); continue; }
          const st = KIND_STYLE[it.kind], sk = SKILLS[it.skillId];
          const chosen = active === it.skillId || (!active && planned === it.skillId);
          this._disk(ctx, it.x, it.y, r, chosen ? '#2b2118' : '#140c14', chosen ? '#ffe9b0' : st.color, sk.icon, it.kind !== 'attack', it.kind);
          // nome curto do lado de fora da roda (maior no item em foco)
          const lx = this.arc.C.x + this.arc.f * Math.cos(it.ang) * (this.arc.R + 40 / k), ly = this.arc.C.y + Math.sin(it.ang) * (this.arc.R + 40 / k);
          ctx.save(); ctx.font = `${it.focus > 0.5 ? 800 : 600} ${(it.focus > 0.5 ? 14 : 11.5) / k}px "Trebuchet MS", sans-serif`;
          ctx.textAlign = this.arc.f > 0 ? 'left' : 'right'; ctx.lineWidth = 3.5 / k; ctx.strokeStyle = 'rgba(8,4,10,0.9)';
          const label = sk.name + (it.kind === 'combo' ? ' (combo)' : '') + (it.disabled ? (it.cd ? ` · recarga ${it.cd}` : ' · sem alvo') : '');
          ctx.strokeText(label, lx - this.arc.f * 10 / k, ly + 4 / k); ctx.fillStyle = it.focus > 0.5 ? '#fff1d0' : '#cbbfb0'; ctx.fillText(label, lx - this.arc.f * 10 / k, ly + 4 / k);
          ctx.restore();
        }
        ctx.globalAlpha = this.fade;
      }

      // dicas contextuais (tooltip)
      const k2 = k;
      if (this.enabled) {
        const hi = this.hover.item;
        if (hi && !hi.cancel && hi.skillId && this.sel) {
          const sk = SKILLS[hi.skillId], u = b.unit(sk.combo ? sk.members[0] : this.sel.uid);
          const lines = [{ t: sk.name + (sk.hits ? `  ·  ${sk.hits.length} golpes` : ''), c: '#ffe9b0' },
            sk.kind === 'attack' ? { t: `Força ${sk.force} · ${sk.beats || 1} batida(s) +0–${sk.impulse != null ? sk.impulse : 3} · Dano ${sk.dmg} · Pressão ${sk.pressure || 0} · Vel ${b.actionSpeed(u, sk)}`, c: '#e8dccb' } : { t: KIND_STYLE[sk.kind].label + (sk.kind === 'defense' ? ' · age antes de tudo' : ` · Vel ${b.actionSpeed(u, sk)}`), c: '#9fd0ff' },
            { t: sk.desc, c: '#bdb0a8', wrap: true }];
          if (sk.postureHeal) lines.push({ t: `Recupera ${sk.postureHeal} de Postura`, c: '#ffd36a' });
          { const E = G.ELEMENTS[u.def.element]; if (E && sk.kind === 'attack') lines.push({ t: `Elemento ${E.name}: forte contra ${G.ELEMENTS[E.beats].name}`, c: E.color }); }
          if (sk.combo) lines.push({ t: `Participantes: ${sk.members.map(m => b.unit(m).name).join(' + ')} · custa a ação dos dois`, c: KIND_STYLE.combo.color, wrap: true });
          if (hi.disabled) lines.push({ t: hi.cd ? `Em recarga (${hi.cd})` : 'Sem alvo válido', c: '#ff9a8a' });
          this._tooltip(ctx, hi.x, hi.y - hi.r - 10 / k2, lines);
        } else {
          const uid = this._activeUid(), sid = this._activeSkill();
          if (uid && sid && this.hover.unit && this.validTargets(uid, sid).includes(this.hover.unit)) {
            const T = vis[this.hover.unit];
            this._drawCard(ctx, T.x, T.y - 175, this.quickPreview(uid, sid, this.hover.unit, null));
          } else if (this.hover.badge && !this.drag) {
            const a = this.hover.badge.act, c = choices[a.actorId];
            this._drawCard(ctx, this.hover.badge.x, this.hover.badge.y - 10 / k2, this.quickPreview(a.actorId, a.skillId, a.targetId, c.intercept));
          } else if (this.hover.intent) {
            const it = b.intents.find(i => i.id === this.hover.intent.id);
            if (it) this._tooltip(ctx, this.hover.intent.x, this.hover.intent.y - 18 / k2, this.intentLines(it));
          } else if (!uid && this.hover.unit && this.showIntents) {
            const it = b.intents.find(i => i.actorId === this.hover.unit || (i.partners || []).includes(this.hover.unit));
            if (it) {
              const sk = SKILLS[it.skillId], A = vis[it.actorId];
              this._tooltip(ctx, A.x, A.y - 215, sk.kind === 'attack'
                ? [{ t: `${[it.actorId, ...(it.partners || [])].map(id => b.unit(id).name).join(' + ')} → ${b.unit(it.targetId).name}${sk.combo ? '  (ATAQUE COMBINADO)' : ''}`, c: '#ff9a8a' },
                   { t: `Postura ${b.unit(it.actorId).post}/${b.unit(it.actorId).postMax} · Pressão do golpe ${sk.pressure || 0}`, c: '#d9b85c' }, { t: `${sk.name} · Força ${sk.force} · Dano ${sk.dmg} · Vel ${b.actionSpeed(b.unit(it.actorId), sk)}`, c: '#e8dccb' }]
                : [{ t: `${b.unit(it.actorId).name} vai se defender`, c: '#9fd0ff' }, { t: sk.name, c: '#e8dccb' }]);
            }
          }
        }
      }
      ctx.restore();
    }

    // ------------------------------------------------------------ primitivas
    _disk(ctx, x, y, r, fill, ring, icon, alt, kind) {
      ctx.save();
      ctx.fillStyle = fill; ctx.strokeStyle = ring; ctx.lineWidth = r * 0.14;
      ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); ctx.stroke();
      // forma do anel também indica a categoria (não só a cor)
      if (kind === 'support') { ctx.setLineDash([r * 0.25, r * 0.2]); ctx.beginPath(); ctx.arc(x, y, r * 1.22, 0, 7); ctx.stroke(); }
      else if (kind === 'defense' || kind === 'protect') { ctx.lineWidth = r * 0.07; ctx.beginPath(); ctx.arc(x, y, r * 1.2, 0, 7); ctx.stroke(); }
      ctx.restore();
      drawIcon(ctx, icon, x, y, r * 0.62, ring);
    }
    _tag(ctx, x, y, text, color, size, center) {
      if (!text) return;
      ctx.save();
      ctx.font = `800 ${size}px "Trebuchet MS", sans-serif`; ctx.textAlign = center ? 'center' : 'left';
      ctx.lineWidth = size * 0.3; ctx.strokeStyle = 'rgba(8,4,10,0.9)'; ctx.strokeText(text, x, y);
      ctx.fillStyle = color; ctx.fillText(text, x, y);
      ctx.restore();
    }
    _tooltip(ctx, x, y, lines) {
      const k = this.p.pxPerWorld, fs = 13 / k, lh = 17 / k, pad = 8 / k, maxW = 270 / k;
      ctx.save();
      ctx.font = `600 ${fs}px "Trebuchet MS", sans-serif`;
      const rows = [];
      for (const l of lines) {
        if (!l.wrap) { rows.push(l); continue; }
        let cur = '';
        for (const w of l.t.split(' ')) {
          const t = cur ? cur + ' ' + w : w;
          if (ctx.measureText(t).width > maxW && cur) { rows.push({ t: cur, c: l.c }); cur = w; } else cur = t;
        }
        if (cur) rows.push({ t: cur, c: l.c });
      }
      const w = Math.min(maxW, Math.max(...rows.map(r => ctx.measureText(r.t).width))) + pad * 2;
      const h = rows.length * lh + pad * 1.4;
      // mantém dentro da tela visível
      const tl = this.p.toWorld(8, 8), br = this.p.toWorld(this.p.canvas.clientWidth - 8, this.p.canvas.clientHeight - 8);
      let bx = clamp(x - w / 2, tl.x, br.x - w), by = clamp(y - h, tl.y, br.y - h);
      ctx.fillStyle = 'rgba(12,7,16,0.93)'; ctx.strokeStyle = 'rgba(216,180,90,0.6)'; ctx.lineWidth = 1.2 / k;
      ctx.beginPath(); ctx.roundRect(bx, by, w, h, 6 / k); ctx.fill(); ctx.stroke();
      ctx.textAlign = 'left';
      rows.forEach((r, i) => { ctx.fillStyle = r.c; ctx.fillText(r.t, bx + pad, by + pad + fs + i * lh - 2 / k); });
      ctx.restore();
    }
  }

  // ------------------------------------------------------------ ÍCONES (procedurais)
  function drawIcon(ctx, key, x, y, s, color) {
    ctx.save();
    ctx.translate(x, y);
    ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = s * 0.16; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const L = (pts, close, fill) => { ctx.beginPath(); ctx.moveTo(pts[0] * s, pts[1] * s); for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i] * s, pts[i + 1] * s); if (close) ctx.closePath(); fill ? ctx.fill() : ctx.stroke(); };
    switch (key) {
      case 'sword': L([-0.7, 0.7, 0.6, -0.6]); L([-0.35, 0.15, -0.15, 0.35]); L([-0.7, 0.7, -0.85, 0.85]); break;
      case 'slash': ctx.beginPath(); ctx.arc(-0.2 * s, 0.3 * s, 0.9 * s, -1.4, -0.1); ctx.stroke(); L([-0.6, 0.6, 0.5, -0.5]); break;
      case 'precise': ctx.beginPath(); ctx.arc(0, 0, 0.6 * s, 0, 7); ctx.stroke(); L([0, -0.95, 0, -0.3]); L([0, 0.3, 0, 0.95]); L([-0.95, 0, -0.3, 0]); L([0.3, 0, 0.95, 0]); break;
      case 'risky': L([-0.8, 0.6, 0.6, -0.8]); L([-0.4, 0.8, 0.8, -0.4]); L([0.35, -0.85, 0.85, -0.85, 0.85, -0.35], false); break;
      case 'hammer': L([-0.6, 0.8, 0.25, -0.1]); L([-0.05, -0.75, 0.7, -0.05, 0.4, 0.25, -0.35, -0.45], true, true); break;
      case 'shieldbash': L([-0.55, -0.7, 0.35, -0.7, 0.35, 0.1, -0.1, 0.75, -0.55, 0.1], true); L([0.55, -0.4, 0.95, -0.4]); L([0.55, 0, 0.95, 0]); break;
      case 'shield': L([-0.65, -0.75, 0.65, -0.75, 0.65, 0.1, 0, 0.85, -0.65, 0.1], true); L([0, -0.55, 0, 0.55]); break;
      case 'protect': L([-0.5, -0.7, 0.5, -0.7, 0.5, 0.05, 0, 0.7, -0.5, 0.05], true); ctx.beginPath(); ctx.arc(0, -0.1 * s, 0.18 * s, 0, 7); ctx.fill(); break;
      case 'parry': L([-0.75, 0.75, 0.75, -0.75]); L([0.75, 0.75, -0.75, -0.75]); ctx.beginPath(); ctx.arc(0, 0, 0.22 * s, 0, 7); ctx.fill(); break;
      case 'clash': L([-0.75, 0.75, 0.6, -0.6]); L([0.75, 0.75, -0.6, -0.6]); L([-0.55, -0.85, -0.25, -0.55]); L([0.55, -0.85, 0.25, -0.55]); break;
      case 'bolt': ctx.beginPath(); ctx.arc(0.15 * s, -0.15 * s, 0.38 * s, 0, 7); ctx.fill(); L([-0.85, 0.85, -0.2, 0.2]); L([-0.85, 0.35, -0.45, 0.2]); L([-0.35, 0.85, -0.2, 0.45]); break;
      case 'blast': { ctx.beginPath(); for (let i = 0; i < 16; i++) { const a = i * Math.PI / 8, r = (i % 2 ? 0.38 : 0.95) * s; ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r); } ctx.closePath(); ctx.fill(); break; }
      case 'weaken': ctx.beginPath(); for (let i = 0; i <= 30; i++) { const a = i * 0.42, r = 0.08 * s + i * 0.026 * s; ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r); } ctx.stroke(); L([0.55, 0.35, 0.85, 0.85, 0.35, 0.75], true, true); break;
      case 'support': L([0, -0.8, 0, 0.8]); L([-0.8, 0, 0.8, 0]); ctx.beginPath(); ctx.arc(0, 0, 0.95 * s, 0, 7); ctx.globalAlpha *= 0.5; ctx.stroke(); break;
      case 'dodge': L([-0.85, -0.45, 0.2, -0.45]); L([-0.65, 0, 0.45, 0]); L([-0.85, 0.45, 0.2, 0.45]); L([0.35, -0.7, 0.85, 0, 0.35, 0.7], false); break;
      case 'cancel': L([-0.6, -0.6, 0.6, 0.6]); L([0.6, -0.6, -0.6, 0.6]); break;
      case 'spear': L([-0.85, 0.85, 0.45, -0.45]); L([0.3, -0.75, 0.85, -0.85, 0.75, -0.3], true, true); break;
      case 'sweep': ctx.beginPath(); ctx.arc(0, 0.35 * s, 0.85 * s, -2.8, -0.35); ctx.stroke(); L([0.55, -0.35, 0.95, -0.55, 0.85, -0.1], true, true); break;
      case 'pierce': L([-0.9, 0, 0.5, 0]); L([0.4, -0.3, 0.95, 0, 0.4, 0.3], true, true); L([-0.9, -0.4, -0.5, -0.4]); L([-0.9, 0.4, -0.5, 0.4]); break;
      case 'fist': ctx.beginPath(); ctx.roundRect(-0.55 * s, -0.5 * s, 1.0 * s, 0.9 * s, 0.25 * s); ctx.fill(); L([-0.85, -0.2, -0.6, -0.2]); L([-0.9, 0.15, -0.6, 0.15]); break;
      case 'flurry': for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc((-0.5 + i * 0.5) * s, (i % 2 ? 0.25 : -0.25) * s, 0.26 * s, 0, 7); ctx.fill(); } break;
      case 'upper': L([0, 0.9, 0, -0.5]); L([-0.45, -0.1, 0, -0.85, 0.45, -0.1], false); ctx.beginPath(); ctx.arc(0, 0.55 * s, 0.25 * s, 0, 7); ctx.fill(); break;
      case 'arrow': L([-0.85, 0.85, 0.55, -0.55]); L([0.25, -0.75, 0.85, -0.85, 0.75, -0.25], true, true); L([-0.85, 0.85, -0.85, 0.45]); L([-0.85, 0.85, -0.45, 0.85]); break;
      case 'arrow2': L([-0.85, 0.5, 0.45, -0.8]); L([-0.5, 0.85, 0.8, -0.45]); L([0.3, -0.95, 0.6, -0.95, 0.55, -0.65], true, true); L([0.65, -0.6, 0.95, -0.6, 0.9, -0.3], true, true); break;
      case 'arrowp': L([-0.9, 0.9, 0.55, -0.55]); L([0.2, -0.85, 0.95, -0.95, 0.85, -0.2], true, true); ctx.beginPath(); ctx.arc(0.65 * s, -0.65 * s, 0.25 * s, 0, 7); ctx.stroke(); break;
      case 'up': L([0, 0.8, 0, -0.6]); L([-0.6, -0.05, 0, -0.75, 0.6, -0.05], false); break;
      case 'warn': L([0, -0.85, 0.85, 0.7, -0.85, 0.7], true); ctx.fillStyle = '#140c14'; ctx.fillRect(-0.08 * s, -0.35 * s, 0.16 * s, 0.6 * s); ctx.fillStyle = color; break;
      case 'check': L([-0.7, 0, -0.2, 0.55, 0.75, -0.6], false); break;
      case 'skull': ctx.beginPath(); ctx.arc(0, -0.15 * s, 0.65 * s, 0, 7); ctx.fill(); ctx.fillRect(-0.35 * s, 0.3 * s, 0.7 * s, 0.45 * s); ctx.fillStyle = '#140c14'; ctx.beginPath(); ctx.arc(-0.25 * s, -0.15 * s, 0.15 * s, 0, 7); ctx.arc(0.25 * s, -0.15 * s, 0.15 * s, 0, 7); ctx.fill(); ctx.fillStyle = color; break;
      case 'combo': L([-0.8, 0.7, 0.35, -0.45]); L([0.8, 0.7, -0.35, -0.45]); ctx.beginPath(); for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4 - Math.PI / 2, r = (i % 2 ? 0.14 : 0.36) * s; ctx.lineTo(Math.cos(a) * r, -0.62 * s + Math.sin(a) * r); } ctx.closePath(); ctx.fill(); break;
      default: ctx.beginPath(); ctx.arc(0, 0, 0.5 * s, 0, 7); ctx.fill();
    }
    ctx.restore();
  }

  G.Planner = Planner;
  G.drawIcon = drawIcon;
})(window);
