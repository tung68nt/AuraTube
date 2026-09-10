const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('miniAPI', {
  // Query or receive state from main window
  getMediaState: () => ipcRenderer.invoke('mini-get-media-state'),
  onSyncState: (callback) => {
    const handler = (event, data) => callback(data);
    ipcRenderer.on('mini-sync-state', handler);
    return () => ipcRenderer.removeListener('mini-sync-state', handler);
  },

  // System Theme Synchronization
  getTheme: () => ipcRenderer.invoke('mini-get-theme'),
  onThemeUpdated: (callback) => {
    const handler = (event, theme) => callback(theme);
    ipcRenderer.on('mini-theme-updated', handler);
    return () => ipcRenderer.removeListener('mini-theme-updated', handler);
  },

  // Media Controls directed to main window
  sendControl: (action, payload) => ipcRenderer.invoke('mini-control-main', { action, payload }),

  // Visibility State
  isVisible: () => ipcRenderer.invoke('mini-is-visible'),
  onVisibilityChange: (callback) => {
    const handler = (event, visible) => callback(visible);
    ipcRenderer.on('mini-window-visibility', handler);
    return () => ipcRenderer.removeListener('mini-window-visibility', handler);
  },

  // Actions
  expandToMainWindow: (playbackState) => ipcRenderer.send('mini-expand-main', playbackState),
  toggleDock: () => ipcRenderer.invoke('mini-toggle-dock'),
  getDockState: () => ipcRenderer.invoke('mini-get-dock-state'),
  setPin: (pinned) => ipcRenderer.send('mini-set-pin', pinned),
  hideWindow: () => ipcRenderer.send('mini-hide-window'),
  quitApp: () => ipcRenderer.send('mini-quit')
});
