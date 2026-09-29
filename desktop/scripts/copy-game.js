// Copia a versão mais nova do jogo (MortivaneV<número>.html na raiz do repositório)
// para desktop/game/index.html antes de rodar ou empacotar.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const TARGET_DIR = path.resolve(__dirname, '..', 'game');

const versions = fs.readdirSync(ROOT)
  .map(name => ({ name, v: (name.match(/^MortivaneV(\d+)\.html$/) || [])[1] }))
  .filter(f => f.v)
  .sort((a, b) => Number(b.v) - Number(a.v));

if (!versions.length) {
  console.error('Nenhum MortivaneV<número>.html encontrado em ' + ROOT);
  process.exit(1);
}
const source = path.join(ROOT, versions[0].name);
fs.mkdirSync(TARGET_DIR, { recursive: true });
fs.copyFileSync(source, path.join(TARGET_DIR, 'index.html'));
console.log('Jogo copiado: ' + versions[0].name + ' -> game/index.html');
