// Copia a versão atual do jogo (HTML único) para desktop/game/index.html antes de rodar ou empacotar.
const fs = require('fs');
const path = require('path');

const SOURCE = path.resolve(__dirname, '..', '..', 'MortivaneV98.html');
const TARGET_DIR = path.resolve(__dirname, '..', 'game');

if (!fs.existsSync(SOURCE)) {
  console.error('Arquivo do jogo não encontrado: ' + SOURCE);
  process.exit(1);
}
fs.mkdirSync(TARGET_DIR, { recursive: true });
fs.copyFileSync(SOURCE, path.join(TARGET_DIR, 'index.html'));
console.log('Jogo copiado: ' + path.relative(process.cwd(), SOURCE) + ' -> game/index.html');
