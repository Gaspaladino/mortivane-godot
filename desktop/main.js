// Mortivane — janela desktop (Electron) para distribuição na Steam.
const { app, BrowserWindow, ipcMain, Menu, shell } = require('electron');
const fs = require('fs');
const path = require('path');

const ADMIN = process.argv.includes('--admin');
const RELEASE = app.isPackaged && !ADMIN;

// Uma instância só: abrir de novo foca a janela existente
if (!app.requestSingleInstanceLock()) app.quit();

const settingsFile = () => path.join(app.getPath('userData'), 'window.json');
function readSettings() {
  try { return JSON.parse(fs.readFileSync(settingsFile(), 'utf8')); } catch (e) { return {}; }
}
function writeSettings(data) {
  try { fs.writeFileSync(settingsFile(), JSON.stringify(data)); } catch (e) { /* sem permissão: segue sem lembrar */ }
}

let win = null;

function createWindow() {
  const saved = readSettings();
  win = new BrowserWindow({
    width: 1280,
    height: 720,
    minWidth: 960,
    minHeight: 540,
    backgroundColor: '#0b0910',
    title: 'Mortivane',
    icon: path.join(__dirname, 'build', 'icon.png'),
    show: false,
    fullscreen: saved.fullscreen !== false, // abre em tela cheia na primeira vez
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      devTools: !RELEASE,
      autoplayPolicy: 'no-user-gesture-required',
      additionalArguments: RELEASE ? ['--mortivane-release'] : []
    }
  });
  Menu.setApplicationMenu(null);

  win.once('ready-to-show', () => win.show());
  win.loadFile(path.join(__dirname, 'game', 'index.html'));

  // O jogo nunca navega para fora; links externos abrem no navegador do sistema
  win.webContents.on('will-navigate', (e, url) => {
    if (!url.startsWith('file://')) { e.preventDefault(); shell.openExternal(url); }
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });

  // F11 e Alt+Enter alternam a tela cheia; Ctrl+Shift+I abre o DevTools fora da versão final
  win.webContents.on('before-input-event', (e, input) => {
    if (input.type !== 'keyDown') return;
    if (input.key === 'F11' || (input.alt && input.key === 'Enter')) { e.preventDefault(); toggleFullscreen(); }
    if (!RELEASE && input.control && input.shift && input.key.toLowerCase() === 'i') win.webContents.toggleDevTools();
  });

  const notify = () => {
    writeSettings({ ...readSettings(), fullscreen: win.isFullScreen() });
    win.webContents.send('mortivane:fullscreen', win.isFullScreen());
  };
  win.on('enter-full-screen', notify);
  win.on('leave-full-screen', notify);
  win.on('closed', () => { win = null; });
}

function toggleFullscreen() {
  if (win) win.setFullScreen(!win.isFullScreen());
  return win ? win.isFullScreen() : false;
}

ipcMain.handle('mortivane:is-fullscreen', () => (win ? win.isFullScreen() : false));
ipcMain.handle('mortivane:toggle-fullscreen', () => toggleFullscreen());
ipcMain.handle('mortivane:quit', () => { if (win) win.close(); });

app.on('second-instance', () => {
  if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
});
app.whenReady().then(createWindow);
app.on('window-all-closed', () => app.quit());
