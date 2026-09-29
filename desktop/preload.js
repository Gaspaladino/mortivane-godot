// Ponte mínima e segura entre o jogo (página) e o Electron.
const { contextBridge, ipcRenderer } = require('electron');

const args = process.argv;
contextBridge.exposeInMainWorld('mortivaneDesktop', {
  // true na versão empacotada (sem --admin): esconde o modo administrador
  release: args.includes('--mortivane-release'),
  isFullscreen: () => ipcRenderer.invoke('mortivane:is-fullscreen'),
  toggleFullscreen: () => ipcRenderer.invoke('mortivane:toggle-fullscreen'),
  quit: () => ipcRenderer.invoke('mortivane:quit'),
  onFullscreenChange: (fn) => ipcRenderer.on('mortivane:fullscreen', (_e, on) => fn(!!on))
});
