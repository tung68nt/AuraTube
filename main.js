const { app, BrowserWindow, shell, session, Menu, Tray, nativeImage, nativeTheme, ipcMain, screen } = require('electron');
const path = require('path');
const http = require('http');

// Enforce system theme synchronization
nativeTheme.themeSource = 'system';

// Enforce single instance - NEVER allow multiple app icons on the Dock
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  app.quit();
  process.exit(0);
}

// Clean User-Agent matching Chromium 134 to ensure authentic browser appearance
const CHROME_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
app.userAgentFallback = CHROME_UA;

// Always allow seamless instant video autoplay without requiring prior manual click
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

// Ensure Homebrew and system tools (yt-dlp, ffmpeg, node) are in PATH
const defaultPaths = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin'];
for (const p of defaultPaths) {
  if (!process.env.PATH || !process.env.PATH.includes(p)) {
    process.env.PATH = `${p}:${process.env.PATH || ''}`;
  }
}

// Global safety catch for stream and network aborts
process.on('uncaughtException', (err) => {
  if (err && (err.name === 'AbortError' || err.code === 'ABORT_ERR')) return;
  console.error('Unhandled main process exception:', err);
});
process.on('unhandledRejection', (reason) => {
  if (reason && (reason.name === 'AbortError' || reason.code === 'ABORT_ERR')) return;
  console.error('Unhandled main process rejection:', reason);
});

let mainWindow = null;
let trayWindow = null;
let tray = null;
let isDockVisible = true;
let isTrayPinned = false;
app.isQuitting = false;

const PORT = process.env.PORT || 3000;

function checkServerReady(callback) {
  const req = http.get(`http://127.0.0.1:${PORT}/api/trending`, (res) => {
    callback(true);
  });
  req.on('error', () => {
    callback(false);
  });
}

function startServerIfNeeded(done) {
  checkServerReady((ready) => {
    if (ready) {
      done();
    } else {
      try {
        require(path.join(__dirname, 'server.js'));
      } catch (err) {
        console.error('Failed to load server.js:', err);
      }
      const interval = setInterval(() => {
        checkServerReady((ok) => {
          if (ok) {
            clearInterval(interval);
            done();
          }
        });
      }, 500);
    }
  });
}

// Query active media state from mainWindow
async function getMainWindowMediaState() {
  if (!mainWindow || !mainWindow.webContents) return { hasVideo: false };
  try {
    return await mainWindow.webContents.executeJavaScript(`
      (() => {
        if (window.app && window.app.player) {
          const p = window.app.player;
          const activeMedia = p.isAudioOnly ? p.audio : p.video;
          const videoId = p.currentVideoId;
          const title = document.getElementById('watchTitle')?.textContent?.trim() || '';
          const author = document.getElementById('uploaderName')?.textContent?.trim() || '';
          const views = document.getElementById('videoViews')?.textContent?.trim() || '';
          return {
            hasVideo: Boolean(videoId),
            videoId: videoId,
            title: title || 'Video YouTube',
            author: author || 'YouTube',
            views: views || '',
            currentTime: (activeMedia && activeMedia.currentTime) || 0,
            duration: (activeMedia && activeMedia.duration) || 0,
            paused: activeMedia ? activeMedia.paused : true,
            muted: p.isMuted,
            volume: p.currentVolume,
            isAudioOnly: p.isAudioOnly
          };
        }
        const v = document.querySelector('video');
        if (!v) return { hasVideo: false };
        return {
          hasVideo: Boolean(v.src),
          videoId: '',
          title: document.title || 'Video YouTube',
          author: 'YouTube',
          views: '',
          currentTime: v.currentTime || 0,
          duration: v.duration || 0,
          paused: v.paused,
          muted: v.muted,
          volume: v.volume,
          isAudioOnly: false
        };
      })()
    `);
  } catch (e) {
    return { hasVideo: false };
  }
}

async function sendMediaStateToMini() {
  if (!trayWindow || !trayWindow.webContents) return;
  const state = await getMainWindowMediaState();
  trayWindow.webContents.send('mini-sync-state', state);
}

// Forward live media state updates from mainWindow directly to trayWindow
ipcMain.on('main-media-update', (event, state) => {
  if (trayWindow && !trayWindow.isDestroyed()) {
    trayWindow.webContents.send('mini-sync-state', state);
  }
});

