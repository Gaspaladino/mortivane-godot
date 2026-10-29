// =====================================================================
// LÓGICA DE COMBATE — sem nenhuma dependência visual.
// Rodada compartilhada: intenções inimigas → plano do jogador →
// validação/ligações (Clashes, interceptações) → fila de eventos.
// Tudo é decidido aqui com RNG de semente; a apresentação só reproduz.
// =====================================================================
(function (G) {
  'use strict';
  const { CONFIG, SKILLS, UNITS, PARTY, FOES } = G;

  function makeRng(seed) {
    let s = seed >>> 0;
    return function () {
      s = (s + 0x6D2B79F5) >>> 0;
      let t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const isAttack = sk => sk && sk.kind === 'attack';
  // Participantes de uma ação (ataques combinados têm mais de um)
  const members = act => [act.actorId, ...(act.partners || [])];

  class Battle {
    // party: ids dos 3 aliados escolhidos na formação (ordem = posição: frente → retaguarda)
    constructor(seed, party = PARTY) {
      this.seed = seed;
      this.rand = makeRng(seed);
      this.round = 1;
      this.units = [];
      this.intents = [];
      party.forEach((k, i) => this.units.push(this._makeUnit(k, 'ally', i)));
      FOES.forEach((k, i) => this.units.push(this._makeUnit(k, 'enemy', i)));
    }
    _makeUnit(key, side, slot) {
      const d = UNITS[key];
      return { id: key, key, side, slot, def: d, name: d.name, hp: d.hp, maxHp: d.hp, statuses: {}, cooldowns: {} };
    }

    unit(id) { return this.units.find(u => u.id === id); }
    alive(side) { return this.units.filter(u => u.side === side && u.hp > 0); }
    outcome() {
      if (this.alive('enemy').length === 0) return 'victory';
      if (this.alive('ally').length === 0) return 'defeat';
      return null;
    }
    skillReady(u, id) { return !(u.cooldowns[id] > 0); }
    allAlive(act) { return members(act).every(id => this.unit(id).hp > 0); }
    // Combinação disponível para este aliado? (todos os membros vivos e sem recarga)
    combosFor(uid) {
      return Object.keys(G.COMBOS).filter(id => {
        const c = G.COMBOS[id];
        // só existe se os dois membros estiverem na equipe e vivos
        return c.side === 'ally' && c.members.includes(uid) && c.members.every(m => this.unit(m) && this.unit(m).hp > 0) &&
          this.skillReady(this.unit(c.members[0]), id);
      });
    }
    snapshot() {
      const s = {};
      for (const u of this.units) s[u.id] = { hp: u.hp, statuses: JSON.parse(JSON.stringify(u.statuses)) };
      return s;
    }

    // ------------------------------------------------------------ velocidade
    actionSpeed(u, sk) {
      // combinação: anda no ritmo do membro mais lento
      let s = sk.combo ? Math.min(...sk.members.map(id => this.unit(id).def.spd)) : u.def.spd;
      for (const t of sk.tags) s += CONFIG.speed[t] || 0;
      if (sk.kind === 'defense' || sk.kind === 'protect') s += CONFIG.speed.defense;
      if (sk.kind === 'support') s += 0; // a tag 'support' já dá prioridade
      return s;
    }

    // ------------------------------------------------------------ etapa 1
    planEnemyIntents() {
      this.intents = G.AI.planIntents(this).map((it, i) => ({ ...it, id: 'e' + i, side: 'enemy' }));
      return this.intents;
    }

    // ------------------------------------------------------------ etapa 2/3
    // choices: { [allyId]: { skillId, targetId, intercept } }
    // Devolve o plano validado: ações, ligações de Clash e ordem prevista.
    buildPlan(choices) {
      const actions = [];
      const errors = [];
      for (const it of this.intents) {
        const a = this.unit(it.actorId);
        if (this.allAlive(it)) actions.push({ ...it, speed: this.actionSpeed(a, SKILLS[it.skillId]) });
      }
      for (const u of this.alive('ally')) {
        const c = choices[u.id];
        if (!c || !c.skillId) continue; // (parceiro de combinação: c.comboWith, sem ação própria)
        const sk = SKILLS[c.skillId];
        const own = sk.combo ? sk.members[0] === u.id : u.def.skills.includes(c.skillId);
        if (!own || !this.skillReady(u, c.skillId)) { errors.push(`${u.name}: habilidade indisponível`); continue; }
        const partners = sk.combo ? sk.members.slice(1) : undefined;
        // a combinação consome a ação de todos os membros: precisam estar vivos e reservados
        if (partners && !partners.every(id => this.unit(id).hp > 0 && choices[id] && choices[id].comboWith === u.id)) { errors.push(`${sk.name}: parceiro indisponível`); continue; }
        let targetId = c.targetId;
        if (sk.kind === 'defense') targetId = u.id;
        const t = this.unit(targetId);
        const okTarget = t && t.hp > 0 && (
          (sk.kind === 'attack' && t.side === 'enemy') ||
          (sk.kind === 'support' && t.side === 'ally' && t !== u) ||
          (sk.kind === 'protect' && t.side === 'ally' && t !== u) ||
          sk.kind === 'defense');
        if (!okTarget) continue; // ainda incompleto
        actions.push({ id: 'a_' + u.id, side: 'ally', actorId: u.id, skillId: c.skillId, targetId, partners,
          wantIntercept: !!c.intercept, speed: this.actionSpeed(u, sk) });
      }

      // Ligações de Clash: direto (alvos mútuos) tem prioridade; depois interceptações válidas.
      const links = {}; // actionId -> { partner, type }
      const enemyAttacks = actions.filter(x => x.side === 'enemy' && isAttack(SKILLS[x.skillId]));
      const allyAttacks = actions.filter(x => x.side === 'ally' && isAttack(SKILLS[x.skillId]));
      for (const aa of allyAttacks) {
        // direto: o inimigo-alvo (ou sua combinação) mira algum membro desta ação
        const ea = enemyAttacks.find(e => members(e).includes(aa.targetId) && members(aa).includes(e.targetId));
        if (ea && !links[ea.id]) { links[aa.id] = { partner: ea.id, type: 'direct' }; links[ea.id] = { partner: aa.id, type: 'direct' }; }
      }
      for (const aa of allyAttacks) {
        aa.interceptInfo = this.interceptInfo(aa, enemyAttacks);
        if (links[aa.id] || !aa.wantIntercept) continue;
        const info = aa.interceptInfo;
        if (info && info.valid && !links[info.enemyActionId]) {
          links[aa.id] = { partner: info.enemyActionId, type: 'intercept' };
          links[info.enemyActionId] = { partner: aa.id, type: 'intercept', redirectTo: aa.actorId };
        }
      }
      const order = this._order(actions, links);
      return { actions, links, order, errors };
    }

    // Pode este ataque aliado interceptar o ataque do inimigo-alvo contra outro aliado?
    interceptInfo(aa, enemyAttacks) {
      const ea = enemyAttacks.find(e => members(e).includes(aa.targetId));
      if (!ea || members(aa).includes(ea.targetId)) return null;
      const ally = this.unit(aa.actorId);
      const reach = ally.def.interceptReach || 0;
      return { enemyActionId: ea.id, protects: ea.targetId, valid: aa.speed + reach >= ea.speed,
        mySpeed: aa.speed, reach, enemySpeed: ea.speed };
    }

    // Ordem: posturas primeiro; depois por velocidade. Um Clash é UM evento,
    // posicionado pela ação mais rápida do par.
    _order(actions, links) {
      const byId = Object.fromEntries(actions.map(a => [a.id, a]));
      const sorted = actions.slice().sort((x, y) => (y.speed - x.speed) ||
        (x.side === y.side ? this.unit(x.actorId).slot - this.unit(y.actorId).slot : (x.side === 'ally' ? -1 : 1)));
      const used = new Set(), order = [];
      const stances = sorted.filter(a => ['defense', 'protect'].includes(SKILLS[a.skillId].kind));
      if (stances.length) { order.push({ type: 'stances', actions: stances }); stances.forEach(a => used.add(a.id)); }
      for (const a of sorted) {
        if (used.has(a.id)) continue;
        used.add(a.id);
        const l = links[a.id];
        if (l) { used.add(l.partner); order.push({ type: 'clash', a, b: byId[l.partner], link: l }); }
        else order.push({ type: SKILLS[a.skillId].kind === 'support' ? 'support' : 'attack', a });
      }
      return order;
    }

    // ------------------------------------------------------------ prévia
    forceMods(u, consumeSupport) {
      let m = 0;
      if (u.statuses.weaken) m -= CONFIG.weaken.amount;
      if (u.statuses.support) { m += CONFIG.support.amount; if (consumeSupport) delete u.statuses.support; }
      return m;
    }
    // Chances de vitória/empate de A sobre B somando as rolagens possíveis
    clashOdds(fa, fb) {
      const { rollMin: lo, rollMax: hi } = CONFIG.clash;
      let win = 0, tie = 0, n = 0;
      for (let i = lo; i <= hi; i++) for (let j = lo; j <= hi; j++) {
        n++; if (fa + i > fb + j) win++; else if (fa + i === fb + j) tie++;
      }
      return { win: win / n, tie: tie / n, lose: 1 - (win + tie) / n };
    }
    category(p) {
      const c = CONFIG.clash;
      return p >= c.favorable ? 'favorable' : p < c.unfavorable ? 'unfavorable' : 'even';
    }
    // Simula só a parte determinística (modificadores na ordem certa) para a prévia.
    previewPlan(plan) {
      const mods = {}; // unitId -> { weaken, support }
      for (const u of this.units) mods[u.id] = { weaken: !!u.statuses.weaken, support: !!u.statuses.support };
      const force = (act) => {
        const sk = SKILLS[act.skillId], m = mods[act.actorId];
        let f = sk.force + (m.weaken ? -CONFIG.weaken.amount : 0) + (m.support ? CONFIG.support.amount : 0);
        m.support = false;
        return f;
      };
      const out = [];
      for (const ev of plan.order) {
        if (ev.type === 'clash') {
          const fa = force(ev.a), fb = force(ev.b);
          const odds = this.clashOdds(fa, fb);
          out.push({ ...ev, fa, fb, odds, cat: this.category(odds.win) });
          // um efeito que só acontece se o Clash for vencido não é contado como certo
        } else if (ev.type === 'support') {
          mods[ev.a.targetId].support = true; out.push(ev);
        } else if (ev.type === 'attack') {
          force(ev.a);
          const sk = SKILLS[ev.a.skillId];
          if (sk.applies === 'weaken') mods[ev.a.targetId].weaken = true;
          out.push(ev);
        } else out.push(ev);
      }
      return out;
    }

    // ------------------------------------------------------------ etapa 4
    resolveRound(plan) {
      const events = [];
      const done = new Set();
      // recargas: gastas quando a rodada começa (ação confirmada)
      for (const a of plan.actions) {
        const sk = SKILLS[a.skillId];
        if (sk.cooldown) this.unit(a.actorId).cooldowns[a.skillId] = sk.cooldown;
      }
      for (const ev of plan.order) {
        if (this.outcome()) break;
        if (ev.type === 'stances') { const e = this._stances(ev.actions); if (e) events.push(e); continue; }
        if (ev.type === 'support') { events.push(this._support(ev.a)); continue; }
        if (ev.type === 'clash') { events.push(...this._clashOrFallback(ev, done)); continue; }
        events.push(this._attack(ev.a));
      }
      return events.filter(Boolean);
    }

    _stances(actions) {
      const list = [];
      for (const a of actions) {
        const u = this.unit(a.actorId), sk = SKILLS[a.skillId];
        if (u.hp <= 0) continue;
        if (sk.kind === 'protect') {
          const t = this.unit(a.targetId);
          if (!t || t.hp <= 0) continue;
          t.statuses.protect = u.id;
          u.statuses.block = true;
          list.push({ unitId: u.id, skillId: a.skillId, reaction: 'block', protectId: t.id });
        } else {
          u.statuses[sk.reaction] = true;
          list.push({ unitId: u.id, skillId: a.skillId, reaction: sk.reaction });
        }
      }
      return list.length ? { type: 'stances', list, after: this.snapshot() } : null;
    }

    _support(a) {
      const u = this.unit(a.actorId), t = this.unit(a.targetId);
      if (u.hp <= 0) return null;
      if (!t || t.hp <= 0) return { type: 'fizzle', actorId: u.id, skillId: a.skillId, reason: 'alvo caído' };
      t.statuses.support = true;
      return { type: 'support', actorId: u.id, targetId: t.id, skillId: a.skillId, after: this.snapshot() };
    }

    _roll() {
      const { rollMin: lo, rollMax: hi } = CONFIG.clash;
      return lo + Math.floor(this.rand() * (hi - lo + 1));
    }

    _clashOrFallback(ev, done) {
      const A = this.unit(ev.a.actorId), B = this.unit(ev.b.actorId);
      // se um lado caiu (ou perdeu um membro da combinação), o outro age sem oposição
      const okA = this.allAlive(ev.a), okB = this.allAlive(ev.b);
      if (!okA || !okB) {
        // o lado incompleto vira "fizzle" (_attack detecta); o lado inteiro age normalmente
        const out = [];
        if (!okA) out.push(this._attack(ev.a));
        if (!okB) out.push(this._attack(ev.b));
        if (okA) out.push(this._attack(ev.a));
        if (okB) out.push(this._attack(ev.b));
        return out.filter(Boolean);
      }
      const skA = SKILLS[ev.a.skillId], skB = SKILLS[ev.b.skillId];
      const side = (u, act, sk) => {
        const mod = this.forceMods(u, true);
        const roll = this._roll();
        return { actorId: u.id, skillId: act.skillId, partners: act.partners || [], base: sk.force, mod, roll, total: sk.force + mod + roll };
      };
      const sa = side(A, ev.a, skA), sb = side(B, ev.b, skB);
      // a: sempre o aliado quando há um (para a apresentação ser previsível)
      const intercept = ev.link.type === 'intercept';
      const enemyAct = A.side === 'enemy' ? ev.a : ev.b;
      const res = { type: 'clash', a: sa, b: sb, intercept, originalTargetId: intercept ? enemyAct.targetId : null,
        winner: null, hit: null };
      res.close = Math.abs(sa.total - sb.total) <= CONFIG.clash.closeMargin;
      if (sa.total !== sb.total) {
        const [W, L, wAct] = sa.total > sb.total ? [A, B, ev.a] : [B, A, ev.b];
        res.winner = W.id;
        res.hit = this._applyHit(W, L, wAct.skillId);
      }
      if (A.side === 'enemy') { const t = res.a; res.a = res.b; res.b = t; } // a = aliado
      res.decisive = !!(res.hit && res.hit.killed);
      res.after = this.snapshot();
      return [res];
    }

    _applyHit(att, def, skillId, dmgMult = 1) {
      const sk = SKILLS[skillId];
      let dmg = Math.max(1, Math.round(sk.dmg * dmgMult));
      const hpBefore = def.hp;
      def.hp = Math.max(0, def.hp - dmg);
      let applied = null;
      if (sk.applies && def.hp > 0) {
        def.statuses[sk.applies] = { rounds: CONFIG.weaken.rounds };
        applied = sk.applies;
      }
      return { attackerId: att.id, defenderId: def.id, skillId,
        damage: dmg, hpBefore, hpAfter: def.hp, killed: def.hp <= 0, applied, impact: this.impactOf(sk, dmg, def, dmgMult < 1) };
    }

    // Classificação do impacto físico: light | medium | heavy | extreme.
    // Hoje é só visual; fica na lógica para permitir consequências futuras.
    impactOf(sk, dmg, def, blocked) {
      const LV = ['light', 'medium', 'heavy', 'extreme'];
      const r = dmg / def.maxHp, c = CONFIG.impact;
      let lv = r >= c.heavy ? 2 : r >= c.medium ? 1 : 0;
      if (sk.impact === 'push') lv = Math.max(lv, 1);
      if (sk.impact === 'stagger') lv = Math.max(lv, 2);
      if (sk.impact === 'knockdown') lv = 3;
      if (blocked) lv = Math.max(0, lv - 1);
      return LV[Math.min(lv, sk.impact === 'knockdown' ? 3 : 2)];
    }

    chance(kind, d, a, sk) {
      const has = t => sk.tags.includes(t) ? 1 : 0;
      if (kind === 'dodge') {
        const c = CONFIG.dodge;
        return clamp(c.base + (d.def.dodgeSkill || 0) + (d.def.spd - a.def.spd) * c.speedFactor + has('heavy') * c.heavy + has('fast') * c.fast, c.min, c.max);
      }
      if (kind === 'parry') {
        const c = CONFIG.parry;
        return clamp(c.base + (d.def.parrySkill || 0) + has('heavy') * c.heavy + has('fast') * c.fast, c.min, c.max);
      }
      return 1;
    }

    // Ataque sem oposição (pode sofrer bloqueio, esquiva, aparo ou proteção)
    _attack(act) {
      const a = this.unit(act.actorId), sk = SKILLS[act.skillId];
      if (a.hp <= 0) return null;
      // combinação sem todos os membros não acontece (nada de ação extra pela metade)
      if (!this.allAlive(act)) return { type: 'fizzle', actorId: a.id, skillId: act.skillId, reason: 'combinação interrompida' };
      const t = this.unit(act.targetId);
      if (!t || t.hp <= 0) return { type: 'fizzle', actorId: a.id, skillId: act.skillId, reason: 'alvo já caído' };
      this.forceMods(a, true); // gasta o Suporte, se houver
      let d = t, protectorId = null;
      if (t.statuses.protect) {
        const k = this.unit(t.statuses.protect);
        if (k && k.hp > 0) { d = k; protectorId = k.id; }
      }
      let reaction = d.statuses.block ? 'block' : d.statuses.dodge ? 'dodge' : d.statuses.parry ? 'parry' : 'none';
      if (reaction === 'parry' && (sk.tags.includes('magic') || d.statuses.parry === 'used')) reaction = 'none';
      const ch = this.chance(reaction, d, a, sk);
      const success = this.rand() < ch;
      let outcome = 'hit', mult = 1, counter = null;
      if (reaction === 'block') { outcome = 'blocked'; mult = 1 - (d.def.blockPower || CONFIG.block); }
      else if (reaction === 'dodge') { outcome = success ? 'dodged' : 'dodgeFail'; mult = success ? 0 : 1; }
      else if (reaction === 'parry') {
        d.statuses.parry = 'used'; // só o primeiro golpe físico
        outcome = success ? 'parried' : 'parryFail'; mult = success ? 0 : 1;
      }
      let hit;
      if (mult === 0) hit = { damage: 0, hpBefore: d.hp, hpAfter: d.hp, killed: false, applied: null, impact: null };
      else hit = this._applyHit(a, d, act.skillId, mult);
      if (outcome === 'parried') {
        const before = a.hp, cd = CONFIG.parry.counterDmg;
        a.hp = Math.max(0, a.hp - cd);
        counter = { damage: cd, hpBefore: before, hpAfter: a.hp, killed: a.hp <= 0, consumed: [] };
      }
      return { type: 'attack', attackerId: a.id, partners: act.partners || [], skillId: act.skillId, skill: sk, targetId: t.id, defenderId: d.id,
        protectorId, reaction, chance: ch, success, outcome, damage: hit.damage, hpBefore: hit.hpBefore, hpAfter: hit.hpAfter,
        killed: hit.killed, applied: hit.applied, impact: hit.impact, consumed: [], counter,
        decisive: hit.killed || !!(counter && counter.killed), after: this.snapshot() };
    }

    endRound() {
      for (const u of this.units) {
        for (const k in u.cooldowns) if (u.cooldowns[k] > 0) u.cooldowns[k]--;
        delete u.statuses.block; delete u.statuses.dodge; delete u.statuses.parry; delete u.statuses.protect;
        if (u.statuses.weaken && --u.statuses.weaken.rounds <= 0) delete u.statuses.weaken;
      }
      this.round++;
    }
  }

  G.Battle = Battle;
  G.makeRng = makeRng;
})(typeof window !== 'undefined' ? window : globalThis);
