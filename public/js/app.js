/**
 * Main Application Logic
 */

class YouTubeApp {
  constructor() {
    this.currentView = 'trending'; // trending, search, history, bookmarks, downloads
    this.videos = [];
    this.history = JSON.parse(localStorage.getItem('yt_history') || '[]');
    this.bookmarks = JSON.parse(localStorage.getItem('yt_bookmarks') || '[]');
    
    this.player = null;
    this.currentVideo = null;

    this.initElements();
    this.bindEvents();
    this.loadTrending();
  }

  initElements() {
    this.contentArea = document.querySelector('.content-area');
    this.playerWrapper = document.getElementById('playerWrapper');
    this.searchInput = document.getElementById('searchInput');
    this.searchBtn = document.getElementById('searchBtn');
    this.videoGrid = document.getElementById('videoGrid');
    this.sectionTitle = document.getElementById('sectionTitle');
    this.tagChips = document.querySelectorAll('.tag-chip');
    this.navItems = document.querySelectorAll('.nav-item');
    this.watchOverlay = document.getElementById('watchOverlay');
    this.backBtn = document.getElementById('backBtn');
    this.toast = document.getElementById('toast');
    this.toastMessage = document.getElementById('toastMessage');

    // Download modal
    this.downloadModal = document.getElementById('downloadModal');
    this.downloadModalTitle = document.getElementById('downloadModalTitle');
    this.downloadOptionsList = document.getElementById('downloadOptionsList');
    this.closeModalBtn = document.getElementById('closeModalBtn');
    this.dlThumbImg = document.getElementById('dlThumbImg');
    this.dlDuration = document.getElementById('dlDuration');
    this.dlChannelName = document.getElementById('dlChannelName');
    this.dlViewsCount = document.getElementById('dlViewsCount');
    this.dlOpenFinderBtn = document.getElementById('dlOpenFinderBtn');

    // Watch view details
    this.watchTitle = document.getElementById('watchTitle');
    this.uploaderAvatar = document.getElementById('uploaderAvatar');
    this.uploaderName = document.getElementById('uploaderName');
    this.uploaderSubs = document.getElementById('uploaderSubs');
    this.videoViews = document.getElementById('videoViews');
    this.videoDate = document.getElementById('videoDate');
    this.videoDesc = document.getElementById('videoDesc');
    this.bookmarkBtn = document.getElementById('bookmarkBtn');
    this.downloadWatchBtn = document.getElementById('downloadWatchBtn');
    this.relatedList = document.getElementById('relatedList');

    // Initialize player
    this.player = new AdFreePlayer();

    // YouTube Shorts Feed Controller
    this.shortsFeedContainer = document.getElementById('shortsFeedContainer');
    this.shortsReel = document.getElementById('shortsReel');
    this.shortsPrevBtn = document.getElementById('shortsPrevBtn');
    this.shortsNextBtn = document.getElementById('shortsNextBtn');
    this.shortsController = new ShortsFeedController(this);

    window.app = this;
  }