// Media Control Helpers
function togglePlayPause() {
  if (!mainWindow || !mainWindow.webContents) return;
  mainWindow.webContents.executeJavaScript(`
    (() => {
      if (window.app && window.app.player) {
        window.app.player.togglePlay();
        return 'toggled';
      }
      const v = document.querySelector('video');
      if (v) {
        if (v.paused) {
          v.play().catch(() => {});
          return 'playing';
        } else {
          v.pause();
          return 'paused';
        }
      }
      return 'novideo';
    })()
  `).catch(() => {});
}

function seekRelative(seconds) {
  if (!mainWindow || !mainWindow.webContents) return;
  mainWindow.webContents.executeJavaScript(`
    (() => {
      if (window.app && window.app.player) {
        const p = window.app.player;
        const m = p.isAudioOnly ? p.audio : p.video;
        if (m && isFinite(m.currentTime)) {
          m.currentTime = Math.max(0, Math.min(m.duration || Infinity, m.currentTime + (${seconds})));
          if (!p.isAudioOnly && p.hasSeparateAudio && p.audio) p.audio.currentTime = m.currentTime;
          p.broadcastState();
        }
        return;
      }
      const v = document.querySelector('video');
      if (v && isFinite(v.currentTime)) {
        v.currentTime = Math.max(0, Math.min(v.duration || Infinity, v.currentTime + (${seconds})));
      }
    })()
  `).catch(() => {});
}

function toggleMute() {
  if (!mainWindow || !mainWindow.webContents) return;
  mainWindow.webContents.executeJavaScript(`
    (() => {
      if (window.app && window.app.player) {
        return window.app.player.toggleMute();
      }
      const v = document.querySelector('video');
      if (v) {
        v.muted = !v.muted;
        return v.muted;
      }
      return false;
    })()
  `).catch(() => {});
}

function toggleAudioOnly() {
  if (!mainWindow || !mainWindow.webContents) return;
  mainWindow.webContents.executeJavaScript(`
    (() => {
      if (window.app && window.app.player) {
        window.app.player.toggleAudioOnly();
      }
    })()
  `).catch(() => {});
}

function toggleWindow() {
  if (!mainWindow) {
    createWindow();
    return;
  }
  if (mainWindow.isVisible()) {
    if (mainWindow.isFocused()) {
      mainWindow.hide();
    } else {
      mainWindow.focus();
    }
  } else {
    mainWindow.show();
    mainWindow.focus();
  }
}

function toggleDockVisibility() {
  if (process.platform !== 'darwin' || !app.dock) return isDockVisible;
  if (isDockVisible) {
    app.dock.hide();
    isDockVisible = false;
  } else {
    app.dock.show();
    isDockVisible = true;
  }
  buildAppMenu();
  return isDockVisible;
}

// Mini Player Popover Creation & Positioning
function createTrayWindow() {
  if (trayWindow) return;

  trayWindow = new BrowserWindow({
    width: 380,
    height: 640,
    show: false,
    frame: false,
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    backgroundColor: '#00000000',
    transparent: true,
    hasShadow: false, // Disables macOS native rectangular gray halo artifact
    webPreferences: {
      preload: path.join(__dirname, 'preload-mini.js'),
      contextIsolation: true,
      nodeIntegration: false,
      devTools: false
    }
  });

  trayWindow.webContents.on('before-input-event', (event, input) => {
    if (
      input.key === 'F12' ||
      (input.meta && input.alt && (input.key === 'i' || input.key === 'I')) ||
      (input.control && input.shift && (input.key === 'i' || input.key === 'I'))
    ) {
      event.preventDefault();
    }
  });
  trayWindow.webContents.on('context-menu', (e) => e.preventDefault());

  trayWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.loadURL(url);
      mainWindow.show();
      mainWindow.focus();
    }
    return { action: 'deny' };
  });

  trayWindow.loadURL(`http://127.0.0.1:${PORT}/mini-player.html?t=${Date.now()}`);

  trayWindow.webContents.on('did-finish-load', () => {
    if (trayWindow && !trayWindow.isDestroyed() && trayWindow.isVisible()) {
      trayWindow.webContents.send('mini-window-visibility', true);
      sendMediaStateToMini();
    }
  });

  // Auto-hide when user clicks outside (unless pinned)
  trayWindow.on('blur', () => {
    if (!isTrayPinned && !trayWindow.webContents.isDevToolsOpened()) {
      trayWindow.hide();
      try { trayWindow.webContents.send('mini-window-visibility', false); } catch (e) {}
    }
  });

  trayWindow.on('closed', () => {
    trayWindow = null;
  });
}

