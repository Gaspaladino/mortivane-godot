// =====================================================================
// MÁQUINA DE ESTADOS — rodadas compartilhadas:
//   INTENTS (IA decide e anuncia) → PLAN (planejamento na arena) →
//   RESOLVE (fila de eventos) → INTENTS … | END
// =====================================================================
(function (G) {
  'use strict';
  const { Battle, Presenter, Planner, UI, SKILLS } = G;
  const presenter = new Presenter(document.getElementById('stage'));
  let battle, view = { choices: {}, plan: null, preview: [], complete: false, hint: '' }, gen = 0, firstAction = true;

  const planner = new Planner(presenter, {
    battle: () => battle,
    choices: () => view.choices,
    plan: () => view.plan,
    preview: () => view.preview,
    commit(uid, skillId, targetId) {
      const sk = SKILLS[skillId];
      // trocar a ação de quem estava numa combinação desfaz a combinação inteira
      dropCombo(uid);
      if (sk.combo) {
        // combinação: registrada no líder, consome a ação de todos os membros
        sk.members.forEach(m => dropCombo(m));
        uid = sk.members[0];
        sk.members.slice(1).forEach(m => { view.choices[m] = { comboWith: uid }; });
      }
      const prev = view.choices[uid];
      view.choices[uid] = { skillId, targetId, intercept: prev && prev.targetId === targetId ? prev.intercept : true };
      // interceptação ligada por padrão só quando for válida
      const a = battle.buildPlan(view.choices).actions.find(x => x.actorId === uid);
      if (!(a && a.interceptInfo && a.interceptInfo.valid)) view.choices[uid].intercept = false;
      firstAction = false;
      refreshPlan();
    },
    cancel(uid) { dropCombo(uid); delete view.choices[uid]; refreshPlan(); },
    toggleIntercept(uid) { const c = view.choices[uid]; if (c) { c.intercept = !c.intercept; refreshPlan(); } },
  });

  // Remove uma combinação que envolva este personagem (libera todos os membros).
  function dropCombo(uid) {
    const c = view.choices[uid];
    const lead = c && (c.comboWith || (SKILLS[c.skillId] && SKILLS[c.skillId].combo ? uid : null));
    if (!lead) return;
    const sk = SKILLS[(view.choices[lead] || {}).skillId];
    for (const m of (sk && sk.combo ? sk.members : [lead, uid])) delete view.choices[m];
  }

  // ------------------------------------------------------------ formação da equipe
  let team = loadTeam();
  function loadTeam() {
    try { const t = JSON.parse(localStorage.getItem('duelo-team') || 'null'); if (Array.isArray(t) && t.length === 3 && t.every(id => G.ROSTER.includes(id))) return t; } catch (e) { /* ok */ }
    return G.PARTY.slice();
  }
  const teamState = { team: team.slice(), focus: team[0] };
  const preview = new G.SkillPreview();
  const teamCb = {
    preview,
    focus(id) { teamState.focus = id; G.SFX.play('uiSelect'); UI.renderTeam(teamState, teamCb); },
    toggle(id) {
      const i = teamState.team.indexOf(id);
      if (i >= 0) teamState.team.splice(i, 1);                 // remover
      else if (teamState.team.length < 3) teamState.team.push(id); // sem duplicatas, máximo 3
      teamState.focus = id;
      G.SFX.play(i >= 0 ? 'uiCancel' : 'uiConnect');
      UI.renderTeam(teamState, teamCb);
    },
    start() {
      if (teamState.team.length !== 3) return;
      // ordem em campo: frente → retaguarda pela especialidade (Cavaleiro/Lutador na frente, Mago/Arqueira atrás)
      team = teamState.team.slice().sort((a, b) => (G.UNITS[a].formation || 0) - (G.UNITS[b].formation || 0));
      try { localStorage.setItem('duelo-team', JSON.stringify(teamState.team)); } catch (e) { /* ok */ }
      G.SFX.play('uiConfirm');
      preview.pause();
      UI.showTeam(false);
      start();
    },
  };
  function openTeam() {
    gen++;
    presenter.skip(); presenter.skipping = false; presenter.ambient = false;
    planner.setEnabled(false);
    UI.hideEnd();
    teamState.team = team.slice(); teamState.focus = teamState.team[0] || G.ROSTER[0];
    fsm.state = 'TEAM';
    UI.renderTeam(teamState, teamCb);
    UI.showTeam(true);
  }

  const Phase = { INTENTS: 'INTENTS', PLAN: 'PLAN', RESOLVE: 'RESOLVE', END: 'END' };
  const fsm = { state: null, go(s, data) { this.state = s; enter[s](data); } };

  const enter = {
    async INTENTS() {
      const g = gen;
      UI.setTop(battle, 'Preparação inimiga', true);
      UI.renderWaiting('Os inimigos escolhem suas ações…');
      view = { choices: {}, plan: null, preview: [], complete: false, hint: '' };
      battle.planEnemyIntents(); // fixas para toda a rodada
      const attacks = battle.intents.filter(i => SKILLS[i.skillId].kind === 'attack');
      presenter.threatened = new Set(attacks.map(i => i.targetId));
      for (const id in presenter.vis) presenter.vis[id].threat = null;
      attacks.forEach(i => { presenter.vis[i.targetId].threat = i.actorId; });
      planner.showIntents = true;
      presenter.showBanner(`RODADA ${battle.round}`, '#ff8a6a', 900, 'os inimigos revelam suas intenções');
      await presenter.wait(450);
      await presenter.announceIntents(battle.intents);
      if (g !== gen) return;
      presenter.skipping = false;
      fsm.go(Phase.PLAN);
    },

    PLAN() {
      presenter.ambient = true; // pequenos reposicionamentos naturais durante o planejamento
      planner.setEnabled(true);
      refreshPlan();
    },

    async RESOLVE() {
      const g = gen;
      planner.setEnabled(false);
      presenter.ambient = false;
      G.SFX.play('uiConfirm');
      UI.setTop(battle, 'Execução da rodada', true);
      UI.renderWaiting('Confrontos em andamento…  <small>(Espaço pula)</small>');
      presenter.threatened = null;
      for (const id in presenter.vis) presenter.vis[id].threat = null;
      const plan = battle.buildPlan(view.choices);       // validação final
      const events = battle.resolveRound(plan);          // tudo decidido aqui
      await presenter.playAll(events);
      if (g !== gen) return;
      planner.showIntents = false;
      const out = battle.outcome();
      if (out) return fsm.go(Phase.END, out);
      battle.endRound();
      presenter.endRound(battle.snapshot());
      fsm.go(Phase.INTENTS);
    },

    END(result) {
      presenter.ambient = false;
      UI.setTop(battle, result === 'victory' ? 'Vitória' : 'Derrota', false);
      UI.renderWaiting('');
      UI.renderEnd(result, start, openTeam);
    },
  };

  function refreshPlan() {
    const allies = battle.alive('ally');
    view.plan = battle.buildPlan(view.choices);
    view.preview = battle.previewPlan(view.plan);
    // completo: todo aliado vivo tem ação própria OU participa de uma combinação válida
    // (quem está com Quebra pendente não planeja: perde a ação desta rodada)
    view.complete = allies.every(u => u.broken || view.plan.actions.some(a => a.actorId === u.id || (a.partners || []).includes(u.id)));
    // posturas defensivas preparadas aparecem já no planejamento
    for (const u of allies) {
      const c = view.choices[u.id], sk = c && c.skillId && SKILLS[c.skillId];
      presenter.setPrepStance(u.id, sk && sk.kind === 'defense' ? sk.reaction : sk && sk.kind === 'protect' ? 'block' : null);
    }
    const note = {};
    for (const a of view.plan.actions.filter(x => x.side === 'ally')) {
      const sk = SKILLS[a.skillId];
      if (sk.kind === 'protect') note[a.targetId] = `${battle.unit(a.actorId).name} protege`;
      else if (sk.kind === 'defense') note[a.actorId] = note[a.actorId] || G.REACTIONS[sk.reaction].name;
    }
    UI.defenseNote = note;
    const lost = allies.filter(u => u.broken).map(u => u.name);
    view.hint = (lost.length ? `<b style="color:#ffd36a">${lost.join(' e ')} perde${lost.length > 1 ? 'm' : ''} a ação (Quebra de Postura).</b> ` : '') + (firstAction ? '<b>Selecione um personagem e conecte uma habilidade ao alvo.</b> <small>(clique ou arraste · botão direito/✕ cancela · Esc desfaz)</small>'
      : view.complete ? 'Tudo pronto. Passe o mouse nas correntes para ver os Clashes.' : 'Planeje os personagens restantes.');
    UI.setTop(battle, 'Planejamento', false);
    UI.renderBar(battle, view, () => { if (view.complete && fsm.state === Phase.PLAN) fsm.go(Phase.RESOLVE); });
  }

  document.querySelectorAll('[data-speed]').forEach(b => b.onclick = () => { presenter.speed = +b.dataset.speed; UI.setSpeed(presenter.speed); });
  document.getElementById('btn-skip').onclick = () => presenter.skip();
  document.getElementById('btn-restart').onclick = () => { if (confirm('Reiniciar a batalha?')) start(); };
  document.getElementById('btn-help').onclick = () => document.getElementById('help').classList.toggle('show');
  document.getElementById('help').onclick = () => document.getElementById('help').classList.remove('show');
  window.addEventListener('keydown', e => {
    if (e.key === ' ' && (fsm.state === Phase.RESOLVE || fsm.state === Phase.INTENTS)) { e.preventDefault(); presenter.skip(); }
    if (e.key === 'Enter' && fsm.state === Phase.PLAN && view.complete) fsm.go(Phase.RESOLVE);
  });

  function start() {
    gen++;
    presenter.skip(); presenter.skipping = false;
    planner.setEnabled(false);
    UI.hideEnd();
    // ?seed=123 repete a mesma batalha (útil para testes)
    const fixed = +new URLSearchParams(location.search).get('seed');
    team = team.slice().sort((a, b) => (G.UNITS[a].formation || 0) - (G.UNITS[b].formation || 0));
    battle = new Battle(fixed || ((Date.now() ^ (Math.random() * 1e9)) >>> 0), team);
    presenter.reset(battle);
    fsm.go(Phase.INTENTS);
  }
  // ------------------------------------------------------------ áudio (volume geral, efeitos, silenciar)
  const A = G.SFX.settings;
  document.getElementById('vol-master').value = A.master; document.getElementById('vol-sfx').value = A.sfx; document.getElementById('vol-mute').checked = A.muted;
  document.getElementById('vol-master').oninput = e => G.SFX.set('master', +e.target.value);
  document.getElementById('vol-sfx').oninput = e => { G.SFX.set('sfx', +e.target.value); G.SFX.play('uiSkill'); };
  document.getElementById('vol-mute').onchange = e => { G.SFX.set('muted', e.target.checked); document.getElementById('btn-audio').textContent = e.target.checked ? '🔇' : '🔊'; };
  document.getElementById('btn-audio').textContent = A.muted ? '🔇' : '🔊';
  // reduzir animações: prévias não repetem, menos tremor, sem câmera lenta
  try { G.reduceMotion = localStorage.getItem('duelo-reduce') === '1'; } catch (e) { /* ok */ }
  document.getElementById('vol-reduce').checked = !!G.reduceMotion;
  document.getElementById('vol-reduce').onchange = e => { G.reduceMotion = e.target.checked; try { localStorage.setItem('duelo-reduce', e.target.checked ? '1' : '0'); } catch (er) { /* ok */ } };
  document.getElementById('btn-audio').onclick = () => document.getElementById('audio-pop').classList.toggle('show');
  document.getElementById('btn-team').onclick = () => { if (fsm.state === 'TEAM' || confirm('Voltar para a formação de equipe? A batalha atual será encerrada.')) openTeam(); };

  UI.setSpeed(1);
  // ?seed=… vai direto para a batalha (testes); senão começa pela formação
  if (new URLSearchParams(location.search).get('seed')) start(); else { battle = new Battle(1, team); presenter.reset(battle); openTeam(); }
  G.debug = { get battle() { return battle; }, presenter, planner, fsm, get view() { return view; }, teamCb, teamState };
})(window);