  bindEvents() {
    this.shortsController.bindEvents();

    // Hamburger Menu Toggle Sidebar
    this.menuToggleBtn = document.getElementById('menuToggleBtn');
    this.sidebar = document.querySelector('.sidebar');
    if (this.menuToggleBtn && this.sidebar) {
      this.menuToggleBtn.addEventListener('click', () => {
        this.sidebar.classList.toggle('collapsed');
      });
    }

    // Search
    this.searchBtn.addEventListener('click', () => this.handleSearch());
    this.searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') this.handleSearch();
    });

    // Navigation items
    this.navItems.forEach(item => {
      item.addEventListener('click', (e) => {
        e.preventDefault();
        const view = item.dataset.view;
        this.switchView(view);
      });
    });

    // Category Tags
    this.tagChips.forEach(chip => {
      chip.addEventListener('click', () => {
        this.tagChips.forEach(c => c.classList.remove('active'));
        chip.classList.add('active');
        const query = chip.dataset.tag;
        if (query === 'all') {
          this.loadTrending();
        } else {
          this.searchInput.value = query;
          this.handleSearch(query);
        }
      });
    });

    // Watch view back
    this.backBtn.addEventListener('click', () => this.closeWatchView());

    // Description toggle
    this.videoDesc.addEventListener('click', () => {
      this.videoDesc.classList.toggle('expanded');
    });

    // Bookmark
    this.bookmarkBtn.addEventListener('click', () => this.toggleBookmark(this.currentVideo));

    // Subscribe Button
    this.subscribeBtn = document.getElementById('subscribeBtn');
    if (this.subscribeBtn) {
      this.subscribeBtn.addEventListener('click', () => {
        if (!this.currentVideo) return;
        const channel = this.currentVideo.uploader || 'Kênh YouTube';
        const isSub = this.subscribeBtn.classList.toggle('subscribed');
        this.subscribeBtn.textContent = isSub ? 'Đã đăng ký' : 'Đăng ký';
        this.showToast(isSub ? `🔔 Đã đăng ký kênh: ${channel}` : `Đã hủy đăng ký: ${channel}`);
      });
    }

    // Like Button
    this.likeBtn = document.getElementById('likeBtn');
    if (this.likeBtn) {
      this.likeBtn.addEventListener('click', () => {
        this.likeBtn.classList.toggle('active');
        this.showToast(this.likeBtn.classList.contains('active') ? '👍 Đã thích video' : 'Đã bỏ thích');
      });
    }

    // Share Button
    this.shareBtn = document.getElementById('shareBtn');
    if (this.shareBtn) {
      this.shareBtn.addEventListener('click', () => {
        if (!this.currentVideo) return;
        const ytUrl = `https://www.youtube.com/watch?v=${this.currentVideo.id}`;
        navigator.clipboard.writeText(ytUrl).then(() => {
          this.showToast('🔗 Đã sao chép liên kết video!');
        });
      });
    }

    // Download button in watch view
    this.downloadWatchBtn.addEventListener('click', () => {
      if (this.currentVideo) {
        this.openDownloadModal(this.currentVideo);
      }
    });

    // Modal controls
    if (this.closeModalBtn) {
      this.closeModalBtn.addEventListener('click', () => this.closeDownloadModal());
    }
    if (this.downloadModal) {
      this.downloadModal.addEventListener('click', (e) => {
        if (e.target === this.downloadModal) this.closeDownloadModal();
      });
    }

    if (this.dlOpenFinderBtn) {
      this.dlOpenFinderBtn.addEventListener('click', async () => {
        try {
          await fetch('/api/open-folder', { method: 'POST' });
          this.showToast('Đã mở thư mục tải về trong Finder');
        } catch (e) {
          this.showToast('Không thể mở Finder: ' + e.message);
        }
      });
    }

    const dlTabs = document.querySelectorAll('.dl-segmented-tabs .dl-tab');
    dlTabs.forEach(tab => {
      tab.addEventListener('click', () => {
        dlTabs.forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        const filter = tab.dataset.tab;
        const rows = document.querySelectorAll('#downloadOptionsList .dl-row');
        rows.forEach(r => {
          if (filter === 'all' || r.dataset.category === filter) {
            r.style.display = 'flex';
          } else {
            r.style.display = 'none';
          }
        });
      });
    });



    // Remote control listener from Menubar Mini Player
    if (window.electronAPI && window.electronAPI.onControl) {
      window.electronAPI.onControl(({ action, payload }) => {
        if (!this.player || !this.player.video) return;
        switch (action) {
          case 'togglePlay':
            this.player.togglePlay();
            break;
          case 'play':
            if (this.player.video.paused) this.player.video.play().catch(() => {});
            break;
          case 'pause':
            if (!this.player.video.paused) this.player.video.pause();
            break;
          case 'seek':
            if (typeof payload === 'number' && this.player.video.duration) {
              this.player.video.currentTime = payload;
              if (this.player.hasSeparateAudio && this.player.audio) {
                this.player.audio.currentTime = payload;
              }
              this.player.broadcastState();
            }
            break;
          case 'seekRelative':
            if (typeof payload === 'number' && this.player.video.duration) {
              const target = Math.max(0, Math.min(this.player.video.duration, this.player.video.currentTime + payload));
              this.player.video.currentTime = target;
              if (this.player.hasSeparateAudio && this.player.audio) {
                this.player.audio.currentTime = target;
              }
              this.player.broadcastState();
            }
            break;
          case 'toggleMute':
            this.player.toggleMute();
            break;
          case 'setVolume':
            if (typeof payload === 'number') {
              this.player.setVolume(payload);
            }
            break;
          case 'playVideo':
            if (payload && payload.id) {
              this.playVideoById(payload.id);
            }
            break;
          case 'toggleAudioOnly':
            if (this.player) {
              this.player.toggleAudioOnly();
            }
            break;
          case 'setQuality':
            if (this.player && payload) {
              this.player.setQuality(payload);
            }
            break;
        }
      });
    }

    if (window.electronAPI && window.electronAPI.onPlayVideo) {
      window.electronAPI.onPlayVideo(({ videoId, currentTime, isPlaying }) => {
        if (!videoId) return;
        if (this.player && this.player.currentVideoId === videoId) {
          if (typeof currentTime === 'number') {
            this.player.video.currentTime = currentTime;
            if (this.player.hasSeparateAudio && this.player.audio) {
              this.player.audio.currentTime = currentTime;
            }
          }
          if (isPlaying) {
            this.player.video.play().catch(() => {});
          } else {
            this.player.video.pause();
          }
        } else {
          this.playVideoById(videoId, currentTime || 0);
        }
      });
    }

    this.checkAccountStatus();
  }

  async checkAccountStatus() {
    try {
      const res = await fetch('/api/account/status');
      const data = await res.json();
      if (data.loggedIn && this.accountBtnText) {
        this.accountBtnText.textContent = 'Đã Đăng Nhập ✓';
      }
    } catch (e) {}
  }

  switchView(view) {
    this.currentView = view;
    this.closeWatchView(false);

    this.navItems.forEach(i => {
      i.classList.toggle('active', i.dataset.view === view);
    });

    if (view === 'shorts') {
      if (this.player && this.player.video && !this.player.video.paused) {
        this.player.video.pause();
      }
      this.contentArea.classList.add('shorts-mode');
      if (this.shortsFeedContainer) this.shortsFeedContainer.style.display = 'flex';
      this.shortsController.open();
    } else {
      this.contentArea.classList.remove('shorts-mode');
      if (this.shortsFeedContainer) this.shortsFeedContainer.style.display = 'none';
      if (this.shortsController) this.shortsController.close();

      if (view === 'trending') {
        this.sectionTitle.textContent = 'Thịnh hành';
        this.loadTrending();
      } else if (view === 'subscriptions') {
        this.sectionTitle.textContent = 'Kênh Đăng Ký (Theo Dõi)';
        this.loadSubscriptions();
      } else if (view === 'history') {
        this.sectionTitle.textContent = 'Video Đã Xem';
        this.renderVideoGrid(this.history);
      } else if (view === 'bookmarks') {
        this.sectionTitle.textContent = 'Danh Sách Xem Sau';
        this.renderVideoGrid(this.bookmarks);
      } else if (view === 'downloads') {
        this.sectionTitle.textContent = 'Tệp Đã Tải Về';
        this.loadDownloadsList();
      }
    }
  }

  async loadSubscriptions() {
    this.sectionTitle.textContent = 'Kênh đăng ký';
    this.videoGrid.innerHTML = `
      <div style="grid-column: 1/-1; text-align: center; padding: 60px 20px; color: #aaa;">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="currentColor" style="opacity: 0.5; margin-bottom: 12px;"><path d="M18.7 8.7H5.3V7h13.4v1.7zm-1.7-5H7v1.7h10V3.7zm3.4 8.3v10H3.6V12h16.8zm-1.7 1.7H5.3v6.6h11.7v-6.6zM10 14.2l4.5 2.3-4.5 2.3v-4.6z"/></svg>
        <h3 style="color: #fff; font-size: 18px; margin-bottom: 8px;">Kênh đăng ký</h3>
        <p style="font-size: 14px; margin-bottom: 16px;">Xem mọi video trực tiếp không cần đăng nhập tài khoản.</p>
      </div>
    `;
  }

  async loadTrending() {
    this.sectionTitle.textContent = 'Thịnh hành';
    this.videoGrid.innerHTML = `<div style="grid-column: 1/-1; text-align: center; padding: 40px; color: var(--yt-spec-text-secondary);">Đang tải video...</div>`;
    try {
      const res = await fetch('/api/trending');
      const data = await res.json();
      if (data.success && data.videos) {
        this.videos = data.videos;
        this.renderVideoGrid(this.videos);
        if (data.personalized) {
          this.sectionTitle.textContent = 'Trang chủ (Gợi ý theo tài khoản của bạn)';
        }
      } else {
        throw new Error(data.error || 'Failed to fetch trending');
      }
    } catch (err) {
      this.videoGrid.innerHTML = `<div style="grid-column: 1/-1; text-align: center; padding: 40px; color: #ff5252;">Không thể kết nối danh sách thịnh hành: ${err.message}</div>`;
    }
  }

  renderSearchSkeletons() {
    let html = '';
    for (let i = 0; i < 6; i++) {
      html += `
        <div class="search-skeleton-card">
          <div class="skeleton-thumb"></div>
          <div class="skeleton-info">
            <div class="skeleton-line title"></div>
            <div class="skeleton-line meta"></div>
            <div class="skeleton-line channel"></div>
            <div class="skeleton-line snippet"></div>
          </div>
        </div>
      `;
    }
    this.videoGrid.className = 'search-results-list';
    this.videoGrid.innerHTML = html;
  }

  async handleSearch(queryOverride) {
    const query = queryOverride || this.searchInput.value.trim();
    if (!query) return;

    this.currentView = 'search';
    this.closeWatchView(false);
    this.sectionTitle.textContent = `🔍 Kết quả tìm kiếm: "${query}"`;
    this.renderSearchSkeletons();

    try {
      const res = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
      const data = await res.json();
      if (data.success && data.videos) {
        this.videos = data.videos;
        this.renderSearchResults(data.channel, this.videos);
      } else {
        throw new Error(data.error || 'Không tìm thấy video');
      }
    } catch (err) {
      this.videoGrid.innerHTML = `<div style="text-align: center; padding: 60px 20px; color: #ff5252;">Lỗi tìm kiếm: ${err.message}</div>`;
    }
  }

  renderSearchResults(channel, items) {
    if ((!items || items.length === 0) && !channel) {
      this.videoGrid.innerHTML = `<div style="text-align: center; padding: 60px 20px; color: var(--text-muted);">Không tìm thấy kết quả nào.</div>`;
      return;
    }

    let html = '';

    // 1. Channel Hero Card (matching YouTube)
    if (channel) {
      html += `
        <div class="channel-hero-card">
          <div class="channel-hero-avatar-wrap">
            <img src="${channel.avatar}" class="channel-hero-avatar" alt="${this.escapeHtml(channel.title)}">
          </div>
          <div class="channel-hero-info">
            <h2 class="channel-hero-title">${this.escapeHtml(channel.title)}</h2>
            <div class="channel-hero-meta">
              ${channel.handle ? `<span class="channel-handle">${this.escapeHtml(channel.handle)}</span>` : ''}
              ${channel.handle && channel.subscribers ? `<span class="meta-dot">•</span>` : ''}
              <span class="channel-subscribers">${this.escapeHtml(channel.subscribers)}</span>
            </div>
            ${channel.description ? `<p class="channel-hero-desc">${this.escapeHtml(channel.description)}</p>` : ''}
          </div>
          <div class="channel-hero-action">
            <button class="channel-subscribe-btn">Đăng ký</button>
          </div>
        </div>
      `;
    }

    // 2. Horizontal Video Cards
    if (items && items.length > 0) {
      html += items.map(video => {
        const durationFormatted = this.formatDuration(video.duration);
        const initial = (video.uploader || 'Y').trim()[0].toUpperCase();

        return `
          <div class="search-video-card" data-id="${video.id}">
            <div class="search-thumb-wrap">
              <img src="${video.thumbnail}" alt="${this.escapeHtml(video.title)}" loading="lazy" />
              ${durationFormatted ? `<span class="duration-badge">${durationFormatted}</span>` : ''}
            </div>
            <div class="search-details">
              <h3 class="search-video-title" title="${this.escapeHtml(video.title)}">${this.escapeHtml(video.title)}</h3>
              <div class="search-meta-row">
                <span class="search-views">${this.formatViews(video.viewCount)}</span>
                ${video.publishedTime ? `<span class="meta-dot">•</span><span class="search-time">${this.escapeHtml(video.publishedTime)}</span>` : ''}
              </div>
              <div class="search-channel-row">
                ${video.avatar ? `<img src="${video.avatar}" class="search-avatar" alt="${this.escapeHtml(video.uploader)}">` : `<div class="channel-avatar-sm">${initial}</div>`}
                <span class="search-uploader">${this.escapeHtml(video.uploader || 'YouTube')}</span>
              </div>
              ${video.description ? `<p class="search-snippet">${this.escapeHtml(video.description)}</p>` : ''}
            </div>
          </div>
        `;
      }).join('');
    }

    this.videoGrid.innerHTML = html;

    // Attach click and hover prefetch handlers
    this.videoGrid.querySelectorAll('.search-video-card').forEach(card => {
      const id = card.dataset.id;
      card.addEventListener('mouseenter', () => {
        if (id) fetch(`/api/stream?v=${id}&quality=720`).catch(() => {});
      }, { once: true });
      card.addEventListener('click', () => {
        const video = items.find(v => v.id === id);
        if (video) this.openWatchView(video);
      });
    });
  }

  renderVideoGrid(items) {
    this.videoGrid.className = 'video-grid';
    if (!items || items.length === 0) {
      this.videoGrid.innerHTML = `<div style="grid-column: 1/-1; text-align: center; padding: 60px 20px; color: var(--text-muted);">Chưa có video nào ở đây.</div>`;
      return;
    }

    this.videoGrid.innerHTML = items.map(video => {
      const durationFormatted = this.formatDuration(video.duration);
      const initial = (video.uploader || 'Y').trim()[0].toUpperCase();

      return `
        <div class="video-card" data-id="${video.id}">
          <div class="thumbnail-wrap">
            <img src="${video.thumbnail}" alt="${this.escapeHtml(video.title)}" loading="lazy" />
            ${durationFormatted ? `<span class="duration-badge">${durationFormatted}</span>` : ''}
          </div>
          <div class="card-info">
            <div class="channel-avatar">${initial}</div>
            <div class="card-details">
              <h3 class="video-title" title="${this.escapeHtml(video.title)}">${this.escapeHtml(video.title)}</h3>
              <div class="channel-name">${this.escapeHtml(video.uploader || 'YouTube')}</div>
              <div class="video-meta">
                <span>${this.formatViews(video.viewCount)}</span>
              </div>
            </div>
          </div>
        </div>
      `;
    }).join('');

    // Attach click and hover prefetch handlers
    this.videoGrid.querySelectorAll('.video-card').forEach(card => {
      const id = card.dataset.id;
      card.addEventListener('mouseenter', () => {
        if (id) fetch(`/api/stream?v=${id}&quality=720`).catch(() => {});
      }, { once: true });
      card.addEventListener('click', () => {
        const video = items.find(v => v.id === id);
        if (video) this.openWatchView(video);
      });
    });
  }

  async openWatchView(video) {
    if (this.shortsController) {
      this.shortsController.close();
    }
    if (this.shortsFeedContainer) {
      this.shortsFeedContainer.style.display = 'none';
    }
    if (this.contentArea && !this.contentArea.classList.contains('watching')) {
      this.savedScrollTop = this.contentArea.scrollTop || 0;
    }
    this.currentVideo = video;
    if (this.contentArea) {
      this.contentArea.classList.add('watching');
      this.contentArea.scrollTop = 0;
    }
    this.watchOverlay.classList.add('active');
    this.watchOverlay.scrollTop = 0;
    window.scrollTo({ top: 0, behavior: 'instant' });

    // Smoothly ensure watch overlay is scrolled to top without displacing the fixed top bar
    if (this.watchOverlay) {
      this.watchOverlay.scrollTop = 0;
    }
    if (this.contentArea) {
      this.contentArea.scrollTop = 0;
    }
    window.scrollTo({ top: 0, behavior: 'instant' });

    // Add to history
    this.addToHistory(video);

    // Populate initial metadata
    this.watchTitle.textContent = video.title;
    this.uploaderName.textContent = video.uploader || 'Kênh YouTube';
    this.uploaderAvatar.textContent = (video.uploader || 'Y')[0].toUpperCase();
    this.videoViews.textContent = this.formatViews(video.viewCount);
    this.videoDesc.textContent = video.description || 'Đang tải thông tin chi tiết...';

    this.updateBookmarkButtonState();
    this.renderRelatedVideos(video.id);

    // Start stream immediately at 0ms with autoPlay
    const preferredQuality = localStorage.getItem('yt_preferred_quality') || this.player.qualitySelect.value || '1080';
    const initialQuality = (preferredQuality !== 'audio') ? preferredQuality : '1080';
    this.player.exitMiniplayer();
    if (video.thumbnail) {
      this.player.setPoster(video.thumbnail);
    }
    this.player.loadStream(video.id, initialQuality, 0, true);

    // Fetch full details & SponsorBlock asynchronously in background (never blocks playback!)
    fetch(`/api/info?v=${video.id}`)
      .then(res => res.json())
      .then(data => {
        if (this.currentVideo && this.currentVideo.id !== video.id) return;
        if (data.success && data.info) {
          const info = data.info;
          this.watchTitle.textContent = info.title;
          this.uploaderName.textContent = info.uploader;
          this.videoViews.textContent = `${this.formatViews(info.viewCount)} lượt xem`;
          if (info.description) this.videoDesc.textContent = info.description;

          let heights = info.availableResolutions || [];
          if (!heights || heights.length === 0) {
            heights = [...new Set(
              (info.formats || [])
                .map(f => f.height)
                .filter(h => typeof h === 'number' && h >= 144)
            )].sort((a, b) => b - a);
          }

          if (heights.length > 0) {
            this.updateQualityOptions(heights);
          }

          if (data.sponsorSegments && data.sponsorSegments.length > 0) {
            this.player.setSponsorSegments(data.sponsorSegments);
            this.showToast(`🛡️ Đã tải ${data.sponsorSegments.length} phân đoạn SponsorBlock`);
          } else {
            this.player.setSponsorSegments([]);
          }
        }
      })
      .catch(err => {
        console.warn('Metadata fetch note:', err);
      });
  }

  updateQualityOptions(heights) {
    if (!this.player || !this.player.qualitySelect) return;
    const select = this.player.qualitySelect;
    const preferred = localStorage.getItem('yt_preferred_quality') || '1080';
    const currentActive = this.player.currentQuality || preferred;

    const qualityLabels = {
      2160: '4K Ultra HD (2160p)',
      1440: '2K Quad HD (1440p)',
      1080: '1080p Full HD',
      720: '720p HD',
      480: '480p',
      360: '360p',
      240: '240p',
      144: '144p'
    };

    // Normalize all input heights to unique integers in descending order
    const numHeights = [...new Set(
      (heights || [])
        .map(h => (typeof h === 'number' ? h : parseInt(h, 10)))
        .filter(h => !isNaN(h) && h >= 144)
    )].sort((a, b) => b - a);

    const standardHeights = [2160, 1440, 1080, 720, 480, 360, 240, 144];
    let available = standardHeights.filter(h => numHeights.includes(h));
    if (numHeights.length > 0) {
      const maxH = Math.max(...numHeights);
      available = standardHeights.filter(h => h <= maxH);
    }
    if (available.length === 0) {
      available = [1080, 720, 480, 360, 240, 144];
    }

    // Determine which option should be active:
    let selectedQuality = available[0]; // fallback highest
    if (this.player.isAudioOnly || currentActive === 'audio') {
      selectedQuality = 'audio';
    } else {
      const activeNum = parseInt(currentActive, 10);
      if (!isNaN(activeNum)) {
        if (available.includes(activeNum)) {
          selectedQuality = activeNum;
        } else {
          // If video doesn't reach activeNum, pick closest available <= activeNum
          const match = available.find(h => h <= activeNum) || available[0];
          selectedQuality = match;
        }
      }
    }

    select.innerHTML = '';
    available.forEach(h => {
      const opt = document.createElement('option');
      opt.value = h.toString();
      opt.textContent = qualityLabels[h] || `${h}p`;
      if (h.toString() === selectedQuality.toString()) opt.selected = true;
      select.appendChild(opt);
    });

    // Add audio-only option
    const audioOpt = document.createElement('option');
    audioOpt.value = 'audio';
    audioOpt.textContent = 'Chỉ Audio';
    if (selectedQuality === 'audio') audioOpt.selected = true;
    select.appendChild(audioOpt);

    select.value = selectedQuality.toString();
    return selectedQuality.toString();
  }

  renderRelatedVideos(currentVideoId) {
    if (!this.relatedList) return;
    const related = (this.videos || []).filter(v => v.id !== currentVideoId).slice(0, 15);
    
    this.relatedList.innerHTML = related.map(v => {
      const duration = this.formatDuration(v.duration);
      return `
        <div class="related-card" data-id="${v.id}">
          <div class="related-thumb">
            <img src="${v.thumbnail}" alt="${this.escapeHtml(v.title)}" loading="lazy" />
            ${duration ? `<span class="duration-badge">${duration}</span>` : ''}
          </div>
          <div class="related-info">
            <div class="related-title">${this.escapeHtml(v.title)}</div>
            <div class="related-channel">${this.escapeHtml(v.uploader || 'YouTube')}</div>
            <div class="related-meta">${this.formatViews(v.viewCount)} lượt xem</div>
          </div>
        </div>
      `;
    }).join('');

    this.relatedList.querySelectorAll('.related-card').forEach(card => {
      const id = card.dataset.id;
      card.addEventListener('mouseenter', () => {
        if (id) fetch(`/api/stream?v=${id}&quality=720`).catch(() => {});
      }, { once: true });
      card.addEventListener('click', () => {
        const targetVideo = (this.videos || []).find(v => v.id === id);
        if (targetVideo) {
          this.openWatchView(targetVideo);
        }
      });
    });
  }

  reopenWatchView() {
    if (this.contentArea) {
      this.contentArea.classList.add('watching');
      this.contentArea.scrollTop = 0;
    }
    this.watchOverlay.classList.add('active');
    this.watchOverlay.scrollTop = 0;
    if (this.player) {
      this.player.exitMiniplayer();
    }
    window.scrollTo({ top: 0, behavior: 'instant' });
  }

  closeWatchView(allowMiniplayer = true) {
    if (this.contentArea) {
      this.contentArea.classList.remove('watching');
      if (typeof this.savedScrollTop === 'number') {
        this.contentArea.scrollTop = this.savedScrollTop;
      }
    }
    this.watchOverlay.classList.remove('active');
    if (this.player && this.player.video) {
      if (allowMiniplayer && !this.player.video.paused) {
        // Enter YouTube style miniplayer
        this.player.enterMiniplayer(this.currentVideo?.title || 'Đang phát');
      } else {
        this.player.exitMiniplayer();
        this.player.video.pause();
      }
    }
  }

  addToHistory(video) {
    this.history = this.history.filter(v => v.id !== video.id);
    this.history.unshift(video);
    if (this.history.length > 50) this.history.pop();
    localStorage.setItem('yt_history', JSON.stringify(this.history));
  }

  toggleBookmark(video) {
    if (!video) return;
    const exists = this.bookmarks.some(b => b.id === video.id);
    if (exists) {
      this.bookmarks = this.bookmarks.filter(b => b.id !== video.id);
      this.showToast('Đã xóa khỏi danh sách Xem sau');
    } else {
      this.bookmarks.unshift(video);
      this.showToast('Đã thêm vào danh sách Xem sau');
    }
    localStorage.setItem('yt_bookmarks', JSON.stringify(this.bookmarks));
    this.updateBookmarkButtonState();
  }

  updateBookmarkButtonState() {
    if (!this.currentVideo || !this.bookmarkBtn) return;
    const exists = this.bookmarks.some(b => b.id === this.currentVideo.id);
    if (exists) {
      this.bookmarkBtn.classList.add('bookmarked');
      this.bookmarkBtn.innerHTML = `
        <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>
        <span>Đã lưu</span>
      `;
      this.bookmarkBtn.style.color = '';
    } else {
      this.bookmarkBtn.classList.remove('bookmarked');
      this.bookmarkBtn.innerHTML = `
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>
        <span>Lưu video</span>
      `;
      this.bookmarkBtn.style.color = '';
    }
  }

  openDownloadModal(video) {
    this.selectedForDownload = video;

    // 1. Populate Preview Card
    const thumbImg = document.getElementById('dlModalThumb');
    const durBadge = document.getElementById('dlModalDuration');
    const titleEl = document.getElementById('downloadModalTitle');
    const authorEl = document.getElementById('dlModalAuthor');
    const viewsEl = document.getElementById('dlModalViews');

    if (thumbImg) {
      thumbImg.src = video.thumbnail || (video.id ? `https://i.ytimg.com/vi/${video.id}/hqdefault.jpg` : '');
    }
    if (durBadge) {
      durBadge.textContent = typeof video.duration === 'string' ? video.duration : (video.duration ? `${Math.floor(video.duration/60)}:${String(Math.floor(video.duration%60)).padStart(2, '0')}` : '0:00');
    }
    if (titleEl) {
      titleEl.textContent = video.title || 'Video YouTube';
    }
    if (authorEl) {
      authorEl.textContent = video.uploader || video.author || 'YouTube';
    }
    if (viewsEl) {
      viewsEl.textContent = video.viewCount ? (typeof video.viewCount === 'number' ? `${video.viewCount.toLocaleString()} lượt xem` : `${video.viewCount}`) : 'YouTube';
    }

    // 2. Calculate realistic sizes
    let durSecs = 240;
    if (video.duration) {
      if (typeof video.duration === 'number') {
        durSecs = video.duration;
      } else {
        const parts = video.duration.split(':').map(Number);
        if (parts.length === 3) durSecs = parts[0] * 3600 + parts[1] * 60 + parts[2];
        else if (parts.length === 2) durSecs = parts[0] * 60 + parts[1];
      }
    }

    const calcSize = (rateMBPerSec) => {
      const mb = Math.round(durSecs * rateMBPerSec);
      if (mb >= 1000) return `${(mb / 1024).toFixed(1)} GB`;
      return `${Math.max(1, mb)} MB`;
    };

    const videoTiers = [
      { format: '1080', res: '1080p Full HD', spec: '1920 × 1080 · H.264', size: calcSize(0.35), type: 'video' },
      { format: '720', res: '720p HD', spec: '1280 × 720 · H.264', size: calcSize(0.20), type: 'video' },
      { format: '480', res: '480p Tiêu chuẩn', spec: '854 × 480 · H.264', size: calcSize(0.11), type: 'video' },
      { format: '360', res: '360p Tiết kiệm', spec: '640 × 360 · H.264', size: calcSize(0.06), type: 'video' }
    ];

    const audioTiers = [
      { format: 'mp3', res: 'MP3 Chất lượng cao', spec: '320 kbps · 48 kHz Stereo', size: calcSize(0.04), type: 'audio' },
      { format: 'm4a', res: 'M4A Bitstream gốc', spec: '128 kbps · AAC Siêu nhẹ', size: calcSize(0.016), type: 'audio' }
    ];

    let currentTab = 'video';
    let selectedTier = videoTiers[0];

    const tabVideoBtn = document.getElementById('dlTabVideo');
    const tabAudioBtn = document.getElementById('dlTabAudio');
    const submitBtn = document.getElementById('dlSubmitBtn');
    const submitBtnText = document.getElementById('dlSubmitBtnText');

    if (tabVideoBtn && tabAudioBtn) {
      tabVideoBtn.classList.add('active');
      tabAudioBtn.classList.remove('active');
    }

    const updateSubmitText = () => {
      if (!submitBtnText) return;
      if (selectedTier.type === 'video') {
        submitBtnText.textContent = `Tải xuống ${selectedTier.format}p MP4 (${selectedTier.size})`;
      } else {
        submitBtnText.textContent = `Tải xuống ${selectedTier.res} (${selectedTier.size})`;
      }
    };

    const renderList = () => {
      const tiers = currentTab === 'video' ? videoTiers : audioTiers;
      if (!this.downloadOptionsList) return;

      this.downloadOptionsList.innerHTML = tiers.map(t => {
        const isSelected = selectedTier.format === t.format;
        return `
          <div class="dl-option-card ${isSelected ? 'selected' : ''}" data-format="${t.format}">
            <div class="dl-card-left">
              <div class="dl-radio-circle">
                <div class="dl-radio-dot"></div>
              </div>
              <div class="dl-card-details">
                <span class="dl-card-res">${t.res}</span>
                <span class="dl-card-spec">${t.spec}</span>
              </div>
            </div>
            <div class="dl-card-right">
              <span class="dl-card-size">${t.size}</span>
            </div>
          </div>
        `;
      }).join('');

      this.downloadOptionsList.querySelectorAll('.dl-option-card').forEach(card => {
        card.addEventListener('click', () => {
          const fmt = card.dataset.format;
          const matched = tiers.find(t => t.format === fmt);
          if (matched) {
            selectedTier = matched;
            renderList();
            updateSubmitText();
          }
        });
      });
    };

    if (tabVideoBtn && tabAudioBtn) {
      tabVideoBtn.onclick = () => {
        if (currentTab === 'video') return;
        currentTab = 'video';
        tabVideoBtn.classList.add('active');
        tabAudioBtn.classList.remove('active');
        selectedTier = videoTiers[0];
        renderList();
        updateSubmitText();
      };
      tabAudioBtn.onclick = () => {
        if (currentTab === 'audio') return;
        currentTab = 'audio';
        tabAudioBtn.classList.add('active');
        tabVideoBtn.classList.remove('active');
        selectedTier = audioTiers[0];
        renderList();
        updateSubmitText();
      };
    }

    if (submitBtn) {
      submitBtn.onclick = () => {
        this.triggerDownload(selectedTier.format);
      };
    }

    renderList();
    updateSubmitText();

    this.downloadModal.classList.add('active');
  }

  closeDownloadModal() {
    this.downloadModal.classList.remove('active');
  }

  async triggerDownload(format) {
    if (!this.selectedForDownload) return;
    const video = this.selectedForDownload;
    this.closeDownloadModal();
    const formatLabel = format === 'mp3' ? 'Âm thanh MP3' : `${format}p MP4`;
    this.showToast(`Bắt đầu tải ${formatLabel} về máy...`);

    try {
      const res = await fetch('/api/download', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          videoId: video.id,
          format: format,
          title: video.title
        })
      });
      const data = await res.json();
      if (data.success) {
        this.showToast(`Đã thêm vào tiến trình tải (Lưu tại ~/Downloads/YouTube_Adfree)`);
      } else {
        throw new Error(data.error);
      }
    } catch (err) {
      this.showToast(`Lỗi tải về: ${err.message}`);
    }
  }

  async loadDownloadsList() {
    this.videoGrid.innerHTML = `<div style="grid-column: 1/-1; text-align: center; padding: 40px; color: var(--text-secondary);">Đang kiểm tra thư mục tải về...</div>`;
    try {
      const res = await fetch('/api/downloads');
      const data = await res.json();
      if (data.success) {
        if (data.downloads.length === 0) {
          this.videoGrid.innerHTML = `
            <div style="grid-column: 1/-1; text-align: center; padding: 40px; color: var(--text-muted);">
              <p>Chưa có file nào đang tải.</p>
              <p style="margin-top: 8px; font-size: 13px;">Thư mục lưu mặc định: <strong style="color: #fff;">${data.downloadDir}</strong></p>
            </div>
          `;
        } else {
          this.videoGrid.innerHTML = data.downloads.map(d => `
            <div style="background: var(--bg-surface); padding: 18px; border-radius: 12px; border: 1px solid var(--border-subtle); display: flex; flex-direction: column; gap: 8px;">
              <div style="font-weight: 600; font-size: 14px;">${this.escapeHtml(d.title)}</div>
              <div style="font-size: 12px; color: var(--text-secondary);">Định dạng: ${d.format.toUpperCase()} • Trạng thái: ${d.status}</div>
              <div style="width: 100%; height: 6px; background: rgba(255,255,255,0.1); border-radius: 3px; overflow: hidden;">
                <div style="width: ${d.progress}%; height: 100%; background: var(--primary);"></div>
              </div>
              <div style="font-size: 11px; color: var(--text-muted);">${d.progress}%</div>
            </div>
          `).join('');
        }
      }
    } catch (err) {
      this.videoGrid.innerHTML = `<div style="grid-column: 1/-1; color: #ff5252;">Lỗi: ${err.message}</div>`;
    }
  }

  showToast(message) {
    this.toastMessage.textContent = message;
    this.toast.classList.add('show');
    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => {
      this.toast.classList.remove('show');
    }, 3500);
  }

  formatDuration(seconds) {
    if (!seconds) return '';
    if (typeof seconds === 'string' && seconds.includes(':')) {
      return seconds;
    }
    const s = parseInt(seconds, 10);
    if (isNaN(s)) return '';
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    const hours = Math.floor(mins / 60);
    const remMins = mins % 60;
    if (hours > 0) {
      return `${hours}:${remMins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  formatViews(views) {
    if (!views) return '';
    if (typeof views === 'string' && (views.includes('lượt xem') || views.includes('views') || views.includes('trực tiếp') || views.includes('watching'))) {
      return views;
    }
    const n = parseInt(views, 10);
    if (isNaN(n)) return views;
    if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M lượt xem';
    if (n >= 1000) return (n / 1000).toFixed(1) + 'K lượt xem';
    return n + ' lượt xem';
  }

  escapeHtml(str) {
    if (!str) return '';
    return str.replace(/[&<>'"]/g, 
      tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag)
    );
  }

  async playVideoById(videoId, startTime = 0) {
    try {
      const res = await fetch(`/api/info?v=${videoId}`);
      const data = await res.json();
      if (data.success && data.info) {
        this.openWatchView(data.info);
        if (startTime > 0 && this.player && this.player.video) {
          this.player.video.currentTime = startTime;
        }
      }
    } catch (e) {
      console.warn('playVideoById error:', e);
    }
  }
}

/**
 * YouTube Shorts Vertical Reel Controller (Exact YouTube Native UX)
 */
class ShortsFeedController {
  constructor(app) {
    this.app = app;
    this.container = null;
    this.reel = null;
    this.prevBtn = null;
    this.nextBtn = null;
    this.shorts = [];
    this.currentIndex = 0;
    this.isOpen = false;
    this.isLoading = false;
    this.currentPage = 1;
    this.isMuted = false;
    this.lastWheelTime = 0;
    this.touchStartY = 0;
    this.observer = null;
    this.likes = new Set();
    this.dislikes = new Set();
    this.subscribers = new Set();
  }

  bindEvents() {
    this.container = this.app.shortsFeedContainer;
    this.reel = this.app.shortsReel;
    this.prevBtn = this.app.shortsPrevBtn;
    this.nextBtn = this.app.shortsNextBtn;

    if (this.prevBtn) {
      this.prevBtn.addEventListener('click', () => {
        this.goToIndex(this.currentIndex - 1);
      });
    }

    if (this.nextBtn) {
      this.nextBtn.addEventListener('click', () => {
        this.goToIndex(this.currentIndex + 1);
      });
    }

    // Wheel navigation (debounced snap)
    if (this.reel) {
      this.reel.addEventListener('wheel', (e) => {
        if (!this.isOpen) return;
        if (Math.abs(e.deltaY) < 25) return;
        const now = Date.now();
        if (now - this.lastWheelTime < 380) {
          e.preventDefault();
          return;
        }
        this.lastWheelTime = now;
        e.preventDefault();
        if (e.deltaY > 0) {
          this.goToIndex(this.currentIndex + 1);
        } else {
          this.goToIndex(this.currentIndex - 1);
        }
      }, { passive: false });

      // Touch swipe
      this.reel.addEventListener('touchstart', (e) => {
        if (!this.isOpen) return;
        if (e.touches && e.touches[0]) {
          this.touchStartY = e.touches[0].clientY;
        }
      }, { passive: true });

      this.reel.addEventListener('touchend', (e) => {
        if (!this.isOpen) return;
        if (e.changedTouches && e.changedTouches[0]) {
          const touchEndY = e.changedTouches[0].clientY;
          const delta = this.touchStartY - touchEndY;
          if (Math.abs(delta) > 50) {
            if (delta > 0) {
              this.goToIndex(this.currentIndex + 1);
            } else {
              this.goToIndex(this.currentIndex - 1);
            }
          }
        }
      }, { passive: true });
    }

    // Keyboard navigation
    window.addEventListener('keydown', (e) => {
      if (!this.isOpen) return;
      if (['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;

      if (e.key === 'ArrowDown' || e.key === 'PageDown' || e.key === 'j') {
        e.preventDefault();
        this.goToIndex(this.currentIndex + 1);
      } else if (e.key === 'ArrowUp' || e.key === 'PageUp' || e.key === 'k') {
        e.preventDefault();
        this.goToIndex(this.currentIndex - 1);
      } else if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        this.togglePlayPauseCurrent();
      } else if (e.key === 'm' || e.key === 'M') {
        e.preventDefault();
        this.toggleMute();
      }
    });

    this.setupObserver();
  }

  setupObserver() {
    if (!this.reel) return;
    if (this.observer) this.observer.disconnect();

    this.observer = new IntersectionObserver((entries) => {
      if (!this.isOpen) return;
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const idx = parseInt(entry.target.dataset.index, 10);
          if (!isNaN(idx) && idx !== this.currentIndex) {
            this.currentIndex = idx;
            this.updateNavButtons();
            this.playActiveShort();
            this.checkInfiniteLoad();
          }
        }
      });
    }, {
      root: this.reel,
      threshold: 0.65
    });
  }

  async open() {
    this.isOpen = true;
    if (this.shorts.length === 0) {
      await this.loadInitialShorts();
    } else {
      this.playActiveShort();
    }
  }

  close() {
    this.isOpen = false;
    this.pauseAll();
  }

  async loadInitialShorts() {
    if (this.isLoading) return;
    this.isLoading = true;
    this.currentPage = 1;
    this.reel.innerHTML = `<div style="display:flex; flex-direction:column; align-items:center; justify-content:center; height:60vh; color:#aaa; font-size:15px; gap:16px;">
      <div class="short-spinner active" style="position:static; transform:none;"></div>
      <span>Đang tải YouTube Shorts chất lượng cao...</span>
    </div>`;

    try {
      const res = await fetch('/api/shorts?page=1');
      const data = await res.json();
      if (data.success && data.videos && data.videos.length > 0) {
        this.shorts = data.videos;
        this.renderAllShorts();
        this.currentIndex = 0;
        this.updateNavButtons();
        setTimeout(() => {
          this.goToIndex(0, false);
        }, 60);
      } else {
        throw new Error('Không có video Shorts nào từ hệ thống');
      }
    } catch (err) {
      this.reel.innerHTML = `<div style="text-align:center; padding: 80px 20px; color: #ff5252; font-size:15px;">Không thể tải Shorts: ${err.message}</div>`;
    } finally {
      this.isLoading = false;
    }
  }

  async loadMoreShorts() {
    if (this.isLoading) return;
    this.isLoading = true;
    this.currentPage++;

    try {
      const res = await fetch(`/api/shorts?page=${this.currentPage}`);
      const data = await res.json();
      if (data.success && data.videos && data.videos.length > 0) {
        const newVideos = data.videos.filter(nv => !this.shorts.some(s => s.id === nv.id));
        if (newVideos.length > 0) {
          const startIdx = this.shorts.length;
          this.shorts.push(...newVideos);
          newVideos.forEach((v, i) => {
            const itemEl = this.createShortItemElement(v, startIdx + i);
            this.reel.appendChild(itemEl);
            if (this.observer) this.observer.observe(itemEl);
          });
          this.updateNavButtons();
        }
      }
    } catch (e) {
      console.warn('loadMoreShorts failed:', e);
    } finally {
      this.isLoading = false;
    }
  }

  checkInfiniteLoad() {
    if (this.currentIndex >= this.shorts.length - 3) {
      this.loadMoreShorts();
    }
  }

  renderAllShorts() {
    this.reel.innerHTML = '';
    this.shorts.forEach((v, idx) => {
      const itemEl = this.createShortItemElement(v, idx);
      this.reel.appendChild(itemEl);
      if (this.observer) this.observer.observe(itemEl);
    });
  }

  createShortItemElement(v, idx) {
    const item = document.createElement('div');
    item.className = 'short-reel-item';
    item.dataset.id = v.id;
    item.dataset.index = idx;

    const viewsFormatted = this.app.formatViews ? this.app.formatViews(v.viewCount) : (v.viewCount || '100N');
    const isLiked = this.likes.has(v.id);
    const isSubscribed = this.subscribers.has(v.uploader);

    item.innerHTML = `
      <div class="short-main-wrapper">
        <div class="short-player-card">
          <video class="short-video" playsinline loop preload="none"></video>
          <audio class="short-audio" loop></audio>
          <img src="${v.thumbnail}" alt="${this.escapeHtml(v.title)}" class="short-poster-img" loading="lazy" />
          <div class="short-spinner"></div>
          <div class="short-play-indicator">
            <svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
          </div>
          <div class="short-top-bar">
            <button class="short-mute-btn" title="Bật/Tắt âm thanh (M)">
              ${this.getVolumeSvg(this.isMuted)}
            </button>
          </div>
          <div class="short-bottom-overlay">
            <div class="short-channel-row">
              <img src="${v.avatar}" alt="${this.escapeHtml(v.uploader)}" class="short-channel-avatar" onerror="this.src='https://ui-avatars.com/api/?name=YT&background=ff0033&color=fff'" />
              <span class="short-channel-name" title="${this.escapeHtml(v.uploader)}">${this.escapeHtml(v.uploader)}</span>
              <button class="short-sub-btn ${isSubscribed ? 'subscribed' : ''}">
                ${isSubscribed ? 'Đã đăng ký' : 'Đăng ký'}
              </button>
            </div>
            <div class="short-title-text" title="${this.escapeHtml(v.title)}">${this.escapeHtml(v.title)}</div>
            <div class="short-sound-row">
              <svg class="short-sound-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>
              <span class="short-sound-title">Âm thanh gốc - ${this.escapeHtml(v.uploader)}</span>
            </div>
          </div>
          <div class="short-progress-wrap">
            <div class="short-progress-bar"></div>
          </div>
        </div>

        <!-- Floating Actions Bar -->
        <div class="short-actions-bar">
          <div class="short-action-item">
            <button class="short-action-btn like-btn ${isLiked ? 'active' : ''}" title="Thích">
              <svg viewBox="0 0 24 24" fill="currentColor"><path d="M1 21h4V9H1v12zm22-11c0-1.1-.9-2-2-2h-6.31l.95-4.57.03-.32c0-.41-.17-.79-.44-1.06L14.17 1 7.59 7.59C7.22 7.95 7 8.45 7 9v10c0 1.1.9 2 2 2h9c.83 0 1.54-.5 1.84-1.22l3.02-7.05c.09-.23.14-.47.14-.73v-2z"/></svg>
            </button>
            <span class="short-action-label">${viewsFormatted}</span>
          </div>

          <div class="short-action-item">
            <button class="short-action-btn dislike-btn ${this.dislikes.has(v.id) ? 'active' : ''}" title="Không thích">
              <svg viewBox="0 0 24 24" fill="currentColor"><path d="M15 3H6c-.83 0-1.54.5-1.84 1.22l-3.02 7.05c-.09.23-.14.47-.14.73v2c0 1.1.9 2 2 2h6.31l-.95 4.57-.03.32c0 .41.17.79.44 1.06L9.83 23l6.59-6.59c.37-.36.58-.86.58-1.41V5c0-1.1-.9-2-2-2zm4 0v12h4V3h-4z"/></svg>
            </button>
            <span class="short-action-label">Không thích</span>
          </div>

          <div class="short-action-item">
            <button class="short-action-btn comment-btn" title="Bình luận">
              <svg viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4c-1.1 0-1.99.9-1.99 2L2 22l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zM6 9h12v2H6V9zm8 5H6v-2h8v2zm4-6H6V6h12v2z"/></svg>
            </button>
            <span class="short-action-label">Bình luận</span>
          </div>

          <div class="short-action-item">
            <button class="short-action-btn share-btn" title="Chia sẻ">
              <svg viewBox="0 0 24 24" fill="currentColor"><path d="M14 9V5l7 7-7 7v-4.1c-5 0-8.5 1.6-11 5.1 1-5 4-10 11-11z"/></svg>
            </button>
            <span class="short-action-label">Chia sẻ</span>
          </div>

          <div class="short-action-item">
            <button class="short-action-btn more-btn" title="Mở trong trình phát">
              <svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="19" r="2"/></svg>
            </button>
            <span class="short-action-label">Xem đủ</span>
          </div>
        </div>
      </div>
    `;

    this.attachCardEvents(item, v);
    return item;
  }

  attachCardEvents(item, v) {
    const card = item.querySelector('.short-player-card');
    const video = item.querySelector('.short-video');
    const audio = item.querySelector('.short-audio');
    const muteBtn = item.querySelector('.short-mute-btn');
    const subBtn = item.querySelector('.short-sub-btn');
    const likeBtn = item.querySelector('.like-btn');
    const dislikeBtn = item.querySelector('.dislike-btn');
    const commentBtn = item.querySelector('.comment-btn');
    const shareBtn = item.querySelector('.share-btn');
    const moreBtn = item.querySelector('.more-btn');
    const indicator = item.querySelector('.short-play-indicator');
    const progressBar = item.querySelector('.short-progress-bar');
    const spinner = item.querySelector('.short-spinner');
    const poster = item.querySelector('.short-poster-img');

    // Click on video toggles play/pause
    card.addEventListener('click', (e) => {
      if (e.target.closest('.short-top-bar') || e.target.closest('.short-bottom-overlay')) return;
      if (!video.src) {
        this.playCard(item, v);
        return;
      }
      if (video.paused) {
        video.play().catch(() => {});
        if (item.dataset.hasSeparateAudio === 'true' && audio.src) audio.play().catch(() => {});
        this.showPlayIndicator(indicator, true);
      } else {
        video.pause();
        if (item.dataset.hasSeparateAudio === 'true' && audio.src) audio.pause();
        this.showPlayIndicator(indicator, false);
      }
    });

    // Mute button
    muteBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.toggleMute();
    });

    // Subscribe
    subBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (this.subscribers.has(v.uploader)) {
        this.subscribers.delete(v.uploader);
        subBtn.classList.remove('subscribed');
        subBtn.textContent = 'Đăng ký';
        this.app.showToast(`Đã hủy đăng ký kênh: ${v.uploader}`);
      } else {
        this.subscribers.add(v.uploader);
        subBtn.classList.add('subscribed');
        subBtn.textContent = 'Đã đăng ký';
        this.app.showToast(`🔔 Đã đăng ký kênh: ${v.uploader}`);
      }
    });

    // Like
    likeBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (this.likes.has(v.id)) {
        this.likes.delete(v.id);
        likeBtn.classList.remove('active');
        this.app.showToast('Đã bỏ thích');
      } else {
        this.likes.add(v.id);
        likeBtn.classList.add('active');
        this.dislikes.delete(v.id);
        dislikeBtn.classList.remove('active');
        this.app.showToast('👍 Đã thích Short!');
      }
    });

    // Dislike
    dislikeBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (this.dislikes.has(v.id)) {
        this.dislikes.delete(v.id);
        dislikeBtn.classList.remove('active');
      } else {
        this.dislikes.add(v.id);
        dislikeBtn.classList.add('active');
        this.likes.delete(v.id);
        likeBtn.classList.remove('active');
        this.app.showToast('Đã đánh dấu không thích');
      }
    });

    // Comments
    commentBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.app.showToast('💬 Bình luận đang được cập nhật...');
    });

    // Share
    shareBtn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const url = `https://www.youtube.com/shorts/${v.id}`;
      try {
        await navigator.clipboard.writeText(url);
        this.app.showToast('🔗 Đã sao chép liên kết Short!');
      } catch (err) {
        this.app.showToast(`Liên kết: ${url}`);
      }
    });

    // More / Open Full Player
    moreBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.close();
      this.app.openWatchView(v);
    });

    // Video events
    video.addEventListener('timeupdate', () => {
      if (video.duration) {
        const pct = (video.currentTime / video.duration) * 100;
        progressBar.style.width = `${pct}%`;
      }
    });

    video.addEventListener('waiting', () => {
      spinner.classList.add('active');
    });

    video.addEventListener('playing', () => {
      spinner.classList.remove('active');
      poster.classList.add('hidden');
    });

    video.addEventListener('ended', () => {
      video.currentTime = 0;
      video.play().catch(() => {});
      if (item.dataset.hasSeparateAudio === 'true' && audio.src) {
        audio.currentTime = 0;
        audio.play().catch(() => {});
      }
    });
  }

  showPlayIndicator(indicator, isPlaying) {
    if (!indicator) return;
    indicator.innerHTML = isPlaying
      ? `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>`
      : `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>`;
    indicator.classList.add('show');
    setTimeout(() => {
      indicator.classList.remove('show');
    }, 450);
  }

  goToIndex(index, smooth = true) {
    if (index < 0 || index >= this.shorts.length) return;
    this.currentIndex = index;
    this.updateNavButtons();

    const targetItem = this.reel.children[index];
    if (targetItem) {
      targetItem.scrollIntoView({
        behavior: smooth ? 'smooth' : 'instant',
        block: 'center'
      });
      this.playActiveShort();
      this.checkInfiniteLoad();
    }
  }

  updateNavButtons() {
    if (this.prevBtn) {
      this.prevBtn.disabled = this.currentIndex <= 0;
      this.prevBtn.classList.toggle('disabled', this.currentIndex <= 0);
    }
    if (this.nextBtn) {
      const isEnd = this.currentIndex >= this.shorts.length - 1;
      this.nextBtn.disabled = isEnd;
      this.nextBtn.classList.toggle('disabled', isEnd);
    }
  }

  playActiveShort() {
    if (!this.isOpen) return;
    const currentItem = this.reel.children[this.currentIndex];
    if (!currentItem) return;

    // Pause all other videos
    Array.from(this.reel.children).forEach((item, idx) => {
      if (idx !== this.currentIndex) {
        const v = item.querySelector('.short-video');
        const a = item.querySelector('.short-audio');
        if (v && !v.paused) v.pause();
        if (a && !a.paused) a.pause();
      }
    });

    const videoData = this.shorts[this.currentIndex];
    this.playCard(currentItem, videoData);

    // Preload next short in background
    if (this.currentIndex + 1 < this.shorts.length) {
      const nextId = this.shorts[this.currentIndex + 1].id;
      fetch(`/api/stream?v=${nextId}&quality=720`).catch(() => {});
    }
  }

  async playCard(card, videoData) {
    const video = card.querySelector('.short-video');
    const audio = card.querySelector('.short-audio');
    const spinner = card.querySelector('.short-spinner');

    video.muted = this.isMuted;
    audio.muted = this.isMuted;

    if (video.src && video.src !== window.location.href) {
      video.play().catch(() => {});
      if (card.dataset.hasSeparateAudio === 'true' && audio.src) {
        audio.currentTime = video.currentTime;
        audio.play().catch(() => {});
      }
      return;
    }

    spinner.classList.add('active');
    try {
      const res = await fetch(`/api/stream?v=${videoData.id}&quality=720`);
      const stream = await res.json();
      if (!this.isOpen || parseInt(card.dataset.index, 10) !== this.currentIndex) return;

      const videoUrl = stream.proxyVideoUrl || `/api/proxy-stream?v=${videoData.id}&quality=720&type=video`;
      video.src = videoUrl;

      if (stream.hasSeparateAudio && stream.proxyAudioUrl) {
        card.dataset.hasSeparateAudio = 'true';
        audio.src = stream.proxyAudioUrl;
        audio.muted = this.isMuted;
      } else {
        card.dataset.hasSeparateAudio = 'false';
      }

      video.load();
      video.play().then(() => {
        spinner.classList.remove('active');
        if (card.dataset.hasSeparateAudio === 'true') {
          audio.currentTime = video.currentTime;
          audio.play().catch(() => {});
        }
      }).catch(err => {
        spinner.classList.remove('active');
        console.warn('Playback notice:', err.message);
      });
    } catch (err) {
      spinner.classList.remove('active');
      console.error('Error loading short stream:', err);
    }
  }

  pauseAll() {
    if (!this.reel) return;
    Array.from(this.reel.children).forEach(item => {
      const v = item.querySelector('.short-video');
      const a = item.querySelector('.short-audio');
      if (v) v.pause();
      if (a) a.pause();
    });
  }

  togglePlayPauseCurrent() {
    const currentItem = this.reel.children[this.currentIndex];
    if (!currentItem) return;
    const video = currentItem.querySelector('.short-video');
    const audio = currentItem.querySelector('.short-audio');
    const indicator = currentItem.querySelector('.short-play-indicator');
    if (!video) return;

    if (video.paused) {
      video.play().catch(() => {});
      if (currentItem.dataset.hasSeparateAudio === 'true' && audio.src) audio.play().catch(() => {});
      this.showPlayIndicator(indicator, true);
    } else {
      video.pause();
      if (currentItem.dataset.hasSeparateAudio === 'true' && audio.src) audio.pause();
      this.showPlayIndicator(indicator, false);
    }
  }

  toggleMute() {
    this.isMuted = !this.isMuted;
    if (!this.reel) return;
    Array.from(this.reel.children).forEach(item => {
      const v = item.querySelector('.short-video');
      const a = item.querySelector('.short-audio');
      const btn = item.querySelector('.short-mute-btn');
      if (v) v.muted = this.isMuted;
      if (a) a.muted = this.isMuted;
      if (btn) btn.innerHTML = this.getVolumeSvg(this.isMuted);
    });
    this.app.showToast(this.isMuted ? '🔇 Đã tắt tiếng' : '🔊 Đã bật tiếng');
  }

  getVolumeSvg(isMuted) {
    if (isMuted) {
      return `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/></svg>`;
    }
    return `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>`;
  }

  escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
}

// Start application
window.addEventListener('DOMContentLoaded', () => {
  window.app = new YouTubeApp();
});