function toggleTrayWindow(bounds) {
  if (!trayWindow) {
    createTrayWindow();
  }

  if (trayWindow.isVisible()) {
    trayWindow.hide();
    try { trayWindow.webContents.send('mini-window-visibility', false); } catch (e) {}
    return;
  }

  const trayBounds = bounds || (tray ? tray.getBounds() : { x: 0, y: 0, width: 0, height: 0 });
  const winBounds = trayWindow.getBounds();

  // Bounds safety check for multi-monitors
  const display = screen.getDisplayNearestPoint({ x: trayBounds.x, y: trayBounds.y });

  // Position directly centered beneath the YouTube menu bar icon
  let x = Math.round(trayBounds.x + (trayBounds.width / 2) - (winBounds.width / 2));
  
  // Exact native macOS popover Y position matching MacClean & BatFlow
  // On macOS, display.workArea.y is the exact menubar bottom edge
  const menuBarBottom = display.workArea.y > 0 ? display.workArea.y : (trayBounds.y + trayBounds.height);
  let y = Math.round(menuBarBottom + 2);

  if (x < display.bounds.x + 8) x = display.bounds.x + 8;
  if (x + winBounds.width > display.bounds.x + display.bounds.width - 8) {
    x = display.bounds.x + display.bounds.width - winBounds.width - 8;
  }

  trayWindow.setPosition(x, y, false);
  trayWindow.show();
  trayWindow.focus();
  try { trayWindow.webContents.send('mini-window-visibility', true); } catch (e) {}

  sendMediaStateToMini();
}

function createTray() {
  // Destroy existing tray if any to prevent duplicate icons
  if (tray) {
    try {
      tray.destroy();
    } catch (e) {}
    tray = null;
  }

  // Use official YouTube template icon (crisp white in Dark Mode, native macOS menu bar standard)
  const trayIconPath = path.join(__dirname, 'assets/ytTemplate.png');
  const trayIcon = nativeImage.createFromPath(trayIconPath);
  trayIcon.setTemplateImage(true);

  tray = new Tray(trayIcon);
  tray.setToolTip('AuraTube - Trình phát YouTube');
  tray.setIgnoreDoubleClickEvents(true);

  // Single click: Instant Mini Video Player Popover
  tray.on('click', (event, bounds) => {
    toggleTrayWindow(bounds);
  });

  // Right click: Fast native context menu fallback
  tray.on('right-click', () => {
    const contextMenu = Menu.buildFromTemplate([
      {
        label: 'AuraTube Desktop',
        enabled: false
      },
      { type: 'separator' },
      {
        label: mainWindow && mainWindow.isVisible() ? 'Ẩn cửa sổ AuraTube' : 'Hiện cửa sổ AuraTube',
        click: () => toggleWindow()
      },
      {
        label: isDockVisible ? 'Ẩn icon trên Dock' : 'Hiện icon trên Dock',
        click: () => toggleDockVisibility()
      },
      { type: 'separator' },
      {
        label: 'Thoát AuraTube',
        click: () => {
          app.isQuitting = true;
          app.quit();
        }
      }
    ]);
    tray.popUpContextMenu(contextMenu);
  });
}

// Setup IPC Communication with Mini Player
ipcMain.handle('mini-get-theme', () => {
  return nativeTheme.shouldUseDarkColors ? 'dark' : 'light';
});

nativeTheme.on('updated', () => {
  const theme = nativeTheme.shouldUseDarkColors ? 'dark' : 'light';
  if (trayWindow && !trayWindow.isDestroyed()) {
    trayWindow.webContents.send('mini-theme-updated', theme);
  }
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('theme-updated', theme);
  }
});

ipcMain.handle('mini-get-media-state', async () => {
  return await getMainWindowMediaState();
});

ipcMain.handle('mini-get-dock-state', () => {
  return isDockVisible;
});

ipcMain.handle('mini-is-visible', () => {
  return trayWindow && !trayWindow.isDestroyed() ? trayWindow.isVisible() : false;
});

ipcMain.handle('mini-toggle-dock', () => {
  return toggleDockVisibility();
});

ipcMain.on('mini-set-pin', (event, pinned) => {
  isTrayPinned = Boolean(pinned);
  if (trayWindow) {
    trayWindow.setAlwaysOnTop(isTrayPinned, 'floating');
  }
});

ipcMain.on('mini-hide-window', () => {
  if (trayWindow) trayWindow.hide();
});

