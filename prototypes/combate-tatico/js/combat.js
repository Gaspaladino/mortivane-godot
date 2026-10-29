// =====================================================================
// LÓGICA DE COMBATE — sem nenhuma dependência visual.
// Resolve tudo de forma determinística (RNG com semente) e devolve
// "confrontos" que a apresentação apenas reproduz.
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

  class Battle {
    constructor(seed) {
      this.seed = seed;
      this.rand = makeRng(seed);
      this.round = 1;
      this.protectUsed = false;
      this.units = [];
      PARTY.forEach((k, i) => this.units.push(this._makeUnit(k, 'ally', i)));
      FOES.forEach((k, i) => this.units.push(this._makeUnit(k, 'enemy', i)));
    }

    _makeUnit(key, side, slot) {
      const d = UNITS[key];
      return { id: key, key, side, slot, def: d, name: d.name, hp: d.hp, maxHp: d.hp,
        statuses: {}, cooldowns: {} };
    }

    unit(id) { return this.units.find(u => u.id === id); }
    alive(side) { return this.units.filter(u => u.side === side && u.hp > 0); }
    outcome() {
      if (this.alive('enemy').length === 0) return 'victory';
      if (this.alive('ally').length === 0) return 'defeat';
      return null;
    }
    skillReady(u, skillId) { return !(u.cooldowns[skillId] > 0); }

    snapshot() {
      const s = {};
      for (const u of this.units) s[u.id] = { hp: u.hp, statuses: { ...u.statuses } };
      return s;
    }

    // ------------------------------------------------------- chances
    chance(kind, d, a, skill) {
      const tags = skill.tags;
      const mods = (table) => tags.reduce((acc, t) => acc + (table[t] || 0), 0);
      if (kind === 'dodge') {
        const c = CONFIG.dodge;
        return clamp(c.base + d.def.dodgeSkill + (d.def.spd - a.def.spd) * c.speedFactor + mods(c.tagMods), c.min, c.max);
      }
      if (kind === 'parry') {
        const c = CONFIG.parry;
        return clamp(c.base + d.def.parrySkill + mods(c.tagMods), c.min, c.max);
      }
      return 1; // block / barrier / none sempre "acontecem"
    }

    // Opções válidas de reação para um defensor contra um golpe
    reactionOptions(d, a, skill) {
      const marked = a.side === 'ally' && d.statuses.mark;
      let opts = d.def.reactions.filter(r => {
        if (r === 'parry' && skill.tags.includes('magic')) return false;
        if (marked && (r === 'parry' || r === 'dodge')) return false;
        return true;
      });
      if (opts.length === 0) opts = ['none'];
      return opts.map(kind => ({ kind, chance: this.chance(kind, d, a, skill),
        expected: this.expectedDamage(a, d, skill, kind) }));
    }
    defaultReaction(d, a, skill) { return this.reactionOptions(d, a, skill)[0].kind; }

    // ------------------------------------------------------- dano
    rawDamage(a, d, skill) {
      const c = CONFIG.damage;
      return skill.power * (a.def.atk / c.atkRef) * (c.defRef / (c.defRef + d.def.def));
    }
    multipliers(a, d, skill) {
      let m = 1;
      if (d.statuses.vulnerable) m *= CONFIG.vulnerableMult * (skill.vulnerableBonus || 1);
      if (a.side === 'ally' && d.statuses.mark) m *= CONFIG.markMult;
      return m;
    }
    blockFactor(d, skill) { return skill.unblockable ? 1 : 1 - d.def.blockPower; }

    // Dano esperado (sem variância) — usado pela UI e pela IA
    expectedDamage(a, d, skill, kind) {
      const base = this.rawDamage(a, d, skill) * this.multipliers(a, d, skill);
      const ch = this.chance(kind, d, a, skill);
      switch (kind) {
        case 'block': case 'barrier': return base * this.blockFactor(d, skill);
        case 'dodge': return base * (1 - ch);
        case 'parry': return base * (1 - ch) * CONFIG.parry.failMult;
        default: return base;
      }
    }
    previewHit(a, d, skill) { return Math.round(this.rawDamage(a, d, skill) * this.multipliers(a, d, skill)); }

    _roll() { return this.rand(); }
    _variance() { return 1 + (this.rand() * 2 - 1) * CONFIG.damage.variance; }

    // ------------------------------------------------------- confronto
    // action: { attackerId, skillId, targetId, reaction?, protectorId? }
    resolveAttack(action) {
      const a = this.unit(action.attackerId);
      const skill = SKILLS[action.skillId];
      let target = this.unit(action.targetId);
      let retargeted = false;
      if (!target || target.hp <= 0) {
        const pool = this.alive(a.side === 'ally' ? 'enemy' : 'ally').sort((x, y) => x.hp - y.hp);
        target = pool[0];
        retargeted = true;
      }
      let protector = null;
      if (action.protectorId) {
        const p = this.unit(action.protectorId);
        if (p && p.hp > 0 && p !== target) protector = p;
      }
      const d = protector || target;
      const opts = this.reactionOptions(d, a, skill).map(o => o.kind);
      let reaction = protector ? opts.find(k => k === 'block') || opts[0]
        : (opts.includes(action.reaction) ? action.reaction : opts[0]);
      if (retargeted) reaction = opts[0];

      const markConsumed = a.side === 'ally' && !!d.statuses.mark;
      const chance = this.chance(reaction, d, a, skill);
      const roll = this._roll();
      const success = roll < chance;
      const variance = this._variance();
      const mult = this.multipliers(a, d, skill);
      const base = this.rawDamage(a, d, skill) * variance * mult;

      let dmg = 0, outcome = 'hit';
      if (reaction === 'block' || reaction === 'barrier') {
        if (skill.unblockable) { outcome = 'guardBroken'; dmg = base; }
        else { outcome = 'blocked'; dmg = base * this.blockFactor(d, skill); }
      } else if (reaction === 'dodge') {
        if (success) { outcome = 'dodged'; dmg = 0; } else { outcome = 'dodgeFail'; dmg = base; }
      } else if (reaction === 'parry') {
        if (success) { outcome = 'parried'; dmg = 0; } else { outcome = 'parryFail'; dmg = base * CONFIG.parry.failMult; }
      } else { dmg = base; }
      dmg = dmg > 0 ? Math.max(CONFIG.damage.min, Math.round(dmg)) : 0;

      const hpBefore = d.hp;
      d.hp = Math.max(0, d.hp - dmg);
      const consumed = [];
      if (dmg > 0 && d.statuses.vulnerable) { delete d.statuses.vulnerable; consumed.push('vulnerable'); }
      if (markConsumed) { delete d.statuses.mark; consumed.push('mark'); }

      let applied = null;
      if (skill.applies && d.hp > 0 && (dmg > 0 || outcome === 'blocked')) {
        if (skill.applies === 'taunt') d.statuses.taunt = a.id;
        else d.statuses[skill.applies] = true;
        applied = skill.applies;
      }
      if (skill.cooldown) a.cooldowns[action.skillId] = skill.cooldown;

      // Contra-ataque do aparo: não pode ser reagido (sem cadeias infinitas)
      let counter = null;
      if (outcome === 'parried' && a.hp > 0) {
        const cskill = { power: CONFIG.parry.counterPower, tags: ['melee'] };
        let cd = this.rawDamage(d, a, cskill) * this._variance() * this.multipliers(d, a, cskill);
        const cConsumed = [];
        if (a.statuses.vulnerable) { delete a.statuses.vulnerable; cConsumed.push('vulnerable'); }
        if (d.side === 'ally' && a.statuses.mark) { delete a.statuses.mark; cConsumed.push('mark'); }
        cd = Math.max(CONFIG.damage.min, Math.round(cd));
        const before = a.hp;
        a.hp = Math.max(0, a.hp - cd);
        counter = { damage: cd, hpBefore: before, hpAfter: a.hp, killed: a.hp <= 0, consumed: cConsumed };
      }

      const killed = d.hp <= 0;
      const decisive = (dmg > 0 && (killed || dmg >= d.maxHp * CONFIG.decisiveRatio)) ||
        (counter && counter.killed);
      return {
        attackerId: a.id, skillId: action.skillId, skill,
        targetId: target.id, defenderId: d.id, protectorId: protector ? protector.id : null,
        reaction, chance, roll, success, outcome, damage: dmg, hpBefore, hpAfter: d.hp,
        killed, applied, consumed, counter, decisive, retargeted,
        after: this.snapshot(),
      };
    }

    // Ordem: velocidade (desempate: aliados primeiro, depois posição)
    orderBySpeed(actions) {
      return actions.slice().sort((x, y) => {
        const a = this.unit(x.attackerId), b = this.unit(y.attackerId);
        return (b.def.spd - a.def.spd) || (a.side === b.side ? a.slot - b.slot : (a.side === 'ally' ? -1 : 1));
      });
    }

    // plans: [{attackerId, skillId, targetId}]
    resolvePlayerPhase(plans) {
      const results = [];
      for (const p of this.orderBySpeed(plans)) {
        const a = this.unit(p.attackerId);
        if (a.hp <= 0 || this.outcome()) continue;
        if (!this.skillReady(a, p.skillId)) continue;
        // a reação inimiga é decidida no instante do golpe (com o estado atual)
        let t = this.unit(p.targetId);
        if (!t || t.hp <= 0) t = this.alive('enemy').sort((x, y) => x.hp - y.hp)[0];
        const reaction = G.AI.chooseReaction(this, t, a, SKILLS[p.skillId]);
        results.push(this.resolveAttack({ ...p, targetId: t.id, reaction }));
      }
      return results;
    }

    planEnemyIntents() { return this.orderBySpeed(G.AI.planIntents(this)); }

    // choices: { [index]: { reaction, protect } }
    resolveEnemyPhase(intents, choices) {
      const results = [];
      intents.forEach((it, i) => {
        const a = this.unit(it.attackerId);
        if (a.hp <= 0 || this.outcome()) return;
        const ch = choices[i] || {};
        let protectorId = null;
        if (ch.protect && !this.protectUsed) {
          const k = this.units.find(u => u.def.canProtect && u.hp > 0);
          const t = this.unit(it.targetId);
          if (k && t && t.hp > 0 && k !== t) { protectorId = k.id; this.protectUsed = true; }
        }
        results.push(this.resolveAttack({ ...it, reaction: ch.reaction, protectorId }));
      });
      return results;
    }

    endRound() {
      for (const u of this.units) {
        for (const k in u.cooldowns) if (u.cooldowns[k] > 0) u.cooldowns[k]--;
      }
      this.protectUsed = false;
      this.round++;
    }
  }

  G.Battle = Battle;
  G.makeRng = makeRng;
})(typeof window !== 'undefined' ? window : globalThis);
