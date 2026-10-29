// =====================================================================
// INTERFACE (DOM) — barra compacta. A seleção acontece na arena
// (planner.js); aqui ficam só: dica, ordem prevista, ações e confirmar.
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS } = G;
  const $ = sel => document.querySelector(sel);
  const CAT = { favorable: ['Favorável', '#6fd890'], even: ['Equilibrado', '#ffd36a'], unfavorable: ['Desfavorável', '#ff7a6a'] };

  const UI = {
    CAT,
    setTop(battle, phaseLabel, resolving) {
      $('#round').textContent = `Rodada ${battle.round}`;
      $('#phase').textContent = phaseLabel;
      $('#btn-skip').disabled = !resolving;
      document.body.classList.toggle('resolving', !!resolving);
    },
    setSpeed(s) { document.querySelectorAll('[data-speed]').forEach(b => b.classList.toggle('on', +b.dataset.speed === s)); },
    renderWaiting(text) { $('#panel').innerHTML = `<div class="waiting">${text}</div>`; },

    // view: { choices, plan, preview, complete, hint }
    renderBar(battle, view, onConfirm) {
      const n = id => battle.unit(id).name, sn = id => SKILLS[id].name;
      const who = a => [a.actorId, ...(a.partners || [])].map(n).join(' + ');
      const chips = (view.preview || []).map((ev, i) => {
        let cls = '', txt = '';
        if (ev.type === 'stances') { cls = 'o-def'; txt = '🛡 ' + ev.actions.map(a => SKILLS[a.skillId].kind === 'protect' ? `${n(a.actorId)} protege ${n(a.targetId)}` : `${n(a.actorId)}: ${sn(a.skillId)}`).join(' · '); }
        else if (ev.type === 'support') { cls = 'o-sup'; txt = `${n(ev.a.actorId)} ✚ ${n(ev.a.targetId)}`; }
        else if (ev.type === 'clash') {
          const ally = ev.a.side === 'ally' ? ev.a : ev.b, foe = ally === ev.a ? ev.b : ev.a;
          const c = CAT[battle.category(ally === ev.a ? ev.odds.win : ev.odds.lose)];
          cls = 'o-clash'; txt = `⚔ ${who(ally)} × ${who(foe)} <b style="color:${c[1]}">${c[0]}</b>`;
        } else {
          const a = ev.a, sk = SKILLS[a.skillId];
          cls = a.side === 'enemy' ? 'o-foe' : 'o-ally';
          txt = `${who(a)} → ${n(a.targetId)} <small>${sk.name} · D${sk.dmg}${a.side === 'enemy' ? (UI.defenseNote[a.targetId] ? ' · ' + UI.defenseNote[a.targetId] : ' · sem defesa') : ''}</small>`;
        }
        return `<span class="ochip ${cls}"><i>${i + 1}</i>${txt}</span>`;
      }).join('');
      const done = battle.alive('ally').filter(u => view.choices[u.id]).length; // parceiro de combinação conta
      $('#panel').innerHTML = `<div class="bar-hint">${view.hint}</div><div class="order-strip">${chips}</div>` +
        `<button class="confirm" ${view.complete ? '' : 'disabled'}>Executar rodada ▶ <small>${done}/${battle.alive('ally').length}</small></button>`;
      $('#panel .confirm').onclick = onConfirm;
    },
    defenseNote: {},

    renderEnd(result, onRestart, onTeam) {
      const o = $('#overlay');
      o.innerHTML = `<div class="end ${result}"><h1>${result === 'victory' ? 'VITÓRIA' : 'DERROTA'}</h1><p>${result === 'victory' ? 'Os três inimigos caíram.' : 'Seu grupo foi derrotado.'}</p><div class="row"></div></div>`;
      const row = o.querySelector('.row');
      const b = document.createElement('button'); b.className = 'confirm'; b.textContent = 'Lutar de novo (mesma equipe) ↻';
      b.onclick = onRestart;
      const t = document.createElement('button'); t.className = 'confirm'; t.textContent = 'Trocar equipe 👥';
      t.onclick = onTeam;
      row.append(b, t);
      o.classList.add('show');
    },

    // ------------------------------------------------------------ FORMAÇÃO DA EQUIPE
    // state: { team: [ids], focus: id }; cb: { toggle(id), focus(id), start() }
    renderTeam(state, cb) {
      const roster = $('#roster'), U = G.UNITS;
      const stat = (id, k) => U[id][k] || 0;
      const max = k => Math.max(...G.ROSTER.map(id => stat(id, k)));
      // "resistência" resumida: vida + bloqueio/esquiva
      const res = id => Math.round(stat(id, 'hp') * (1 + (U[id].blockPower || 0) * 0.6 + (U[id].dodgeSkill || 0)));
      const maxRes = Math.max(...G.ROSTER.map(res));
      roster.innerHTML = '';
      for (const id of G.ROSTER) {
        const u = U[id], picked = state.team.includes(id);
        const card = document.createElement('div');
        card.className = 'rcard' + (picked ? ' picked' : '') + (state.focus === id ? ' focus' : '');
        card.innerHTML = `${picked ? `<span class="tagpick">${state.team.indexOf(id) + 1}</span>` : ''}<canvas width="180" height="150"></canvas>
          <b>${u.name}</b><small>${u.role}</small>
          <div class="bars">
            <div class="bar">Vida <i style="--v:${stat(id, 'hp') / max('hp') * 100}%;--c:#5fd08a"></i></div>
            <div class="bar">Vel. <i style="--v:${stat(id, 'spd') / max('spd') * 100}%;--c:#7fd0ff"></i></div>
            <div class="bar">Resist. <i style="--v:${res(id) / maxRes * 100}%;--c:#d8b45a"></i></div>
          </div>`;
        G.drawPortrait(card.querySelector('canvas'), u.art, { glow: picked ? '#4a3a20' : '#3a2a44' });
        card.onclick = () => (state.focus === id ? cb.toggle(id) : cb.focus(id));
        card.ondblclick = () => cb.toggle(id);
        roster.appendChild(card);
      }
      // detalhes do personagem em foco
      const f = U[state.focus];
      const defense = f.skills.map(k => G.SKILLS[k]).find(sk => sk.kind !== 'attack');
      $('#detail').innerHTML = f ? `<h2>${f.name} <small>${f.role}</small></h2><p class="muted">${f.style || ''}</p>
        <div class="muted">Vida <b>${f.hp}</b> · Velocidade <b>${f.spd}</b>${f.blockPower ? ` · Bloqueio ${Math.round(f.blockPower * 100)}%` : ''}${f.dodgeSkill ? ` · Esquiva +${Math.round(f.dodgeSkill * 100)}%` : ''}</div>
        ${f.skills.map(k => G.SKILLS[k]).filter(sk => sk.kind === 'attack').map(sk => `<div class="sk"><em>F${sk.force} · D${sk.dmg}${sk.hits && sk.hits.length > 1 ? ` · ${sk.hits.length} golpes` : ''}</em><span><b>${sk.name}</b> — ${sk.desc}</span></div>`).join('')}
        ${defense ? `<div class="sk"><em>Defesa</em><span><b>${defense.name}</b> — ${defense.desc}</span></div>` : ''}
        <div class="muted">${f.trait}</div>
        <button class="confirm" id="btn-toggle">${state.team.includes(state.focus) ? 'Remover da equipe' : state.team.length >= 3 ? 'Equipe cheia (remova alguém)' : 'Adicionar à equipe'}</button>` : '';
      const tb = $('#btn-toggle');
      if (tb) { tb.disabled = !state.team.includes(state.focus) && state.team.length >= 3; tb.onclick = () => cb.toggle(state.focus); }
      // três espaços da equipe (frente → retaguarda definida pela especialidade)
      const slots = $('#slots'); slots.innerHTML = '';
      for (let i = 0; i < 3; i++) {
        const id = state.team[i], el = document.createElement('div');
        el.className = 'slot' + (id ? ' full' : '');
        el.innerHTML = id ? `<canvas width="40" height="48"></canvas><span><b>${U[id].name}</b><br><small>clique para remover</small></span>` : `Espaço ${i + 1}`;
        if (id) { G.drawPortrait(el.querySelector('canvas'), U[id].art); el.onclick = () => cb.toggle(id); }
        slots.appendChild(el);
      }
      $('#btn-start').disabled = state.team.length !== 3;
      $('#btn-start').onclick = cb.start;
    },
    showTeam(on) { $('#team').classList.toggle('show', on); },
    hideEnd() { $('#overlay').classList.remove('show'); $('#overlay').innerHTML = ''; },
  };

  G.UI = UI;
})(window);
