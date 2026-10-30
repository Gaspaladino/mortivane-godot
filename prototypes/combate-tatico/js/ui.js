// =====================================================================
// INTERFACE (DOM) — barra compacta. A seleção acontece na arena
// (planner.js); aqui ficam só: dica, ordem prevista, ações e confirmar.
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS } = G;
  const $ = sel => document.querySelector(sel);
  const CAT = { favorable: ['Favorável', '#6fd890'], even: ['Equilibrado', '#ffd36a'], unfavorable: ['Desfavorável', '#ff7a6a'], certain: ['Vitória certa', '#7fffb0'], doomed: ['Derrota certa', '#ff5050'] };

  const UI = {
    CAT,
    setTop(battle, phaseLabel, resolving) {
      $('#round').textContent = `R${battle.round}`;
      $('#phase').textContent = phaseLabel;
      $('#btn-skip').disabled = !resolving;
      document.body.classList.toggle('resolving', !!resolving);
    },
    setSpeed(s) { document.querySelectorAll('[data-speed]').forEach(b => b.classList.toggle('on', +b.dataset.speed === s)); },
    renderWaiting() { $('#panel').innerHTML = ''; }, // BattleActionButtonsUI: fora do planejamento, nada na parte inferior

    // view: { choices, plan, preview, complete, hint }
    renderBar(battle, view, onConfirm, onAuto) {
      const n = id => battle.unit(id).name, sn = id => SKILLS[id].name;
      const who = a => [a.actorId, ...(a.partners || [])].map(n).join(' + ');
      const chips = (view.preview || []).map((ev, i) => {
        let cls = '', txt = '';
        if (ev.type === 'stances') { cls = 'o-def'; txt = '🛡 ' + ev.actions.map(a => SKILLS[a.skillId].kind === 'protect' ? `${n(a.actorId)} protege ${n(a.targetId)}` : `${n(a.actorId)}: ${sn(a.skillId)}`).join(' · '); }
        else if (ev.type === 'support') { cls = 'o-sup'; txt = `${n(ev.a.actorId)} ✚ ${n(ev.a.targetId)}`; }
        else if (ev.type === 'clash') {
          const ally = ev.a.side === 'ally' ? ev.a : ev.b, foe = ally === ev.a ? ev.b : ev.a;
          const o = ally === ev.a ? ev.odds : { win: ev.odds.lose, tie: ev.odds.tie, lose: ev.odds.win };
          const c = CAT[battle.category(o.win, o)];
          cls = 'o-clash'; txt = `⚔ ${who(ally)} × ${who(foe)} <b style="color:${c[1]}">${c[0]}</b>`;
        } else {
          const a = ev.a, sk = SKILLS[a.skillId];
          cls = a.side === 'enemy' ? 'o-foe' : 'o-ally';
          txt = `${who(a)} → ${n(a.targetId)} <small>${sk.name} · D${sk.dmg}${a.side === 'enemy' ? (UI.defenseNote[a.targetId] ? ' · ' + UI.defenseNote[a.targetId] : ' · sem defesa') : ''}</small>`;
        }
        return `<span class="ochip ${cls}"><i>${i + 1}</i>${txt}</span>`;
      }).join('');
      const done = battle.alive('ally').filter(u => view.choices[u.id]).length; // parceiro de combinação conta
      $('#panel').innerHTML = `<button class="auto" title="Escolher ações automaticamente (você pode editar)">AUTO</button><button class="confirm" ${view.complete ? '' : 'disabled'}>Executar ▶ <small>${done}/${battle.alive('ally').length}</small></button>`;
      $('#panel .confirm').onclick = onConfirm;
      $('#panel .auto').onclick = onAuto;
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

    // ------------------------------------------------------------ FORMAÇÃO DA EQUIPE (uma tela, sem rolagem)
    // state: { team: [ids], focus: id, skill: id }; cb: { toggle(id), focus(id), start(), preview, pickSkill(id) }
    elemTag(el, small) {
      const e = G.ELEMENTS[el]; if (!e) return '';
      return `<span class="eltag${small ? ' sm' : ''}" style="--e:${e.color}"><i></i>${e.name}</span>`;
    },
    renderTeam(state, cb) {
      const U = G.UNITS;
      // grade de personagens (compacta)
      const roster = $('#roster'); roster.innerHTML = '';
      for (const id of G.ROSTER) {
        const u = U[id], picked = state.team.includes(id);
        const card = document.createElement('button');
        card.className = 'rcard' + (picked ? ' picked' : '') + (state.focus === id ? ' focus' : '');
        card.style.setProperty('--acc', u.accent || '#d8b45a');
        card.innerHTML = `${picked ? `<span class="tagpick">${state.team.indexOf(id) + 1}</span>` : ''}<canvas width="150" height="120"></canvas>
          <span class="rname">${u.name}</span><span class="rrole">${u.role}</span>${this.elemTag(u.element, true)}`;
        G.drawPortrait(card.querySelector('canvas'), u.art, { glow: picked ? '#4a3a20' : (u.accent || '#3a2a44') + '44' });
        card.onclick = () => (state.focus === id ? cb.toggle(id) : cb.focus(id));
        roster.appendChild(card);
      }
      // ficha em 4 blocos: identidade · atributos · habilidades · papel tático
      const f = U[state.focus], det = $('#detail');
      if (f) {
        const sks = f.skills.map(k => [k, G.SKILLS[k]]);
        det.innerHTML = `<div class="sheet" style="--acc:${f.accent || '#d8b45a'}">
          <section class="blk ident"><canvas class="sheet-portrait" width="150" height="170"></canvas>
            <div class="sheet-title"><canvas class="sheet-glyph" width="70" height="70"></canvas>
              <h2>${f.name}</h2><div class="cls">${f.role} · ${f.specialty || ''}</div>${this.elemTag(f.element)}<p>${f.style || ''}</p></div></section>
          <section class="blk attrs">
            <div class="tile"><i>Vida</i><b>${f.hp}</b></div><div class="tile"><i>Postura</i><b>${f.posture}</b></div><div class="tile"><i>Velocidade</i><b>${f.spd}</b></div>
            <div class="tile wide"><i>Ataque</i><span>${f.offense || ''}</span></div><div class="tile wide"><i>Defesa</i><span>${f.defense || ''}</span></div></section>
          <section class="blk skills"><div class="sh">Habilidades</div><div class="skgrid">${sks.map(([k, sk]) => `<button class="skbtn${state.skill === k ? ' on' : ''}" data-skill="${k}"><canvas width="40" height="40" data-icon="${sk.icon}"></canvas><span>${sk.name}</span><small>${sk.kind === 'attack' ? `F${sk.force}×${sk.beats || 1} · D${sk.dmg} · P${sk.pressure || 0}` : sk.kind === 'support' ? 'Suporte' : 'Defesa'}</small></button>`).join('')}</div></section>
          <section class="blk role"><div class="sh">Papel tático</div>
            <div class="rl"><b>Faz bem</b><span>${f.good || ''}</span></div><div class="rl"><b>Melhor contra</b><span>${f.bestVs || ''}</span></div><div class="rl"><b>Limitações</b><span>${f.limits || ''}</span></div></section>
        </div>`;
        G.drawPortrait(det.querySelector('.sheet-portrait'), f.art, { glow: (f.accent || '#3a2a44') + '55' });
        G.drawIcon(det.querySelector('.sheet-glyph').getContext('2d'), f.glyph || 'sword', 35, 35, 26, (f.accent || '#d8b45a') + '55');
        det.querySelectorAll('.skbtn canvas').forEach(c => { const g = c.getContext('2d'); g.fillStyle = '#140c14'; g.beginPath(); g.arc(20, 20, 18, 0, 7); g.fill(); g.strokeStyle = f.accent || '#d8b45a'; g.lineWidth = 2; g.stroke(); G.drawIcon(g, c.dataset.icon, 20, 20, 12, f.accent || '#d8b45a'); });
        // prévia só ao CLICAR na habilidade (sem animações disparando no hover)
        det.querySelectorAll('.skbtn').forEach(b => { b.onclick = () => cb.pickSkill(b.dataset.skill); });
      } else det.innerHTML = '';
      // painel da habilidade escolhida: descrição, números e prévia
      const sp = $('#skillpane'), sk = state.skill && G.SKILLS[state.skill];
      if (sk && f && f.skills.includes(state.skill)) {
        const fx = [sk.applies === 'weaken' ? 'enfraquece' : '', sk.impact === 'knockdown' ? 'derruba' : sk.impact === 'stagger' ? 'desequilibra' : sk.impact === 'push' ? 'empurra' : '',
          sk.tags.includes('magic') ? 'magia' : sk.tags.includes('ranged') ? 'à distância' : '', sk.postureHeal ? `+${sk.postureHeal} Postura` : '', sk.cooldown ? `recarga ${sk.cooldown - 1}` : ''].filter(Boolean).join(' · ');
        sp.innerHTML = `<div class="spc" style="--acc:${f.accent}"><h3>${sk.name}</h3><p>${sk.desc}</p>
          <div class="nums">${sk.kind === 'attack' ? `<span><i>Força</i>${sk.force}</span><span><i>Dano</i>${sk.dmg}</span><span><i>Pressão</i>${sk.pressure || 0}</span><span><i>Batidas</i>${sk.beats || 1}</span><span><i>Golpes</i>${(sk.hits || [1]).length}</span>` : `<span><i>Tipo</i>${sk.kind === 'support' ? 'Suporte' : 'Defesa'}</span>`}</div>
          ${fx ? `<div class="fx">${fx}</div>` : ''}<div id="pv-slot" class="pv-slot"></div></div>`;
        if (cb.preview) cb.preview.mount(sp.querySelector('#pv-slot'));
      } else sp.innerHTML = `<div class="spc empty"><p>Clique numa habilidade da ficha para ver a descrição completa e a prévia animada.</p></div>`;
      const tb = $('#btn-toggle');
      tb.textContent = state.team.includes(state.focus) ? 'Remover da equipe' : state.team.length >= 3 ? 'Equipe cheia' : 'Adicionar à equipe';
      tb.disabled = !state.team.includes(state.focus) && state.team.length >= 3;
      tb.onclick = () => cb.toggle(state.focus);
      // três espaços da equipe
      const slots = $('#slots'); slots.innerHTML = '';
      for (let i = 0; i < 3; i++) {
        const id = state.team[i], el = document.createElement('div');
        el.className = 'slot' + (id ? ' full' : '');
        el.innerHTML = id ? `<canvas width="44" height="52"></canvas><span><b>${U[id].name}</b>${this.elemTag(U[id].element, true)}</span><em title="remover">✕</em>` : `<span class="muted">Espaço ${i + 1}</span>`;
        if (id) { G.drawPortrait(el.querySelector('canvas'), U[id].art); el.onclick = () => cb.toggle(id); }
        slots.appendChild(el);
      }
      $('#btn-start').disabled = state.team.length !== 3;
      $('#btn-start').onclick = cb.start;
    },
    // Painel do ciclo elemental: pentágono com setas (quem vence quem)
    drawLegend() {
      const c = $('#legend'); if (!c) return;
      const g = c.getContext('2d'), W = c.width, H = c.height, cx = W / 2, cy = H / 2 + 6, R = 56;
      g.clearRect(0, 0, W, H);
      g.fillStyle = 'rgba(12,8,16,0.6)'; g.beginPath(); g.arc(cx, cy - 2, R + 26, 0, 7); g.fill();
      const pts = G.ELEMENT_ORDER.map((k, i) => { const a = -Math.PI / 2 + i * 2 * Math.PI / 5; return { k, x: cx + Math.cos(a) * R, y: cy + Math.sin(a) * R }; });
      pts.forEach((p, i) => {
        const q = pts[(i + 1) % 5], ang = Math.atan2(q.y - p.y, q.x - p.x), d = Math.hypot(q.x - p.x, q.y - p.y);
        const x0 = p.x + Math.cos(ang) * 15, y0 = p.y + Math.sin(ang) * 15, x1 = p.x + Math.cos(ang) * (d - 17), y1 = p.y + Math.sin(ang) * (d - 17);
        g.strokeStyle = G.ELEMENTS[p.k].color; g.lineWidth = 2.5; g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
        g.fillStyle = G.ELEMENTS[p.k].color; g.beginPath(); g.moveTo(x1 + Math.cos(ang) * 4, y1 + Math.sin(ang) * 4); g.lineTo(x1 - Math.cos(ang - 0.5) * 9, y1 - Math.sin(ang - 0.5) * 9); g.lineTo(x1 - Math.cos(ang + 0.5) * 9, y1 - Math.sin(ang + 0.5) * 9); g.fill();
      });
      pts.forEach(p => { g.fillStyle = '#0e0a12'; g.beginPath(); g.arc(p.x, p.y, 12, 0, 7); g.fill(); g.fillStyle = G.ELEMENTS[p.k].color; g.beginPath(); g.arc(p.x, p.y, 9, 0, 7); g.fill(); });
      g.font = '700 10px "Trebuchet MS", sans-serif'; g.textAlign = 'center'; g.fillStyle = '#e8dccb';
      g.fillText('vence →', cx, cy + 4);
    },
    showTeam(on) { $('#team').classList.toggle('show', on); },
    hideEnd() { $('#overlay').classList.remove('show'); $('#overlay').innerHTML = ''; },
  };

  G.UI = UI;
})(window);
