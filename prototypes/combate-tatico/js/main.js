// =====================================================================
// MÁQUINA DE ESTADOS DA BATALHA — liga lógica, apresentação e interface.
//   PLAN → PLAYER_RESOLVE → ENEMY_INTENT → DEFENSE → ENEMY_RESOLVE → PLAN …
//   (qualquer resolução pode ir para END)
// =====================================================================
(function (G) {
  'use strict';
  const { Battle, Presenter, UI } = G;
  const presenter = new Presenter(document.getElementById('stage'));
  let battle, plan, intents, choices, gen = 0;

  const Phase = {
    PLAN: 'PLAN', PLAYER_RESOLVE: 'PLAYER_RESOLVE', ENEMY_INTENT: 'ENEMY_INTENT',
    DEFENSE: 'DEFENSE', ENEMY_RESOLVE: 'ENEMY_RESOLVE', END: 'END',
  };
  const fsm = {
    state: null,
    go(s, data) { this.state = s; enter[s](data); },
  };

  const enter = {
    PLAN() {
      plan = { plans: {}, active: null, hint: '', order: [], complete: false };
      const first = battle.alive('ally')[0];
      plan.active = first && first.id;
      presenter.showBanner(`RODADA ${battle.round}`, '#7fd0ff', 900, 'sua ofensiva');
      refreshPlan();
    },

    async PLAYER_RESOLVE() {
      UI.setTop(battle, 'Sua ofensiva — resolução', true);
      UI.renderWaiting('Confrontos em andamento…');
      presenter.highlight = null;
      const plans = Object.entries(plan.plans).map(([attackerId, p]) => ({ attackerId, ...p }));
      const results = battle.resolvePlayerPhase(plans); // resultado já decidido aqui
      const g = gen;
      await presenter.playAll(results);
      if (g !== gen) return; // batalha reiniciada no meio
      const out = battle.outcome();
      fsm.go(out ? Phase.END : Phase.ENEMY_INTENT, out);
    },

    async ENEMY_INTENT() {
      UI.setTop(battle, 'Ofensiva inimiga — intenções', false);
      UI.renderWaiting('Os inimigos preparam seus ataques…');
      intents = battle.planEnemyIntents();
      intents.forEach((it, i) => { it.order = i + 1; });
      presenter.showBanner('OFENSIVA INIMIGA', '#ff6a5a', 900, 'observe as intenções');
      const g = gen;
      await presenter.wait(700);
      await presenter.announceIntents(intents, battle);
      if (g !== gen) return;
      fsm.go(Phase.DEFENSE);
    },

    DEFENSE() {
      choices = {};
      intents.forEach((it, i) => {
        const a = battle.unit(it.attackerId), t = battle.unit(it.targetId);
        choices[i] = { reaction: battle.defaultReaction(t, a, G.SKILLS[it.skillId]), protect: false };
      });
      refreshDefense();
    },

    async ENEMY_RESOLVE() {
      UI.setTop(battle, 'Ofensiva inimiga — resolução', true);
      UI.renderWaiting('Defendendo…');
      const results = battle.resolveEnemyPhase(intents, choices);
      const g = gen;
      await presenter.playAll(results);
      if (g !== gen) return;
      const out = battle.outcome();
      if (out) return fsm.go(Phase.END, out);
      battle.endRound();
      fsm.go(Phase.PLAN);
    },

    END(result) {
      UI.setTop(battle, result === 'victory' ? 'Vitória' : 'Derrota', false);
      UI.renderWaiting('');
      UI.renderEnd(result, start);
    },
  };

  // ------------------------------------------------------------ planejamento
  function refreshPlan() {
    const allies = battle.alive('ally');
    const done = allies.filter(u => plan.plans[u.id] && plan.plans[u.id].skillId && plan.plans[u.id].targetId);
    plan.complete = done.length === allies.length;
    plan.order = battle.orderBySpeed(done.map(u => ({ attackerId: u.id, ...plan.plans[u.id] })));
    presenter.plans = plan.order.map((p, i) => ({ ...p, order: i + 1 }));
    const act = plan.active && plan.plans[plan.active];
    presenter.highlight = new Set(act && act.skillId ? battle.alive('enemy').map(e => e.id) : (plan.active ? [plan.active] : []));
    UI.setTop(battle, 'Sua ofensiva — planejamento', false);
    UI.renderPlan(battle, plan, planCb);
  }
  const planCb = {
    activate(id) { plan.active = id; refreshPlan(); },
    pickSkill(uid, sid) {
      plan.active = uid;
      const p = plan.plans[uid] = plan.plans[uid] || {};
      p.skillId = sid;
      plan.hint = `<b>${G.SKILLS[sid].name}</b> — ${G.SKILLS[sid].desc}<br><i>Escolha um alvo.</i>`;
      refreshPlan();
    },
    pickTarget(uid, tid) {
      const p = plan.plans[uid];
      if (!p || !p.skillId) return;
      p.targetId = tid;
      // avança para o próximo personagem sem plano
      const next = battle.alive('ally').find(u => !(plan.plans[u.id] && plan.plans[u.id].targetId));
      plan.active = next ? next.id : uid;
      plan.hint = '';
      refreshPlan();
    },
    hint(h) { UI.hint(h); },
    confirm() { if (plan.complete) fsm.go(Phase.PLAYER_RESOLVE); },
  };

  // ------------------------------------------------------------ defesa
  function refreshDefense() {
    UI.setTop(battle, 'Ofensiva inimiga — escolha suas defesas', false);
    presenter.intents = intents.map((it, i) => ({ ...it, protect: choices[i].protect }));
    UI.renderDefense(battle, intents, choices, defCb);
  }
  const defCb = {
    pickReaction(i, kind) { choices[i].reaction = kind; refreshDefense(); },
    toggleProtect(i) {
      const on = !choices[i].protect;
      for (const k in choices) choices[k].protect = false;
      choices[i].protect = on;
      refreshDefense();
    },
    confirm() { fsm.go(Phase.ENEMY_RESOLVE); },
  };

  // ------------------------------------------------------------ entrada
  document.getElementById('stage').addEventListener('click', ev => {
    if (fsm.state !== Phase.PLAN) return;
    const r = ev.currentTarget.getBoundingClientRect();
    const id = presenter.pick(ev.clientX - r.left, ev.clientY - r.top);
    if (!id) return;
    const u = battle.unit(id);
    if (u.side === 'ally') planCb.activate(id);
    else if (plan.active) {
      const p = plan.plans[plan.active];
      if (p && p.skillId) planCb.pickTarget(plan.active, id);
    }
  });
  document.querySelectorAll('[data-speed]').forEach(b => b.onclick = () => {
    presenter.speed = +b.dataset.speed; UI.setSpeed(presenter.speed);
  });
  document.getElementById('btn-skip').onclick = () => presenter.skip();
  document.getElementById('btn-restart').onclick = () => { if (confirm('Reiniciar a batalha?')) start(); };
  document.getElementById('btn-help').onclick = () => document.getElementById('help').classList.toggle('show');
  document.getElementById('help').onclick = () => document.getElementById('help').classList.remove('show');
  window.addEventListener('keydown', e => {
    if (e.key === ' ' && !document.getElementById('btn-skip').disabled) { e.preventDefault(); presenter.skip(); }
  });

  function start() {
    gen++;
    presenter.skip(); presenter.skipping = false;
    UI.hideEnd();
    const seed = (Date.now() ^ (Math.random() * 1e9)) >>> 0;
    battle = new Battle(seed);
    presenter.reset(battle);
    fsm.go(Phase.PLAN);
  }
  UI.setSpeed(1);
  start();
  G.debug = { get battle() { return battle; }, presenter, fsm };
})(window);
