const { app, BrowserWindow, Menu, ipcMain, session } = require('electron')
const path = require('path')
const http = require('http')

app.setName('Lumen')

const isDev = process.argv.includes('--dev')
const DRAG_CSS = `
  body { -webkit-app-region: drag; }
  a, button, input, textarea, select, label,
  [role="button"], [role="tab"], [role="menuitem"], [role="option"],
  [role="checkbox"], [role="radio"], [role="switch"], [role="slider"],
  [contenteditable="true"], canvas, iframe, .no-drag {
    -webkit-app-region: no-drag;
  }
`

let mainWindow = null

function createWindow(opts = {}) {
  const win = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1000,
    minHeight: 600,
    backgroundColor: '#040404',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    ...opts,
  })
  win.webContents.on('did-finish-load', () => win.webContents.insertCSS(DRAG_CSS))
  win.webContents.on('console-message', (_e, level, message, line, sourceId) => {
    const tag = ['LOG', 'WARN', 'ERR', 'DBG'][level] || 'LOG'
    console.log(`[renderer ${tag}] ${message}${sourceId ? ` (${sourceId}:${line})` : ''}`)
  })
  win.webContents.on('render-process-gone', (_e, details) => {
    console.error(`[renderer GONE] reason=${details.reason} exitCode=${details.exitCode}`)
  })
  win.on('closed', () => { mainWindow = null })
  return win
}

function waitForVite(url, retries = 40, interval = 500) {
  return new Promise((resolve) => {
    const attempt = () => {
      http.get(url, (res) => {
        res.resume()
        if (res.statusCode === 200 || res.statusCode === 304) {
          return resolve()
        }
        if (retries-- > 0) { setTimeout(attempt, interval) } else { resolve() }
      }).on('error', () => {
        if (retries-- > 0) { setTimeout(attempt, interval) } else { resolve() }
      })
    }
    attempt()
  })
}

// ── Menu ──────────────────────────────────────────────────────────────────────
function buildMenu() {
  const template = [
    {
      label: 'Lumen',
      submenu: [
        { label: 'About Lumen', role: 'about' },
        { type: 'separator' },
        { label: 'Quit', role: 'quit' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { label: 'Reload', role: 'reload' },
        { label: 'Enter Full Screen', role: 'togglefullscreen' },
        ...(isDev ? [{ label: 'Developer Tools', role: 'toggleDevTools' }] : []),
      ],
    },
    {
      label: 'Window',
      submenu: [{ role: 'minimize' }, { role: 'zoom' }, { role: 'front' }],
    },
  ]
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

// ── IPC Handlers ─────────────────────────────────────────────────────────────
ipcMain.handle('toggle-fullscreen', () => {
  if (mainWindow) mainWindow.setFullScreen(!mainWindow.isFullScreen())
})

// ── Boot ──────────────────────────────────────────────────────────────────────
app.whenReady().then(async () => {
  buildMenu()

  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    if (permission === 'media' || permission === 'microphone' || permission === 'audioCapture') {
      return callback(true)
    }
    callback(false)
  })

  if (isDev) {
    mainWindow = createWindow()
    mainWindow.loadFile(path.join(__dirname, 'loading.html'))
    await waitForVite('http://localhost:5173')
    if (mainWindow) {
      mainWindow.loadURL('http://localhost:5173')
      mainWindow.webContents.openDevTools({ mode: 'detach' })
    }
  } else {
    mainWindow = createWindow()
    mainWindow.loadFile(path.join(__dirname, 'dist', 'index.html'))
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      mainWindow = createWindow()
      if (isDev) {
        mainWindow.loadURL('http://localhost:5173')
      } else {
        mainWindow.loadFile(path.join(__dirname, 'dist', 'index.html'))
      }
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

