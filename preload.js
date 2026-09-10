const { contextBridge, ipcRenderer } = require('electron');

/**
 * AuraTube Main Window Secure Preload
 * Strictly exposes whitelisted IPC communication without Node.js integration
 */
contextBridge.exposeInMainWorld('electronAPI', {
  sendMediaUpdate: (state) => {
    if (state && typeof state === 'object') {
      ipcRenderer.send('main-media-update', state);
    }
  },
  onControl: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const handler = (event, data) => callback(data);
    ipcRenderer.on('main-control', handler);
    return () => ipcRenderer.removeListener('main-control', handler);
  },
  onPlayVideo: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const handler = (event, data) => callback(data);
    ipcRenderer.on('main-play-video', handler);
    return () => ipcRenderer.removeListener('main-play-video', handler);
  }
});
