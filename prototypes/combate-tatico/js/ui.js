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
      // FICHA do personagem em foco (retrato, atributos, habilidades, especialidade, prévia animada)
      const f = U[state.focus];
      const det = $('#detail');
      if (f) {
        const sks = f.skills.map(k => [k, G.SKILLS[k]]);
        const fx = sk => [sk.applies === 'weaken' ? 'enfraquece' : '', sk.impact === 'knockdown' ? 'derruba' : sk.impact === 'stagger' ? 'desequilibra' : sk.impact === 'push' ? 'empurra' : '',
          sk.unblockable ? 'ignora bloqueio' : '', sk.tags.includes('magic') ? 'magia' : sk.tags.includes('ranged') ? 'à distância' : '', sk.cooldown ? `recarga ${sk.cooldown - 1}` : ''].filter(Boolean).join(' · ');
        const chip = (lbl, v, cls = '') => `<span class="chipv ${cls}"><i>${lbl}</i>${v}</span>`;
        const row = ([k, sk]) => `<div class="skrow" data-skill="${k}" tabindex="0">
            <canvas class="skico" width="44" height="44" data-icon="${sk.icon}" data-kind="${sk.kind}"></canvas>
            <div class="skbody"><b>${sk.name}</b><span>${sk.desc}</span>
              <div class="chips">${sk.kind === 'attack' ? chip('Força', sk.force) + chip('Dano', sk.dmg) + chip('Pressão', sk.pressure || 0, 'p') + chip('Golpes', (sk.hits || [1]).length) : chip(sk.kind === 'support' ? 'Suporte' : 'Defesa', ' ')}${sk.postureHeal ? chip('Postura', '+' + sk.postureHeal, 'p') : ''}${fx(sk) ? `<em>${fx(sk)}</em>` : ''}</div></div></div>`;
        det.innerHTML = `<div class="sheet" style="--acc:${f.accent || '#d8b45a'}">
          <div class="sheet-head"><canvas class="sheet-portrait" width="150" height="170"></canvas>
            <div class="sheet-title"><canvas class="sheet-glyph" width="70" height="70"></canvas><h2>${f.name}</h2><div class="cls">${f.role} · ${f.specialty || ''}</div><p>${f.style || ''}</p></div></div>
          <div class="stats">
            <div class="tile"><i>Vida</i><b>${f.hp}</b></div><div class="tile"><i>Postura</i><b>${f.posture}</b></div><div class="tile"><i>Velocidade</i><b>${f.spd}</b></div>
            <div class="tile wide"><i>Ataque</i><span>${f.offense || ''}</span></div><div class="tile wide"><i>Defesa</i><span>${f.defense || ''}</span></div>
          </div>
          <div class="sh">Habilidades</div>
          <div class="sklist">${sks.filter(([, sk]) => sk.kind === 'attack').map(row).join('')}</div>
          <div class="sh">Especialidade · ${f.specialty || ''}</div>
          <div class="sklist">${sks.filter(([, sk]) => sk.kind !== 'attack').map(row).join('')}</div>
          <div class="sh">Prévia <small>passe o mouse ou clique numa habilidade</small></div>
          <div id="pv-slot" class="pv-slot"></div>
          <button class="confirm" id="btn-toggle">${state.team.includes(state.focus) ? 'Remover da equipe' : state.team.length >= 3 ? 'Equipe cheia (remova alguém)' : 'Adicionar à equipe'}</button></div>`;
        G.drawPortrait(det.querySelector('.sheet-portrait'), f.art, { glow: f.accent ? f.accent + '55' : '#3a2a44' });
        const gl = det.querySelector('.sheet-glyph'); G.drawIcon(gl.getContext('2d'), f.glyph || 'sword', 35, 35, 26, (f.accent || '#d8b45a') + '55');
        det.querySelectorAll('.skico').forEach(c => { const g = c.getContext('2d'); g.fillStyle = '#140c14'; g.beginPath(); g.arc(22, 22, 20, 0, 7); g.fill(); g.strokeStyle = f.accent || '#d8b45a'; g.lineWidth = 2; g.stroke(); G.drawIcon(g, c.dataset.icon, 22, 22, 13, f.accent || '#d8b45a'); });
        // prévia: hover, foco (teclado) ou clique/toque
        if (cb.preview) {
          cb.preview.mount(det.querySelector('#pv-slot'));
          det.querySelectorAll('.skrow').forEach(r => {
            const go = () => { det.querySelectorAll('.skrow').forEach(x => x.classList.toggle('on', x === r)); cb.preview.play(state.focus, r.dataset.skill); };
            r.onmouseenter = go; r.onfocus = go; r.onclick = go;
          });
          const first = det.querySelector('.skrow');
          if (first && !G.reduceMotion) { first.classList.add('on'); cb.preview.play(state.focus, first.dataset.skill); }
        }
      } else det.innerHTML = '';
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