ipcMain.on('mini-quit', () => {
  app.isQuitting = true;
  app.quit();
});

ipcMain.on('mini-expand-main', (event, { videoId, currentTime, isPlaying }) => {
  if (!mainWindow) createWindow();
  mainWindow.show();
  mainWindow.focus();
  if (trayWindow && !isTrayPinned) trayWindow.hide();

  if (videoId && /^[a-zA-Z0-9_-]{11}$/.test(videoId)) {
    mainWindow.webContents.send('main-play-video', {
      videoId,
      currentTime: typeof currentTime === 'number' ? currentTime : 0,
      isPlaying: Boolean(isPlaying)
    });
  }
});

ipcMain.handle('mini-control-main', async (event, { action, payload }) => {
  if (!mainWindow || !mainWindow.webContents) return;
  mainWindow.webContents.send('main-control', { action, payload });
});

function buildAppMenu() {
  const menuTemplate = [
    {
      label: 'AuraTube',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        {
          label: isDockVisible ? '🔽 Ẩn icon trên Dock' : '🔼 Hiện icon trên Dock',
          accelerator: 'CmdOrCtrl+Shift+D',
          click: () => toggleDockVisibility()
        },
        {
          label: 'Thu nhỏ vào Menu Bar',
          accelerator: 'CmdOrCtrl+W',
          click: () => {
            if (mainWindow) mainWindow.hide();
          }
        },
        { type: 'separator' },
        {
          label: 'Thoát AuraTube',
          accelerator: 'CmdOrCtrl+Q',
          click: () => {
            app.isQuitting = true;
            app.quit();
          }
        }
      ]
    },
    {
      label: 'Điều khiển Media',
      submenu: [
        {
          label: 'Phát / Tạm dừng (Play / Pause)',
          accelerator: 'MediaPlayPause',
          click: () => togglePlayPause()
        },
        {
          label: 'Tua tới 10s',
          accelerator: 'CmdOrCtrl+Right',
          click: () => seekRelative(10)
        },
        {
          label: 'Tua lùi 10s',
          accelerator: 'CmdOrCtrl+Left',
          click: () => seekRelative(-10)
        },
        {
          label: 'Bật / Tắt tiếng (Mute)',
          accelerator: 'CmdOrCtrl+M',
          click: () => toggleMute()
        },
        {
          label: 'Chuyển Video / Chỉ Audio (Audio-Only)',
          accelerator: 'Shift+A',
          click: () => toggleAudioOnly()
        },
        {
          label: 'Phát Video mẫu (Test)',
          accelerator: 'CmdOrCtrl+Shift+P',
          click: () => {
            if (mainWindow && mainWindow.webContents) {
              mainWindow.webContents.executeJavaScript(`
                (() => {
                  if (window.app && window.app.videos && window.app.videos.length > 0) {
                    window.app.openWatchView(window.app.videos[0]);
                  } else if (window.app) {
                    window.app.playVideoById('81EY8f25Clo');
                  }
                })()
              `).catch(() => {});
            }
          }
        },
        {
          label: 'Lưu / Bỏ lưu video (Bookmark)',
          accelerator: 'CmdOrCtrl+B',
          click: () => {
            if (mainWindow && mainWindow.webContents) {
              mainWindow.webContents.executeJavaScript(`
                (() => {
                  if (window.app && window.app.currentVideo) {
                    window.app.toggleBookmark(window.app.currentVideo);
                  }
                })()
              `).catch(() => {});
            }
          }
        },
        {
          label: 'Mở Menu Tải về (Cốc Cốc Picker)',
          accelerator: 'CmdOrCtrl+Shift+D',
          click: () => {
            if (mainWindow && mainWindow.webContents) {
              mainWindow.webContents.executeJavaScript(`
                (() => {
                  if (window.app && window.app.currentVideo) {
                    window.app.openDownloadModal(window.app.currentVideo);
                  } else if (window.app && window.app.videos && window.app.videos.length > 0) {
                    window.app.openDownloadModal(window.app.videos[0]);
                  }
                })()
              `).catch(() => {});
            }
          }
        },
        { type: 'separator' },
        { role: 'reload' },
        { role: 'forceReload' },
        { type: 'separator' },
        { role: 'togglefullscreen' }
      ]
    },
    {
      label: 'Cửa sổ',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        { type: 'separator' },
        {
          label: 'Hiện / Ẩn AuraTube',
          accelerator: 'CmdOrCtrl+Shift+A',
          click: () => toggleWindow()
        },
        {
          label: 'Bật / Tắt Mini Video Player trên Menu Bar',
          accelerator: 'CmdOrCtrl+Shift+M',
          click: () => toggleTrayWindow()
        }
      ]
    }
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(menuTemplate));
}

