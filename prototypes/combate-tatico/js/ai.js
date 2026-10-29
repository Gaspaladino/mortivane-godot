// =====================================================================
// IA — decide as intenções ANTES do planejamento do jogador e não muda
// depois. Cada inimigo tem uma preferência própria.
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS, AI_THREAT } = G;

  const AI = {
    planIntents(battle) {
      const allies = battle.alive('ally');
      const intents = [];
      if (!allies.length) return intents;
      for (const e of battle.alive('enemy')) {
        if (e.broken) continue; // Quebra pendente: não age nesta rodada
        const ready = e.def.skills.filter(id => battle.skillReady(e, id));
        const attacks = ready.filter(id => SKILLS[id].kind === 'attack');
        const defense = ready.find(id => SKILLS[id].kind === 'defense');
        const ai = e.def.ai || {};
        // pouca vida: às vezes se defende (visível para o jogador)
        if (defense && e.hp / e.maxHp < ai.defendBelow && battle.rand() < 0.5) {
          intents.push({ actorId: e.id, skillId: defense, targetId: e.id });
          continue;
        }
        const scored = allies.map(u => ({ u, s: this.score(battle, e, u, ai.prefers) + battle.rand() * 0.6 }))
          .sort((x, y) => y.s - x.s);
        const target = scored[0].u;
        intents.push({ actorId: e.id, skillId: this.pickSkill(battle, e, target, attacks, ai.prefers), targetId: target.id });
      }
      return this.maybeCombo(battle, intents);
    },

    // Combinação inimiga: só com os dois membros vivos, ambos atacando, sem recarga
    // e com frequência moderada. Substitui as duas ações por uma (sem ação extra).
    maybeCombo(battle, intents) {
      for (const id in G.COMBOS) {
        const c = G.COMBOS[id];
        if (c.side !== 'enemy') continue;
        const lead = battle.unit(c.members[0]);
        const its = c.members.map(m => intents.find(i => i.actorId === m));
        if (its.some(i => !i || SKILLS[i.skillId].kind !== 'attack')) continue;
        if (!battle.skillReady(lead, id) || battle.rand() >= G.AI_COMBO_CHANCE) continue;
        const lead_it = its[0];
        intents = intents.filter(i => !c.members.includes(i.actorId));
        intents.unshift({ actorId: lead.id, skillId: id, targetId: lead_it.targetId, partners: c.members.slice(1) });
      }
      return intents;
    },

    score(battle, e, u, prefers) {
      const ratio = u.hp / u.maxHp;
      const best = Math.max(...e.def.skills.filter(id => SKILLS[id].kind === 'attack' && battle.skillReady(e, id)).map(id => SKILLS[id].dmg), 0);
      const canKill = best >= u.hp ? 1.2 : 0;
      // Postura: chance de Quebra pesa um pouco, conforme a classe (sem caçar sempre o mais frágil)
      const bestP = Math.max(...e.def.skills.filter(id => SKILLS[id].kind === 'attack' && battle.skillReady(e, id)).map(id => SKILLS[id].pressure || 0), 0);
      const breakable = !u.stable && !u.broken && u.post <= bestP ? ({ strong: 0.5, weak: 0.2, threat: 0.25 }[prefers] || 0.2) : 0;
      switch (prefers) {
        case 'strong': // Brutamontes: alvo onde o golpe forte rende mais (quem pode finalizar, ou o mais resistente)
          return canKill + breakable + (u.statuses.block ? -0.5 : 0) + 0.4 * (1 - ratio) + (u.id === 'knight' ? 0.3 : 0);
        case 'weak':   // Duelista: vulneráveis, enfraquecidos, pouca vida
          return canKill + breakable + 1.4 * (1 - ratio) + (u.statuses.weaken ? 0.8 : 0) + (u.maxHp < 50 ? 0.3 : 0);
        case 'threat': // Conjurador: ameaças e quem ainda não foi amaldiçoado
          return (AI_THREAT[u.id] || 0) + breakable + (u.statuses.weaken ? -0.6 : 0.3) + 0.5 * (1 - ratio) + canKill * 0.5;
        default: return 1 - ratio;
      }
    },

    pickSkill(battle, e, target, attacks, prefers) {
      const by = (f) => attacks.slice().sort((a, b) => f(SKILLS[b]) - f(SKILLS[a]))[0];
      // Brutamontes: prefere Pressão quando o alvo está perto de quebrar
      if (prefers === 'strong') {
        if (!target.stable && target.post <= Math.max(...attacks.map(id => SKILLS[id].pressure || 0)) && battle.rand() < 0.6) return by(s => s.pressure || 0);
        return battle.rand() < 0.8 ? by(s => s.dmg) : by(s => s.force);
      }
      if (prefers === 'threat') {
        const curse = attacks.find(id => SKILLS[id].applies === 'weaken');
        if (curse && !target.statuses.weaken && battle.rand() < 0.7) return curse;
        return by(s => s.dmg);
      }
      if (prefers === 'weak') return target.hp <= Math.max(...attacks.map(id => SKILLS[id].dmg)) ? by(s => s.dmg)
        : (battle.rand() < 0.55 ? by(s => s.dmg) : by(s => s.force));
      return attacks[0];
    },
  };

  G.AI = AI;
})(typeof window !== 'undefined' ? window : globalThis);
