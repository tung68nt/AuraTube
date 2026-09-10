document.addEventListener('DOMContentLoaded', () => {
  const video = document.getElementById('miniVideo');
  const placeholder = document.getElementById('videoPlaceholder');
  const overlay = document.getElementById('playerOverlay');
  const playerBox = document.getElementById('playerBox');

  const titleEl = document.getElementById('videoTitle');
  const avatarEl = document.getElementById('channelAvatar');
  const channelEl = document.getElementById('channelName');
  const viewsEl = document.getElementById('videoViews');

  const centerPlayBtn = document.getElementById('centerPlayBtn');
  const playPauseBtn = document.getElementById('playPauseBtn');
  const rewindBtn = document.getElementById('rewindBtn');
  const forwardBtn = document.getElementById('forwardBtn');
  const volumeBtn = document.getElementById('volumeBtn');
  const timeDisplay = document.getElementById('timeDisplay');

  const seekContainer = document.getElementById('seekContainer');
  const seekProgress = document.getElementById('seekProgress');
  const seekBuffered = document.getElementById('seekBuffered');

  const searchInput = document.getElementById('searchInput');
  const searchResults = document.getElementById('searchResults');
  const searchClearBtn = document.getElementById('searchClearBtn');

  const pinBtn = document.getElementById('pinBtn');
  const expandBtn = document.getElementById('expandBtn');
  const expandPillBtn = document.getElementById('expandPillBtn');
  const dockRow = document.getElementById('dockRow');
  const dockToggleCheckbox = document.getElementById('dockToggleCheckbox');
  const aboutBtn = document.getElementById('aboutBtn');
  const aboutModal = document.getElementById('aboutModal');
  const closeAboutModalBtn = document.getElementById('closeAboutModalBtn');
  const quitBtn = document.getElementById('quitBtn');
  const shareBtn = document.getElementById('shareBtn');
  const shareText = document.getElementById('shareText');
  const closeBtn = document.getElementById('closeBtn');

  const subscribeBtn = document.getElementById('subscribeBtn');
  const likeBtn = document.getElementById('likeBtn');
  const likeText = document.getElementById('likeText');
  const likeIconSvg = document.getElementById('likeIconSvg');

  let currentVideoId = null;
  let isPinned = false;
  let isDockVisible = true;
  let currentMode = 2; // 2 = AuraTube Siêu Tốc, 1 = YouTube Gốc
  let isSubscribed = false;
  let isLiked = false;
  let overlayTimeout = null;

  // macOS System Light / Dark Mode Auto-Sync
  function applyTheme(theme) {
    const isDark = theme === 'dark';
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    document.body.setAttribute('data-theme', isDark ? 'dark' : 'light');
  }

  if (window.miniAPI && window.miniAPI.getTheme) {
    window.miniAPI.getTheme().then(theme => {
      if (theme) applyTheme(theme);
    }).catch(() => {});

    window.miniAPI.onThemeUpdated(theme => {
      if (theme) applyTheme(theme);
    });
  }

  if (window.matchMedia) {
    const colorSchemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
    if (!document.documentElement.getAttribute('data-theme')) {
      applyTheme(colorSchemeQuery.matches ? 'dark' : 'light');
    }
    colorSchemeQuery.addEventListener('change', (e) => {
      applyTheme(e.matches ? 'dark' : 'light');
    });
  }

  function formatTime(seconds) {
    if (!seconds || isNaN(seconds)) return '0:00';
    const s = Math.floor(seconds);
    const m = Math.floor(s / 60);
    const sec = s % 60;
    const hours = Math.floor(m / 60);
    const remM = m % 60;
    if (hours > 0) {
      return `${hours}:${remM < 10 ? '0' : ''}${remM}:${sec < 10 ? '0' : ''}${sec}`;
    }
    return `${m}:${sec < 10 ? '0' : ''}${sec}`;
  }

  function updatePlayIcons(isPlaying) {
    const playSvg = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
    const pauseSvg = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>';
    const centerPlaySvg = '<svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
    const centerPauseSvg = '<svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>';

    if (isPlaying) {
      playPauseBtn.innerHTML = pauseSvg;
      centerPlayBtn.innerHTML = centerPauseSvg;
      hideOverlayDelayed();
    } else {
      playPauseBtn.innerHTML = playSvg;
      centerPlayBtn.innerHTML = centerPlaySvg;
      overlay.classList.add('visible');
    }
  }

  function hideOverlayDelayed() {
    clearTimeout(overlayTimeout);
    if (isScrubbing) return;
    overlayTimeout = setTimeout(() => {
      if (!video.paused && !isScrubbing) {
        overlay.classList.remove('visible');
      }
    }, 2500);
  }

  playerBox.addEventListener('mousemove', () => {
    overlay.classList.add('visible');
    if (!video.paused && !isScrubbing) hideOverlayDelayed();
  });

  playerBox.addEventListener('mouseleave', () => {
    if (!video.paused && !isScrubbing) overlay.classList.remove('visible');
  });

  // Keep mini-player video muted permanently - all master audio comes from mainWindow
  video.muted = true;
  video.volume = 0;

  function togglePlay() {
    if (window.miniAPI && window.miniAPI.sendControl) {
      window.miniAPI.sendControl('togglePlay');
    }
    if (!video.src && !currentVideoId) {
      loadTrendingVideo();
      return;
    }
    if (video.paused) {
      updatePlayIcons(true);
      video.play().catch(() => updatePlayIcons(false));
    } else {
      updatePlayIcons(false);
      video.pause();
    }
  }

  function loadVideo(videoId, title, author, startTime = 0, autoPlay = true, views = null) {
    currentVideoId = videoId;
    if (title) titleEl.textContent = title;
    if (author) {
      channelEl.textContent = author;
      avatarEl.textContent = (author || 'Y')[0].toUpperCase();
    }
    if (views) viewsEl.textContent = views;
    placeholder.style.display = 'none';

    // Strictly keep mini-player video muted
    video.muted = true;
    video.volume = 0;

    // Use quality=mini for lightweight 360p stream matching menubar viewport
    const streamUrl = `/api/proxy-stream?v=${videoId}&quality=mini&type=video`;

    const applyStart = () => {
      video.muted = true;
      video.volume = 0;
      if (startTime > 0 && video.duration && Math.abs(video.currentTime - startTime) > 0.5) {
        try { video.currentTime = startTime; } catch (e) {}
      }
      if (autoPlay && isWindowVisible) {
        video.play().catch(() => {});
        updatePlayIcons(true);
      } else if (!autoPlay) {
        video.pause();
        updatePlayIcons(false);
      }
    };

    if (video.src && video.src.includes(`v=${videoId}`)) {
      if (video.readyState >= 1) {
        applyStart();
      } else {
        video.addEventListener('loadedmetadata', applyStart, { once: true });
      }
    } else {
      video.src = streamUrl;
      video.load();
      video.addEventListener('loadedmetadata', applyStart, { once: true });
    }
  }

  video.addEventListener('play', () => updatePlayIcons(true));
  video.addEventListener('pause', () => updatePlayIcons(false));

  video.addEventListener('timeupdate', () => {
    if (isScrubbing || !video.duration) return;
    const progress = (video.currentTime / video.duration) * 100;
    seekProgress.style.width = `${progress}%`;
    timeDisplay.textContent = `${formatTime(video.currentTime)} / ${formatTime(video.duration)}`;
  });

  video.addEventListener('progress', () => {
    if (!video.duration || video.buffered.length === 0) return;
    const bufferedEnd = video.buffered.end(video.buffered.length - 1);
    const bufferedPercent = (bufferedEnd / video.duration) * 100;
    seekBuffered.style.width = `${bufferedPercent}%`;
  });

  // 60FPS Drag & Scrubbing Engine (Pointer Events)
  let isScrubbing = false;
  let wasPlayingBeforeScrub = false;

  function calculateTimeFromPointer(e) {
    if (!video.duration || isNaN(video.duration)) return 0;
    const rect = seekContainer.getBoundingClientRect();
    const clientX = e.clientX ?? (e.touches && e.touches[0] ? e.touches[0].clientX : 0);
    const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    const targetTime = ratio * video.duration;

    seekProgress.style.width = `${ratio * 100}%`;
    timeDisplay.textContent = `${formatTime(targetTime)} / ${formatTime(video.duration)}`;
    return targetTime;
  }

  seekContainer.addEventListener('pointerdown', (e) => {
    if (!video.duration) return;
    isScrubbing = true;
    seekContainer.classList.add('scrubbing');
    try { seekContainer.setPointerCapture(e.pointerId); } catch (err) {}
    wasPlayingBeforeScrub = !video.paused;
    if (wasPlayingBeforeScrub) {
      video.pause();
    }
    calculateTimeFromPointer(e);
  });

  seekContainer.addEventListener('pointermove', (e) => {
    if (!isScrubbing) return;
    const targetTime = calculateTimeFromPointer(e);
    if (video.fastSeek && typeof targetTime === 'number') {
      try { video.fastSeek(targetTime); } catch (err) {}
    }
  });

  const finishScrubbing = (e) => {
    if (!isScrubbing) return;
    isScrubbing = false;
    seekContainer.classList.remove('scrubbing');
    const finalTime = calculateTimeFromPointer(e);
    if (!isNaN(finalTime) && isFinite(finalTime)) {
      video.currentTime = finalTime;
      // Seek master player in mainWindow
      if (window.miniAPI && window.miniAPI.sendControl) {
        window.miniAPI.sendControl('seek', finalTime);
      }
    }
    if (wasPlayingBeforeScrub) {
      video.play().catch(() => {});
      updatePlayIcons(true);
    }
    try {
      seekContainer.releasePointerCapture(e.pointerId);
    } catch (err) {}
  };

  seekContainer.addEventListener('pointerup', finishScrubbing);
  seekContainer.addEventListener('pointercancel', finishScrubbing);

  playPauseBtn.addEventListener('click', togglePlay);
  centerPlayBtn.addEventListener('click', togglePlay);
  video.addEventListener('click', togglePlay);

  rewindBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    if (window.miniAPI && window.miniAPI.sendControl) {
      window.miniAPI.sendControl('seekRelative', -10);
    }
    if (video.duration) {
      const target = Math.max(0, video.currentTime - 10);
      video.currentTime = target;
      seekProgress.style.width = `${(target / video.duration) * 100}%`;
      timeDisplay.textContent = `${formatTime(target)} / ${formatTime(video.duration)}`;
    }
  });

  forwardBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    if (window.miniAPI && window.miniAPI.sendControl) {
      window.miniAPI.sendControl('seekRelative', 10);
    }
    if (video.duration) {
      const target = Math.min(video.duration, video.currentTime + 10);
      video.currentTime = target;
      seekProgress.style.width = `${(target / video.duration) * 100}%`;
      timeDisplay.textContent = `${formatTime(target)} / ${formatTime(video.duration)}`;
    }
  });

  const volumeHighSvg = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M3 9v6h4l5 5V4L9 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>';
  const volumeMutedSvg = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M3 9v6h4l5 5V4L9 9H3z"/><path d="M16.59 8L15.17 9.41 17.76 12l-2.59 2.59L16.59 16l2.59-2.59 2.59 2.59 1.41-1.41L20.59 12l2.59-2.59L21.76 8l-2.59 2.59L16.59 8z"/></svg>';

  function updateVolumeUI(isMuted) {
    if (isMuted) {
      volumeBtn.innerHTML = volumeMutedSvg;
      volumeBtn.title = 'Bật tiếng (m)';
    } else {
      volumeBtn.innerHTML = volumeHighSvg;
      volumeBtn.title = 'Tắt tiếng (m)';
    }
  }

  volumeBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    if (window.miniAPI && window.miniAPI.sendControl) {
      window.miniAPI.sendControl('toggleMute');
    }
  });

  // Global YouTube-style hotkeys (m: mute, space/k: play/pause, j/l: seek)
  document.addEventListener('keydown', (e) => {
    if (e.target === searchInput) return;
    if (e.key === 'm' || e.key === 'M') {
      if (window.miniAPI && window.miniAPI.sendControl) {
        window.miniAPI.sendControl('toggleMute');
      }
    } else if (e.key === ' ' || e.key === 'k' || e.key === 'K') {
      e.preventDefault();
      togglePlay();
    } else if (e.key === 'j' || e.key === 'J' || e.key === 'ArrowLeft') {
      if (window.miniAPI && window.miniAPI.sendControl) {
        window.miniAPI.sendControl('seekRelative', -10);
      }
      if (video.duration) {
        video.currentTime = Math.max(0, video.currentTime - 10);
      }
    } else if (e.key === 'l' || e.key === 'L' || e.key === 'ArrowRight') {
      if (window.miniAPI && window.miniAPI.sendControl) {
        window.miniAPI.sendControl('seekRelative', 10);
      }
      if (video.duration) {
        video.currentTime = Math.min(video.duration, video.currentTime + 10);
      }
    }
  });

  // Subscribe Button
  subscribeBtn.addEventListener('click', () => {
    isSubscribed = !isSubscribed;
    if (isSubscribed) {
      subscribeBtn.textContent = 'Đã đăng ký';
      subscribeBtn.style.background = 'rgba(255, 255, 255, 0.15)';
      subscribeBtn.style.color = '#fff';
    } else {
      subscribeBtn.textContent = 'Đăng ký';
      subscribeBtn.style.background = '#f1f1f1';
      subscribeBtn.style.color = '#0f0f0f';
    }
  });

  // Like Button
  likeBtn.addEventListener('click', () => {
    isLiked = !isLiked;
    likeBtn.classList.toggle('active', isLiked);
    likeText.textContent = isLiked ? 'Đã thích' : 'Thích';
    if (likeIconSvg) {
      likeIconSvg.setAttribute('fill', isLiked ? 'currentColor' : 'none');
    }
  });

  // Pin Button
  pinBtn.addEventListener('click', () => {
    isPinned = !isPinned;
    pinBtn.classList.toggle('active', isPinned);
    if (window.miniAPI) window.miniAPI.setPin(isPinned);
  });

  // Expand to Main Window
  function expandToMain() {
    if (window.miniAPI) {
      const isPlaying = !video.paused;
      const currentTime = video.currentTime || 0;
      video.pause();
      window.miniAPI.expandToMainWindow({
        videoId: currentVideoId,
        currentTime: currentTime,
        isPlaying: isPlaying
      });
    }
  }
  if (expandBtn) expandBtn.addEventListener('click', expandToMain);
  if (expandPillBtn) expandPillBtn.addEventListener('click', expandToMain);

  // Dock Toggle Switch (Apple-style toggle switch)
  async function handleToggleDock(e) {
    if (e && e.target === dockToggleCheckbox) {
      // Toggle was already changed by clicking checkbox
    }
    if (window.miniAPI) {
      isDockVisible = await window.miniAPI.toggleDock();
      updateDockUI();
    }
  }

  if (dockToggleCheckbox) {
    dockToggleCheckbox.addEventListener('change', handleToggleDock);
  }
  if (dockRow) {
    dockRow.addEventListener('click', (e) => {
      if (e.target !== dockToggleCheckbox) {
        handleToggleDock();
      }
    });
  }

  function updateDockUI() {
    if (dockToggleCheckbox) {
      // "Ẩn icon ở Dock": checked when Dock is hidden (isDockVisible === false)
      dockToggleCheckbox.checked = !isDockVisible;
    }
  }

  // Initial Dock State query
  if (window.miniAPI && window.miniAPI.getDockState) {
    window.miniAPI.getDockState().then(visible => {
      isDockVisible = visible;
      updateDockUI();
    }).catch(() => {});
  }

  // About Modal Handlers
  if (aboutBtn && aboutModal) {
    aboutBtn.addEventListener('click', () => {
      aboutModal.style.display = 'flex';
    });
  }
  if (closeAboutModalBtn && aboutModal) {
    closeAboutModalBtn.addEventListener('click', () => {
      aboutModal.style.display = 'none';
    });
  }
  if (aboutModal) {
    aboutModal.addEventListener('click', (e) => {
      if (e.target === aboutModal) {
        aboutModal.style.display = 'none';
      }
    });
  }

  // Quit App Handler (⌘Q)
  if (quitBtn) {
    quitBtn.addEventListener('click', () => {
      if (window.miniAPI && window.miniAPI.quitApp) {
        window.miniAPI.quitApp();
      }
    });
  }

  // Keyboard Shortcuts (⌘O: Open Main App, ⌘Q: Quit)
  window.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'o') {
      e.preventDefault();
      expandToMain();
    } else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'q') {
      e.preventDefault();
      if (window.miniAPI && window.miniAPI.quitApp) {
        window.miniAPI.quitApp();
      }
    }
  });

  // Share / Copy Link Button
  if (shareBtn) {
    shareBtn.addEventListener('click', async () => {
      if (!currentVideoId) return;
      const url = `https://youtu.be/${currentVideoId}`;
      try {
        await navigator.clipboard.writeText(url);
      } catch (err) {
        const input = document.createElement('input');
        input.value = url;
        document.body.appendChild(input);
        input.select();
        document.execCommand('copy');
        document.body.removeChild(input);
      }
      shareBtn.classList.add('active');
      shareText.textContent = 'Đã chép!';
      setTimeout(() => {
        shareBtn.classList.remove('active');
        shareText.textContent = 'Chia sẻ';
      }, 2000);
    });
  }

  // Close Window
  closeBtn.addEventListener('click', () => {
    if (window.miniAPI) window.miniAPI.hideWindow();
  });

  // YouTube Search Engine with Floating Upwards Results & Full Keyboard Nav
  let searchDebounce = null;
  let searchSelectedIndex = -1;

  function selectVideo(v) {
    searchResults.style.display = 'none';
    searchInput.value = '';
    if (searchClearBtn) searchClearBtn.style.display = 'none';
    loadVideo(v.id, v.title, v.author, 0, true, v.viewCount ? `${v.viewCount} lượt xem` : null);
    if (window.miniAPI && window.miniAPI.sendControl) {
      window.miniAPI.sendControl('playVideo', { id: v.id });
    }
  }

  function updateSelectedResult(items) {
    items.forEach((item, idx) => {
      if (idx === searchSelectedIndex) {
        item.classList.add('selected');
        item.scrollIntoView({ block: 'nearest' });
      } else {
        item.classList.remove('selected');
      }
    });
  }

  searchInput.addEventListener('keydown', async (e) => {
    const items = searchResults.querySelectorAll('.yt-dropdown-item');

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (items.length > 0) {
        searchSelectedIndex = (searchSelectedIndex + 1) % items.length;
        updateSelectedResult(items);
      }
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (items.length > 0) {
        searchSelectedIndex = (searchSelectedIndex - 1 + items.length) % items.length;
        updateSelectedResult(items);
      }
    } else if (e.key === 'Escape') {
      searchResults.style.display = 'none';
      searchInput.blur();
    } else if (e.key === 'Enter') {
      if (searchSelectedIndex >= 0 && items[searchSelectedIndex]) {
        e.preventDefault();
        items[searchSelectedIndex].click();
        return;
      }
      const q = searchInput.value.trim();
      if (!q) return;
      searchResults.style.display = 'none';
      try {
        titleEl.textContent = `Đang tìm: "${q}"...`;
        const res = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
        const data = await res.json();
        if (data.success && data.videos && data.videos.length > 0) {
          selectVideo(data.videos[0]);
        }
      } catch (err) {
        console.error('Search error:', err);
      }
    }
  });

  searchInput.addEventListener('input', () => {
    const q = searchInput.value.trim();
    if (searchClearBtn) {
      searchClearBtn.style.display = q ? 'flex' : 'none';
    }
    clearTimeout(searchDebounce);
    if (q.length < 2) {
      searchResults.style.display = 'none';
      return;
    }
    searchDebounce = setTimeout(async () => {
      try {
        const res = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
        const data = await res.json();
        if (data.success && data.videos && data.videos.length > 0) {
          renderSearchResults(data.videos.slice(0, 8));
        } else {
          searchResults.style.display = 'none';
        }
      } catch (err) {
        searchResults.style.display = 'none';
      }
    }, 280);
  });

  searchInput.addEventListener('focus', () => {
    if (searchResults.children.length > 1 && searchInput.value.trim().length >= 2) {
      searchResults.style.display = 'block';
    }
  });

  if (searchClearBtn) {
    searchClearBtn.addEventListener('click', () => {
      searchInput.value = '';
      searchClearBtn.style.display = 'none';
      searchResults.style.display = 'none';
      searchInput.focus();
    });
  }

  function renderSearchResults(videos) {
    searchResults.innerHTML = '';
    searchSelectedIndex = -1;

    const header = document.createElement('div');
    header.className = 'yt-dropdown-header';
    header.innerHTML = `<span>Gợi ý video</span><span>${videos.length} kết quả</span>`;
    searchResults.appendChild(header);

    videos.forEach((v, idx) => {
      const div = document.createElement('div');
      div.className = 'yt-dropdown-item';
      div.dataset.index = idx;
      div.innerHTML = `
        <div class="yt-dropdown-thumb-box">
          <img class="yt-dropdown-thumb" src="${v.thumbnail || ''}" alt="" onerror="this.style.display='none'">
        </div>
        <div class="yt-dropdown-text">
          <div class="yt-dropdown-title" title="${v.title}">${v.title}</div>
          <div class="yt-dropdown-meta">
            <span class="yt-dropdown-author">${v.author || ''}</span>
            ${v.viewCount ? `<span>•</span><span>${v.viewCount}</span>` : ''}
          </div>
        </div>
      `;
      div.addEventListener('mouseenter', () => {
        if (v.id) fetch(`/api/stream?v=${v.id}&quality=mini`).catch(() => {});
      }, { once: true });
      div.addEventListener('click', () => {
        selectVideo(v);
      });
      searchResults.appendChild(div);
    });
    searchResults.style.display = 'block';
  }

  document.addEventListener('click', (e) => {
    if (!searchInput.contains(e.target) && !searchResults.contains(e.target) && !searchClearBtn?.contains(e.target)) {
      searchResults.style.display = 'none';
    }
  });

  async function loadTrendingVideo() {
    try {
      titleEl.textContent = 'Đang tải gợi ý YouTube...';
      const res = await fetch('/api/trending');
      const data = await res.json();
      if (data.success && data.videos && data.videos.length > 0) {
        const item = data.videos[0];
        loadVideo(item.id, item.title, item.author, 0, true);
      }
    } catch (e) {
      titleEl.textContent = 'Sẵn sàng phát video';
    }
  }
  placeholder.addEventListener('click', loadTrendingVideo);

  let isWindowVisible = true;

  if (window.miniAPI && window.miniAPI.isVisible) {
    window.miniAPI.isVisible().then((vis) => {
      isWindowVisible = Boolean(vis);
      if (isWindowVisible) syncFromMain();
    }).catch(() => {});
  }

  if (window.miniAPI && window.miniAPI.onVisibilityChange) {
    window.miniAPI.onVisibilityChange((visible) => {
      isWindowVisible = Boolean(visible);
      if (!visible) {
        if (!video.paused) {
          video.pause();
          updatePlayIcons(false);
        }
      } else {
        syncFromMain();
      }
    });
  }

  window.addEventListener('focus', () => {
    isWindowVisible = true;
    syncFromMain();
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      if (!isPinned) {
        isWindowVisible = false;
        if (!video.paused) {
          video.pause();
          updatePlayIcons(false);
        }
      }
    } else {
      isWindowVisible = true;
      syncFromMain();
    }
  });

  function applySyncState(media) {
    if (!media || isScrubbing) return;

    if (media.hasVideo && media.videoId) {
      if (currentVideoId !== media.videoId) {
        currentVideoId = media.videoId;
        if (media.title) titleEl.textContent = media.title;
        if (media.author) {
          channelEl.textContent = media.author;
          avatarEl.textContent = (media.author || 'Y')[0].toUpperCase();
        }
        if (media.views) viewsEl.textContent = media.views;

        if (media.isAudioOnly) {
          if (!video.paused) video.pause();
          video.removeAttribute('src');
          video.style.display = 'none';
          if (placeholder) placeholder.style.display = 'flex';
        } else {
          loadVideo(media.videoId, media.title, media.author, media.currentTime || 0, isWindowVisible && !media.paused, media.views || null);
        }
      } else {
        if (media.title) titleEl.textContent = media.title;
        if (media.author) {
          channelEl.textContent = media.author;
          avatarEl.textContent = (media.author || 'Y')[0].toUpperCase();
        }
        if (media.views) viewsEl.textContent = media.views;

        // Keep mini-player video frames tightly in sync with master player (tight 0.5s tolerance)
        if (isWindowVisible && video.duration && Math.abs(video.currentTime - (media.currentTime || 0)) > 0.5) {
          video.currentTime = media.currentTime || 0;
        }

        if (media.isAudioOnly) {
          if (!video.paused) video.pause();
          video.removeAttribute('src');
          video.style.display = 'none';
          if (placeholder) {
            placeholder.style.display = 'flex';
            const span = placeholder.querySelector('span');
            if (span) span.textContent = '🎵 Chế độ chỉ nghe Audio';
          }
        } else {
          video.style.display = 'block';
          if (placeholder) {
            const span = placeholder.querySelector('span');
            if (span) span.textContent = 'Bấm để phát video thịnh hành';
            if (video.src) placeholder.style.display = 'none';
          }
          if (isWindowVisible) {
            if (!media.paused && video.paused) {
              video.play().catch(() => {});
            } else if (media.paused && !video.paused) {
              video.pause();
            }
          } else if (!video.paused) {
            video.pause();
          }
        }
      }

      updatePlayIcons(!media.paused);
      updateVolumeUI(Boolean(media.muted));

      if (media.duration && media.duration > 0) {
        const progress = ((media.currentTime || 0) / media.duration) * 100;
        seekProgress.style.width = `${progress}%`;
        timeDisplay.textContent = `${formatTime(media.currentTime || 0)} / ${formatTime(media.duration)}`;
      }
    } else if (!currentVideoId) {
      loadTrendingVideo();
    }
  }

  // Sync state from Main Window
  async function syncFromMain() {
    if (!window.miniAPI) return;

    try {
      const dockState = await window.miniAPI.getDockState();
      isDockVisible = dockState;
      updateDockUI();

      const media = await window.miniAPI.getMediaState();
      applySyncState(media);
    } catch (err) {
      console.warn('Sync failed:', err);
    }
  }

  if (window.miniAPI && window.miniAPI.onSyncState) {
    window.miniAPI.onSyncState((data) => {
      applySyncState(data);
    });
  }

  syncFromMain();
});