let isCreatingWindow = false;

function createWindow() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
    return mainWindow;
  }

  if (isCreatingWindow) return;
  isCreatingWindow = true;

  const iconPath = path.join(__dirname, 'assets/icon.png');
  if (process.platform === 'darwin' && app.dock) {
    app.dock.setIcon(iconPath);
  }

  mainWindow = new BrowserWindow({
    width: 1380,
    height: 900,
    minWidth: 960,
    minHeight: 640,
    title: 'AuraTube',
    icon: iconPath,
    titleBarStyle: 'hiddenInset',
    backgroundColor: '#0f0f0f',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      devTools: false
    }
  });

  isCreatingWindow = false;

  // Block DevTools shortcuts and browser inspect context menu for a 100% native Mac app feel
  mainWindow.webContents.on('before-input-event', (event, input) => {
    // Block F12, Cmd+Opt+I (macOS), Ctrl+Shift+I (Windows/Linux)
    if (
      input.key === 'F12' ||
      (input.meta && input.alt && (input.key === 'i' || input.key === 'I')) ||
      (input.control && input.shift && (input.key === 'i' || input.key === 'I'))
    ) {
      event.preventDefault();
    }
  });

  mainWindow.webContents.on('context-menu', (e) => {
    // Prevent standard browser context menu containing 'Inspect Element'
    e.preventDefault();
  });

  // Prevent duplicate windows and external ad navigation. Always play cleanly in AuraTube
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    try {
      const parsed = new URL(url);
      if (['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'].includes(parsed.hostname)) {
        const m = url.match(/[?&]v=([^&]+)/) || url.match(/youtu\.be\/([^?&]+)/);
        if (m && m[1] && /^[a-zA-Z0-9_-]{11}$/.test(m[1])) {
          mainWindow.webContents.send('main-play-video', { videoId: m[1], currentTime: 0, isPlaying: true });
        }
        return { action: 'deny' };
      }
      if (['localhost', '127.0.0.1'].includes(parsed.hostname)) {
        return { action: 'deny' };
      }
      // Strictly allow only http and https protocols for external browsing
      if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
        shell.openExternal(url);
      }
    } catch (e) {
      console.warn('Blocked invalid navigation URL:', url);
    }
    return { action: 'deny' };
  });

  mainWindow.loadURL(`http://127.0.0.1:${PORT}`);

  mainWindow.webContents.on('render-process-gone', (event, details) => {
    console.warn('Renderer process note:', details.reason);
  });

  // Clicking red close button (X) quits the app completely as expected
  mainWindow.on('close', () => {
    app.isQuitting = true;
    app.quit();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  buildAppMenu();
  return mainWindow;
}

function setupAdBlocker() {
  const adBlockFilters = {
    urls: [
      '*://*.doubleclick.net/*',
      '*://googleads.g.doubleclick.net/*',
      '*://adservice.google.com/*',
      '*://*.googlesyndication.com/*'
    ]
  };

  try {
    session.defaultSession.webRequest.onBeforeRequest(adBlockFilters, (details, callback) => {
      callback({ cancel: true });
    });
  } catch (err) {
    console.error('Failed to register ad blocker filter:', err);
  }
}

let isAppInitialized = false;

app.whenReady().then(() => {
  setupAdBlocker();

  app.on('second-instance', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    }
  });

  startServerIfNeeded(() => {
    if (!isAppInitialized) {
      isAppInitialized = true;
      createWindow();
      createTray();
      createTrayWindow();
    }
  });

  app.on('activate', () => {
    if (isAppInitialized) {
      if (!mainWindow || mainWindow.isDestroyed()) {
        createWindow();
      } else {
        if (mainWindow.isMinimized()) mainWindow.restore();
        mainWindow.show();
        mainWindow.focus();
      }
    }
  });
});

app.on('before-quit', () => {
  app.isQuitting = true;
  if (tray) {
    try { tray.destroy(); } catch (e) {}
    tray = null;
  }
  if (trayWindow) {
    try { trayWindow.destroy(); } catch (e) {}
    trayWindow = null;
  }
});

app.on('window-all-closed', () => {
  app.isQuitting = true;
  app.quit();
});
