// =====================================================================
// PRÉVIA ANIMADA DAS HABILIDADES (fichas da formação)
// Reaproveita o Presenter real num canvas próprio, com um boneco de treino.
// Só cria eventos sintéticos de apresentação: não toca na batalha, não
// consome ações, não roda IA nem muda o Clash.
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS } = G;

  class SkillPreview {
    constructor() {
      this.box = document.createElement('div'); this.box.className = 'pv-box';
      this.canvas = document.createElement('canvas'); this.box.appendChild(this.canvas);
      this.label = document.createElement('div'); this.label.className = 'pv-label'; this.box.appendChild(this.label);
      this.p = null; this.token = 0; this.current = null;
    }
    // coloca o canvas (persistente) dentro da ficha recém-desenhada
    mount(slot) { if (slot && this.box.parentElement !== slot) slot.appendChild(this.box); }
    _ensure() {
      if (!this.p) { this.p = new G.Presenter(this.canvas); }
      this.p.paused = false;
    }
    pause() { this.token++; this.current = null; if (this.p) { this.p.skip(); this.p.skipping = false; this.p.paused = true; } }

    // Monta a cena: personagem à esquerda, boneco (ou inimigo/aliado demonstrativo) à direita
    _scene(charId, skill) {
      const helper = ['knight', 'swordsman', 'mage'].find(id => id !== charId);
      const b = new G.Battle(1, [charId, helper]);
      this.p.reset(b);
      const keepEnemy = skill.kind === 'defense' || skill.kind === 'protect' ? 'duelist' : 'brute';
      for (const id of Object.keys(this.p.vis)) if (![charId, keepEnemy, ...(skill.kind === 'protect' || skill.kind === 'support' ? [helper] : [])].includes(id)) delete this.p.vis[id];
      const me = this.p.vis[charId], foe = this.p.vis[keepEnemy];
      Object.assign(me, { x: 470, y: 600, home: { x: 470, y: 600 }, face: 1 });
      Object.assign(foe, { x: 790, y: 600, home: { x: 790, y: 600 }, face: -1 });
      if (keepEnemy === 'brute') Object.assign(foe, { art: 'dummy', name: 'Boneco', hp: 99, dispHp: 99, maxHp: 99, post: 80, postMax: 80, dispPost: 80 });
      const ally = this.p.vis[helper];
      if (ally) Object.assign(ally, { x: 330, y: 580, home: { x: 330, y: 580 }, face: 1 });
      this.p.overview();
      this.p.camT = { x: 600, y: 520, z: 1.25 };
      return { b, me, foe, ally, helper, foeId: keepEnemy };
    }

    async play(charId, skillId, loop = true) {
      const key = charId + ':' + skillId;
      if (this.current === key) return;
      this.current = key;
      const tk = ++this.token;
      this._ensure();
      const sk = SKILLS[skillId];
      this.label.textContent = sk.name;
      while (tk === this.token) {
        this.p.skip(); this.p.skipping = false;
        const sc = this._scene(charId, sk);
        await this.p.wait(350);
        if (tk !== this.token) return;
        await this.p.playAll(this._events(charId, sk, skillId, sc));
        if (tk !== this.token) return;
        await this.p.wait(900);
        if (!loop || G.reduceMotion) { this.current = null; return; }
      }
    }

    // Eventos sintéticos no MESMO formato da lógica (só apresentação)
    _events(charId, sk, skillId, sc) {
      const dummy = sc.foe;
      if (sk.kind === 'attack') {
        const impact = sc.b.impactOf(sk, sk.dmg, { maxHp: 56 }, false);
        return [{ type: 'attack', attackerId: charId, partners: [], skillId, skill: sk, targetId: sc.foeId, defenderId: sc.foeId, protectorId: null,
          reaction: 'none', outcome: 'hit', damage: sk.dmg, crit: false, hpBefore: dummy.hp, hpAfter: dummy.hp - sk.dmg, killed: false,
          applied: null, impact, consumed: [], counter: null, decisive: false, after: null }];
      }
      if (sk.kind === 'support') {
        return [{ type: 'support', actorId: charId, targetId: sc.helper, skillId, postHeal: sk.postureHeal || 0, after: null }];
      }
      // defesas: o inimigo demonstrativo ataca e a reação acontece
      const atk = SKILLS.d_flurry, me = sc.me;
      const stance = sk.kind === 'protect'
        ? { type: 'stances', list: [{ unitId: charId, skillId, reaction: 'block', protectId: sc.helper }], after: null }
        : { type: 'stances', list: [{ unitId: charId, skillId, reaction: sk.reaction, postHeal: sk.postureHeal || 0 }], after: null };
      const target = sk.kind === 'protect' ? sc.helper : charId;
      const r = sk.kind === 'protect' ? 'block' : sk.reaction;
      const outcome = { block: 'blocked', parry: 'parried', dodge: 'dodged' }[r];
      const dmg = outcome === 'blocked' ? 3 : 0;
      return [stance, { type: 'attack', attackerId: 'duelist', partners: [], skillId: 'd_flurry', skill: atk, targetId: target, defenderId: charId,
        protectorId: sk.kind === 'protect' ? charId : null, reaction: r, outcome, damage: dmg, crit: false, hpBefore: me.hp, hpAfter: me.hp - dmg,
        killed: false, applied: null, impact: 'light', consumed: [],
        counter: outcome === 'parried' ? { damage: 6, hpBefore: 40, hpAfter: 34, killed: false, consumed: [] } : null, decisive: false, after: null }];
    }
  }

  G.SkillPreview = SkillPreview;
})(window);
