// =====================================================================
// MÁQUINA DE ESTADOS — rodadas compartilhadas:
//   INTENTS (IA decide e anuncia) → PLAN (jogador + prévia) →
//   RESOLVE (fila de eventos) → INTENTS … | END
// =====================================================================
(function (G) {
  'use strict';
  const { Battle, Presenter, UI, SKILLS } = G;
  const presenter = new Presenter(document.getElementById('stage'));
  let battle, view, gen = 0;

  const Phase = { INTENTS: 'INTENTS', PLAN: 'PLAN', RESOLVE: 'RESOLVE', END: 'END' };
  const fsm = { state: null, go(s, data) { this.state = s; enter[s](data); } };

  const enter = {
    async INTENTS() {
      const g = gen;
      UI.setTop(battle, 'Preparação inimiga', true);
      UI.renderWaiting('Os inimigos escolhem suas ações…');
      battle.planEnemyIntents(); // fixas para toda a rodada
      presenter.threatened = new Set(battle.intents.filter(i => SKILLS[i.skillId].kind === 'attack').map(i => i.targetId));
      presenter.overlay = intentOverlay(null);
      presenter.showBanner(`RODADA ${battle.round}`, '#ff8a6a', 900, 'os inimigos revelam suas intenções');
      await presenter.wait(500);
      await presenter.announceIntents(battle.intents);
      if (g !== gen) return;
      presenter.skipping = false;
      fsm.go(Phase.PLAN);
    },

    PLAN() {
      view = { choices: {}, active: null, hint: '', plan: null, preview: [], complete: false };
      const first = battle.alive('ally')[0];
      view.active = first && first.id;
      refreshPlan();
    },

    async RESOLVE() {
      const g = gen;
      UI.setTop(battle, 'Execução da rodada', true);
      UI.renderWaiting('Confrontos em andamento…');
      presenter.highlight = null;
      const plan = battle.buildPlan(view.choices);       // validação final
      const events = battle.resolveRound(plan);          // tudo decidido aqui
      await presenter.playAll(events);
      if (g !== gen) return;
      const out = battle.outcome();
      if (out) return fsm.go(Phase.END, out);
      battle.endRound();
      presenter.endRound(battle.snapshot());
      fsm.go(Phase.INTENTS);
    },

    END(result) {
      UI.setTop(battle, result === 'victory' ? 'Vitória' : 'Derrota', false);
      UI.renderWaiting('');
      UI.renderEnd(result, start);
    },
  };

  // ------------------------------------------------------------ overlay
  function intentOverlay(plan) {
    const items = [];
    const linked = id => plan && plan.links[id];
    battle.intents.forEach(it => {
      const sk = SKILLS[it.skillId];
      if (battle.unit(it.actorId).hp <= 0) return;
      if (sk.kind !== 'attack') { items.push({ from: it.actorId, style: 'badge', label: '🛡 ' + sk.name, color: '#ff8a6a' }); return; }
      const l = linked(it.id);
      if (l && l.type === 'direct') return; // vira a linha de Clash
      items.push({ from: it.actorId, to: it.targetId, style: 'dashed', color: '#ff5a5a', label: `${sk.name} F${sk.force} D${sk.dmg}`, lift: 20 + battle.unit(it.actorId).slot * 30 });
    });
    return items;
  }
  function planOverlay(plan, preview) {
    const items = intentOverlay(plan);
    const orderOf = {};
    preview.forEach((ev, i) => { [ev.a, ev.b].forEach(x => { if (x) orderOf[x.id] = i + 1; }); (ev.actions || []).forEach(x => { orderOf[x.id] = i + 1; }); });
    for (const ev of preview) {
      if (ev.type === 'clash') {
        const ally = ev.a.side === 'ally' ? ev.a : ev.b, foe = ally === ev.a ? ev.b : ev.a;
        const cat = battle.category(ally === ev.a ? ev.odds.win : ev.odds.lose);
        items.push({ from: ally.actorId, to: foe.actorId, style: 'clash', color: UI.CAT[cat][1],
          label: `⚔ ${ev.link.type === 'intercept' ? 'Intercepta' : 'Clash'} · ${UI.CAT[cat][0]}`, order: orderOf[ally.id] });
      }
    }
    for (const a of plan.actions.filter(x => x.side === 'ally')) {
      if (plan.links[a.id]) continue;
      const sk = SKILLS[a.skillId];
      if (sk.kind === 'defense') items.push({ from: a.actorId, style: 'badge', label: `${orderOf[a.id]}. 🛡 ${sk.name}`, color: '#7fd0ff' });
      else items.push({ from: a.actorId, to: a.targetId, style: 'arrow', order: orderOf[a.id],
        color: sk.kind === 'support' ? '#7fe0a0' : sk.kind === 'protect' ? '#9fd0ff' : '#7fd0ff', label: sk.name });
    }
    return items;
  }

  // ------------------------------------------------------------ planejamento
  function refreshPlan() {
    const allies = battle.alive('ally');
    view.plan = battle.buildPlan(view.choices);
    view.preview = battle.previewPlan(view.plan);
    view.complete = allies.every(u => view.plan.actions.some(a => a.actorId === u.id));
    // anotações de defesa para a lista de ordem
    const note = {};
    for (const a of view.plan.actions.filter(x => x.side === 'ally')) {
      const sk = SKILLS[a.skillId];
      if (sk.kind === 'protect') note[a.targetId] = `${battle.unit(a.actorId).name} protege`;
      else if (sk.kind === 'defense') note[a.actorId] = note[a.actorId] || G.REACTIONS[sk.reaction].name;
    }
    UI._defenseNote = note;
    presenter.overlay = planOverlay(view.plan, view.preview);
    const ch = view.active && view.choices[view.active];
    const sk = ch && ch.skillId && SKILLS[ch.skillId];
    presenter.highlight = new Set(!sk ? [view.active].filter(Boolean)
      : sk.kind === 'attack' ? battle.alive('enemy').map(e => e.id)
      : sk.kind === 'defense' ? [] : battle.alive('ally').filter(u => u.id !== view.active).map(u => u.id));
    UI.setTop(battle, 'Planejamento — escolha as ações', false);
    UI.renderPlan(battle, view, planCb);
  }
  const planCb = {
    activate(id) { view.active = id; refreshPlan(); },
    pickSkill(uid, sid) {
      view.active = uid;
      const prev = view.choices[uid] || {};
      const sk = SKILLS[sid];
      // mantém o alvo se continuar válido para o novo tipo de habilidade
      const keep = prev.targetId && SKILLS[prev.skillId] && SKILLS[prev.skillId].kind === 'attack' && sk.kind === 'attack';
      view.choices[uid] = { skillId: sid, targetId: keep ? prev.targetId : null, intercept: keep ? prev.intercept : false };
      if (sk.kind === 'defense') view.choices[uid].targetId = uid;
      view.hint = `<b>${sk.name}</b> — ${sk.desc}` + (sk.kind === 'defense' ? '' : '<br><i>Escolha um alvo.</i>');
      if (sk.kind === 'defense') nextActive(uid);
      refreshPlan();
    },
    pickTarget(uid, tid) {
      const c = view.choices[uid];
      if (!c || !c.skillId) return;
      c.targetId = tid; c.intercept = false;
      // interceptar por padrão quando for válido (o jogador pode desligar)
      const a = battle.buildPlan(view.choices).actions.find(x => x.actorId === uid);
      if (a && a.interceptInfo && a.interceptInfo.valid) c.intercept = true;
      view.hint = '';
      nextActive(uid);
      refreshPlan();
    },
    toggleIntercept(uid) { const c = view.choices[uid]; if (c) c.intercept = !c.intercept; refreshPlan(); },
    hint(h) { UI.hint(h); },
    confirm() { if (view.complete) fsm.go(Phase.RESOLVE); },
  };
  function nextActive(uid) {
    const pending = battle.alive('ally').find(u => !(view.choices[u.id] && view.choices[u.id].targetId));
    view.active = pending ? pending.id : uid;
  }

  // ------------------------------------------------------------ entrada
  document.getElementById('stage').addEventListener('click', ev => {
    if (fsm.state !== Phase.PLAN) return;
    const r = ev.currentTarget.getBoundingClientRect();
    const id = presenter.pick(ev.clientX - r.left, ev.clientY - r.top);
    if (!id) return;
    const u = battle.unit(id);
    const c = view.active && view.choices[view.active];
    const sk = c && c.skillId && SKILLS[c.skillId];
    if (sk && ((sk.kind === 'attack' && u.side === 'enemy') || ((sk.kind === 'support' || sk.kind === 'protect') && u.side === 'ally' && id !== view.active)))
      planCb.pickTarget(view.active, id);
    else if (u.side === 'ally') planCb.activate(id);
  });
  document.querySelectorAll('[data-speed]').forEach(b => b.onclick = () => { presenter.speed = +b.dataset.speed; UI.setSpeed(presenter.speed); });
  document.getElementById('btn-skip').onclick = () => presenter.skip();
  document.getElementById('btn-restart').onclick = () => { if (confirm('Reiniciar a batalha?')) start(); };
  document.getElementById('btn-help').onclick = () => document.getElementById('help').classList.toggle('show');
  document.getElementById('help').onclick = () => document.getElementById('help').classList.remove('show');
  window.addEventListener('keydown', e => {
    if (e.key === ' ' && (fsm.state === Phase.RESOLVE || fsm.state === Phase.INTENTS)) { e.preventDefault(); presenter.skip(); }
  });

  function start() {
    gen++;
    presenter.skip(); presenter.skipping = false;
    UI.hideEnd();
    battle = new Battle((Date.now() ^ (Math.random() * 1e9)) >>> 0);
    presenter.reset(battle);
    fsm.go(Phase.INTENTS);
  }
  UI.setSpeed(1);
  start();
  G.debug = { get battle() { return battle; }, presenter, fsm, get view() { return view; } };
})(window);
