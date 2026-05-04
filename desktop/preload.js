const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('nexusDesktop', {
  isDesktop: true,
  platform: process.platform,
  onVoiceEvent: (callback) => ipcRenderer.on('voice-event', (_event, value) => callback(value)),
  toggleFullscreen: () => ipcRenderer.invoke('toggle-fullscreen'),
})
