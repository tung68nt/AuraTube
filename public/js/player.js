/**
 * Custom Video Player Engine with SponsorBlock & Quality Switching
 */

class AdFreePlayer {
  constructor() {
    this.video = document.getElementById('mainVideo');
    this.audio = document.getElementById('audioTrack');
    this.wrapper = document.querySelector('.player-wrapper');
    this.controls = document.querySelector('.player-controls');
    this.playBtn = document.getElementById('playPauseBtn');
    this.seekBar = document.getElementById('seekBar');
    this.seekProgress = document.getElementById('seekProgress');
    this.seekBuffered = document.getElementById('seekBuffered');
    this.timeDisplay = document.getElementById('timeDisplay');
    this.volumeBtn = document.getElementById('volumeBtn');
    this.volumeSlider = document.getElementById('volumeSlider');
    this.qualitySelect = document.getElementById('qualitySelect');
    this.speedSelect = document.getElementById('speedSelect');
    this.pipBtn = document.getElementById('pipBtn');
    this.theaterBtn = document.getElementById('theaterBtn');
    this.fullscreenBtn = document.getElementById('fullscreenBtn');
    this.playerSpinner = document.getElementById('playerSpinner');

    this.currentVideoId = null;
    this.currentQuality = '1080';
    this.isAudioOnly = false;
    this.hasSeparateAudio = false;
    this.isMuted = false;
    this.currentVolume = 1;
    this.lastBroadcastTime = 0;
    this.sponsorSegments = [];
    this.isDraggingSeek = false;
    this.controlsTimeout = null;
    this.audioCard = document.getElementById('audioModeCard');

    this.initEvents();
  }

  initEvents() {
    // Play / Pause triggers
    this.playBtn.addEventListener('click', () => this.togglePlay());
    this.video.addEventListener('click', () => this.togglePlay());
    if (this.audioCard) {
      this.audioCard.addEventListener('click', () => this.togglePlay());
    }

    // Video media events
    this.video.addEventListener('play', () => {
      if (!this.isAudioOnly) {
        this.updatePlayBtn(true);
        if (this.hasSeparateAudio && this.audio) {
          this.audio.currentTime = this.video.currentTime;
          this.audio.play().catch(() => {});
        }
        this.broadcastState();
      }
    });
    this.video.addEventListener('pause', () => {
      if (!this.isAudioOnly) {
        this.updatePlayBtn(false);
        if (this.hasSeparateAudio && this.audio) {
          this.audio.pause();
        }
        this.broadcastState();
      }
    });
    this.video.addEventListener('seeking', () => {
      if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) {
        this.audio.currentTime = this.video.currentTime;
      }
      this.broadcastState();
    });
    this.video.addEventListener('ratechange', () => {
      if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) {
        this.audio.playbackRate = this.video.playbackRate;
      }
    });

    this.video.addEventListener('waiting', () => {
      if (!this.isAudioOnly && this.playerSpinner) this.playerSpinner.classList.add('active');
    });
    this.video.addEventListener('canplay', () => {
      if (!this.isAudioOnly && this.playerSpinner) this.playerSpinner.classList.remove('active');
    });
    this.video.addEventListener('playing', () => {
      if (!this.isAudioOnly && this.playerSpinner) this.playerSpinner.classList.remove('active');
    });

    this.video.addEventListener('error', () => {
      if (this.isAudioOnly || this.currentQuality === 'audio') return;
      if (!this.video.src || !this.video.getAttribute('src')) return;
      if (this.playerSpinner) this.playerSpinner.classList.remove('active');
      console.warn('Video element playback error:', this.video.error);
      if (this.currentVideoId && this.qualitySelect && this.qualitySelect.value !== '360' && this.qualitySelect.value !== 'audio') {
        const curQ = parseInt(this.qualitySelect.value, 10) || 1080;
        let fallbackQ = '720';
        if (curQ > 1440) fallbackQ = '1440';
        else if (curQ > 1080) fallbackQ = '1080';
        else if (curQ > 720) fallbackQ = '720';
        else fallbackQ = '360';
        console.log(`Attempting fallback stream at ${fallbackQ}p...`);
        if (this.qualitySelect) this.qualitySelect.value = fallbackQ;
        this.currentQuality = fallbackQ;
        this.loadStream(this.currentVideoId, fallbackQ, this.video.currentTime || 0, true);
      }
    });

    // Audio media events (active in Audio-Only Mode)
    this.audio.addEventListener('error', () => {
      if (this.isAudioOnly && this.playerSpinner) this.playerSpinner.classList.remove('active');
    });
    this.audio.addEventListener('play', () => {
      if (this.isAudioOnly) {
        this.updatePlayBtn(true);
        this.broadcastState();
      }
    });
    this.audio.addEventListener('pause', () => {
      if (this.isAudioOnly) {
        this.updatePlayBtn(false);
        this.broadcastState();
      }
    });
    this.audio.addEventListener('waiting', () => {
      if (this.isAudioOnly && this.playerSpinner) this.playerSpinner.classList.add('active');
    });
    this.audio.addEventListener('canplay', () => {
      if (this.isAudioOnly && this.playerSpinner) this.playerSpinner.classList.remove('active');
    });
    this.audio.addEventListener('playing', () => {
      if (this.isAudioOnly && this.playerSpinner) this.playerSpinner.classList.remove('active');
    });
    this.audio.addEventListener('ended', () => {
      if (this.isAudioOnly) {
        this.updatePlayBtn(false);
        this.broadcastState();
      }
    });
    this.audio.addEventListener('timeupdate', () => {
      if (this.isAudioOnly) {
        this.onTimeUpdate();
        const now = Date.now();
        if (now - this.lastBroadcastTime > 400) {
          this.lastBroadcastTime = now;
          this.broadcastState();
        }
      }
    });
    this.audio.addEventListener('progress', () => {
      if (this.isAudioOnly) {
        this.onProgressUpdate();
      }
    });

    // Progress and Time (Video mode)
    this.video.addEventListener('timeupdate', () => {
      if (this.isAudioOnly) return;
      this.onTimeUpdate();
      // Smooth drift correction for separate audio track (no seeking = zero stutter)
      if (this.hasSeparateAudio && this.audio && !this.audio.paused && !this.video.paused) {
        const drift = this.audio.currentTime - this.video.currentTime;
        const absDrift = Math.abs(drift);
        if (absDrift > 0.8) {
          // Large desync: perform hard alignment
          this.audio.currentTime = this.video.currentTime;
        } else if (absDrift > 0.05) {
          // Micro-desync: smoothly adjust audio playbackRate without seeking!
          const targetRate = this.video.playbackRate * (drift < 0 ? 1.04 : 0.96);
          this.audio.playbackRate = targetRate;
        } else {
          if (this.audio.playbackRate !== this.video.playbackRate) {
            this.audio.playbackRate = this.video.playbackRate;
          }
        }
      }
      const now = Date.now();
      if (now - this.lastBroadcastTime > 400) {
        this.lastBroadcastTime = now;
        this.broadcastState();
      }
    });
    this.video.addEventListener('progress', () => {
      if (!this.isAudioOnly) this.onProgressUpdate();
    });

    // Seeking
    this.seekBar.addEventListener('click', (e) => this.seek(e));
    this.seekBar.addEventListener('mousedown', () => { this.isDraggingSeek = true; });
    window.addEventListener('mouseup', () => { this.isDraggingSeek = false; });
    this.seekBar.addEventListener('mousemove', (e) => {
      if (this.isDraggingSeek) this.seek(e);
    });

    // Volume
    this.volumeSlider.addEventListener('input', (e) => {
      this.currentVolume = parseFloat(e.target.value);
      this.isMuted = this.currentVolume === 0;
      this.applyVolume();
      this.updateVolumeBtn();
      this.broadcastState();
    });

    this.volumeBtn.addEventListener('click', () => {
      this.toggleMute();
    });

    // Quality Switcher with toast feedback and seamless seek restoration
    this.qualitySelect.addEventListener('change', (e) => {
      const targetQuality = e.target.value;
      if (targetQuality !== 'audio') {
        localStorage.setItem('yt_preferred_quality', targetQuality);
      }
      const label = e.target.options[e.target.selectedIndex]?.text || targetQuality;
      if (window.app && window.app.showToast) {
        window.app.showToast(`⚙️ Đang chuyển sang: ${label}...`);
      }
      if (this.currentVideoId) {
        const currentTime = (this.isAudioOnly ? this.audio.currentTime : this.video.currentTime) || 0;
        const wasPlaying = this.isAudioOnly ? !this.audio.paused : !this.video.paused;
        this.loadStream(this.currentVideoId, targetQuality, currentTime, wasPlaying);
      }
    });

    // Speed Switcher
    this.speedSelect.addEventListener('change', (e) => {
      const rate = parseFloat(e.target.value);
      this.video.playbackRate = rate;
      if (this.audio) this.audio.playbackRate = rate;
    });

    // Picture in Picture Button (Manual only)
    if (document.pictureInPictureEnabled) {
      this.pipBtn.addEventListener('click', async () => {
        try {
          if (document.pictureInPictureElement) {
            await document.exitPictureInPicture();
          } else {
            await this.video.requestPictureInPicture();
          }
        } catch (err) {
          console.error(err);
        }
      });
    } else {
      this.pipBtn.style.display = 'none';
    }

    // Global ESC key listener: Exit fullscreen straight back to normal view with 1 click
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        if (document.fullscreenElement) {
          e.preventDefault();
          e.stopPropagation();
          document.exitFullscreen().catch(() => {});
          this.exitMiniplayer();
          return;
        }
        if (document.pictureInPictureElement) {
          e.preventDefault();
          e.stopPropagation();
          document.exitPictureInPicture().catch(() => {});
          return;
        }
        if (this.wrapper.classList.contains('miniplayer')) {
          e.preventDefault();
          e.stopPropagation();
          this.exitMiniplayer();
          if (window.app) window.app.reopenWatchView();
          return;
        }
      }
    }, true);

    // Fullscreen change listener: Never allow miniplayer to activate when exiting fullscreen
    document.addEventListener('fullscreenchange', () => {
      this.exitMiniplayer();
    });

    // Miniplayer controls
    this.expandMiniBtn = document.getElementById('expandMiniplayerBtn');
    this.closeMiniBtn = document.getElementById('closeMiniplayerBtn');
    this.miniTitle = document.getElementById('miniplayerTitle');

    if (this.expandMiniBtn) {
      this.expandMiniBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this.exitMiniplayer();
        if (window.app) window.app.reopenWatchView();
      });
    }

    if (this.closeMiniBtn) {
      this.closeMiniBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        this.exitMiniplayer();
        this.video.pause();
      });
    }

    this.wrapper.addEventListener('click', (e) => {
      if (this.wrapper.classList.contains('miniplayer')) {
        // Clicking on miniplayer returns to watch view
        if (!e.target.closest('.miniplayer-actions') && !e.target.closest('.player-controls')) {
          this.exitMiniplayer();
          if (window.app) window.app.reopenWatchView();
        }
      }
    });

    // Fullscreen
    this.fullscreenBtn.addEventListener('click', () => this.toggleFullscreen());

    // Theater Mode
    if (this.theaterBtn) {
      this.theaterBtn.addEventListener('click', () => {
        const container = document.querySelector('.watch-container');
        if (container) container.classList.toggle('theater');
      });
    }

    // Auto-hide controls
    this.wrapper.addEventListener('mousemove', () => this.showControlsTemporarily());
    this.wrapper.addEventListener('mouseleave', () => {
      if (!this.video.paused) this.controls.classList.remove('visible');
    });

    // Global Keyboard Shortcuts
    window.addEventListener('keydown', (e) => this.handleShortcuts(e));
  }

  showControlsTemporarily() {
    this.controls.classList.add('visible');
    clearTimeout(this.controlsTimeout);
    this.controlsTimeout = setTimeout(() => {
      if (!this.video.paused) {
        this.controls.classList.remove('visible');
      }
    }, 2500);
  }

  togglePlay() {
    const activeMedia = this.isAudioOnly ? this.audio : this.video;
    if (!activeMedia) return;
    if (activeMedia.paused) {
      const p = activeMedia.play();
      if (p !== undefined) {
        p.then(() => {
          this.updatePlayBtn(true);
          if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) {
            this.audio.currentTime = this.video.currentTime;
            this.audio.play().catch(() => {});
          }
          this.broadcastState();
        }).catch(e => console.log('Play interrupted:', e));
      }
    } else {
      activeMedia.pause();
      this.updatePlayBtn(false);
      if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) {
        this.audio.pause();
      }
      this.broadcastState();
    }
  }

  updatePlayBtn(isPlaying) {
    if (isPlaying) {
      this.playBtn.innerHTML = `<svg viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>`;
      this.playBtn.title = 'Tạm dừng (k)';
      if (this.audioCard) this.audioCard.classList.add('playing');
    } else {
      this.playBtn.innerHTML = `<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>`;
      this.playBtn.title = 'Phát (k)';
      if (this.audioCard) this.audioCard.classList.remove('playing');
    }
  }

  broadcastState() {
    if (window.electronAPI && window.electronAPI.sendMediaUpdate) {
      const activeMedia = this.isAudioOnly ? this.audio : this.video;
      const title = document.getElementById('watchTitle')?.textContent?.trim() || '';
      const author = document.getElementById('uploaderName')?.textContent?.trim() || '';
      const views = document.getElementById('videoViews')?.textContent?.trim() || '';
      window.electronAPI.sendMediaUpdate({
        hasVideo: Boolean(this.currentVideoId),
        videoId: this.currentVideoId,
        title: title,
        author: author,
        views: views,
        currentTime: (activeMedia && activeMedia.currentTime) || 0,
        duration: (activeMedia && activeMedia.duration) || 0,
        paused: activeMedia ? activeMedia.paused : true,
        muted: this.isMuted,
        volume: this.currentVolume,
        isAudioOnly: this.isAudioOnly
      });
    }
  }

  applyVolume() {
    if (this.isAudioOnly) {
      // Audio-only mode: video completely muted & 0 volume; audio plays
      if (this.video) {
        this.video.muted = true;
        this.video.volume = 0;
      }
      if (this.audio) {
        this.audio.volume = this.currentVolume;
        this.audio.muted = this.isMuted;
      }
    } else if (this.hasSeparateAudio && this.audio) {
      // High-res video with separate audio track:
      // Audio is played EXCLUSIVELY by this.audio.
      // this.video MUST be muted so it cannot echo or emit duplicate audio.
      this.video.muted = true;
      this.video.volume = 0;
      this.audio.volume = this.currentVolume;
      this.audio.muted = this.isMuted;
    } else {
      // Single combined audio+video stream:
      // this.video plays the audio. this.audio is kept silent.
      this.video.volume = this.currentVolume;
      this.video.muted = this.isMuted;
      if (this.audio) {
        this.audio.muted = true;
        this.audio.volume = 0;
      }
    }
  }

  toggleMute() {
    this.isMuted = !this.isMuted;
    this.applyVolume();
    this.updateVolumeBtn();
    this.broadcastState();
    return this.isMuted;
  }

  setVolume(val) {
    this.currentVolume = Math.max(0, Math.min(1, val));
    this.isMuted = this.currentVolume === 0;
    this.volumeSlider.value = this.currentVolume;
    this.applyVolume();
    this.updateVolumeBtn();
    this.broadcastState();
  }

  updateVolumeBtn() {
    if (this.isMuted || this.currentVolume === 0) {
      this.volumeBtn.innerHTML = `<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L9 9H3z"/><path d="M16.59 8L15.17 9.41 17.76 12l-2.59 2.59L16.59 16l2.59-2.59 2.59 2.59 1.41-1.41L20.59 12l2.59-2.59L21.76 8l-2.59 2.59L16.59 8z"/></svg>`;
      this.volumeBtn.title = 'Bật tiếng (m)';
    } else if (this.currentVolume < 0.5) {
      this.volumeBtn.innerHTML = `<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L9 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"/></svg>`;
      this.volumeBtn.title = 'Tắt tiếng (m)';
    } else {
      this.volumeBtn.innerHTML = `<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L9 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>`;
      this.volumeBtn.title = 'Tắt tiếng (m)';
    }
  }

  seek(e) {
    const rect = this.seekBar.getBoundingClientRect();
    const pos = (e.clientX - rect.left) / rect.width;
    const clampedPos = Math.max(0, Math.min(1, pos));
    const activeMedia = this.isAudioOnly ? this.audio : this.video;
    if (activeMedia && activeMedia.duration) {
      activeMedia.currentTime = clampedPos * activeMedia.duration;
      if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) {
        this.audio.currentTime = activeMedia.currentTime;
      }
      this.broadcastState();
    }
  }

  onTimeUpdate() {
    const activeMedia = this.isAudioOnly ? this.audio : this.video;
    if (!activeMedia || !activeMedia.duration) return;
    const current = activeMedia.currentTime;
    const duration = activeMedia.duration;
    const percent = (current / duration) * 100;
    this.seekProgress.style.width = `${percent}%`;

    this.timeDisplay.textContent = `${this.formatTime(current)} / ${this.formatTime(duration)}`;

    // SponsorBlock Auto Skip
    this.checkSponsorSkip(current);
  }

  onProgressUpdate() {
    const activeMedia = this.isAudioOnly ? this.audio : this.video;
    if (!activeMedia || !activeMedia.duration || activeMedia.buffered.length === 0) return;
    const bufferedEnd = activeMedia.buffered.end(activeMedia.buffered.length - 1);
    const percent = (bufferedEnd / activeMedia.duration) * 100;
    this.seekBuffered.style.width = `${percent}%`;
  }

  checkSponsorSkip(current) {
    if (!this.sponsorSegments || this.sponsorSegments.length === 0) return;
    const activeMedia = this.isAudioOnly ? this.audio : this.video;
    for (const item of this.sponsorSegments) {
      const [start, end] = item.segment;
      if (current >= start && current < end - 0.5) {
        console.log(`[SponsorBlock] Skipping ${item.category} segment from ${start}s to ${end}s`);
        activeMedia.currentTime = end;
        if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) {
          this.audio.currentTime = end;
        }
        if (window.app && window.app.showToast) {
          window.app.showToast(`⚡ Đã tự động bỏ qua đoạn tài trợ (${Math.round(end - start)}s)`);
        }
        break;
      }
    }
  }

  toggleFullscreen() {
    if (!document.fullscreenElement) {
      this.wrapper.requestFullscreen().catch(err => console.error(err));
    } else {
      document.exitFullscreen().catch(err => console.error(err));
    }
  }

  handleShortcuts(e) {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    const activeMedia = this.isAudioOnly ? this.audio : this.video;

    switch (e.key.toLowerCase()) {
      case 'a':
        e.preventDefault();
        this.toggleAudioOnly();
        break;
      case ' ':
      case 'k':
        e.preventDefault();
        this.togglePlay();
        break;
      case 'f':
        e.preventDefault();
        this.toggleFullscreen();
        break;
      case 'm':
        e.preventDefault();
        this.toggleMute();
        break;
      case 'arrowright':
      case 'l':
        e.preventDefault();
        if (activeMedia) {
          activeMedia.currentTime = Math.min(activeMedia.duration || Infinity, activeMedia.currentTime + 10);
          if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) this.audio.currentTime = activeMedia.currentTime;
          this.broadcastState();
        }
        break;
      case 'arrowleft':
      case 'j':
        e.preventDefault();
        if (activeMedia) {
          activeMedia.currentTime = Math.max(0, activeMedia.currentTime - 10);
          if (!this.isAudioOnly && this.hasSeparateAudio && this.audio) this.audio.currentTime = activeMedia.currentTime;
          this.broadcastState();
        }
        break;
      case 'arrowup':
        e.preventDefault();
        this.setVolume(this.currentVolume + 0.1);
        break;
      case 'arrowdown':
        e.preventDefault();
        this.setVolume(this.currentVolume - 0.1);
        break;
    }
  }

  formatTime(seconds) {
    const s = Math.floor(seconds);
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    const hours = Math.floor(mins / 60);
    const remMins = mins % 60;
    if (hours > 0) {
      return `${hours}:${remMins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  async loadStream(videoId, quality = '1080', startTime = 0, autoPlay = true) {
    this.currentVideoId = videoId;
    this.currentQuality = quality;
    this.isAudioOnly = (quality === 'audio');

    // Reset seek progress UI
    this.seekProgress.style.width = '0%';
    this.seekBuffered.style.width = '0%';
    this.timeDisplay.textContent = '0:00 / 0:00';

    if (this.playerSpinner) this.playerSpinner.classList.add('active');

    if (this.isAudioOnly) {
      // Audio-Only Mode: Show audio card, pause & clear video element
      this.wrapper.classList.add('audio-only-mode');
      this.updateAudioModeUI();

      // Completely stop and hide video so no frames render and no GPU decoding occurs
      this.video.pause();
      this.video.removeAttribute('src');
      this.video.load();
      this.video.style.display = 'none';

      this.hasSeparateAudio = false;
      this.applyVolume();

      // Stream highest-bitrate direct uncompressed audio
      const audioEndpoint = `/api/proxy-stream?v=${videoId}&quality=audio&type=audio`;
      this.audio.src = audioEndpoint;
      this.audio.playbackRate = parseFloat(this.speedSelect.value) || 1.0;
      this.audio.load();

      let audioStarted = false;
      const startAudioPlayback = () => {
        if (audioStarted) return;
        audioStarted = true;
        if (this.playerSpinner) this.playerSpinner.classList.remove('active');
        if (startTime > 0) {
          try { this.audio.currentTime = startTime; } catch (e) {}
        }
        this.applyVolume();
        if (autoPlay) {
          this.audio.play().then(() => {
            this.updatePlayBtn(true);
            this.broadcastState();
          }).catch(() => {
            this.updatePlayBtn(false);
          });
        }
      };

      this.audio.onloadedmetadata = startAudioPlayback;
      this.audio.oncanplay = startAudioPlayback;
      this.audio.onerror = () => {
        if (this.playerSpinner) this.playerSpinner.classList.remove('active');
      };
      return;
    }

    // Video Mode: Remove audio-only mode, restore video display, stop standalone audio
    this.wrapper.classList.remove('audio-only-mode');
    this.video.style.display = '';
    this.hasSeparateAudio = false;

    if (this.audio) {
      this.audio.pause();
      this.audio.removeAttribute('src');
    }

    const videoEndpoint = `/api/proxy-stream?v=${videoId}&quality=${quality}&type=video`;
    this.video.autoplay = autoPlay;
    this.video.playbackRate = parseFloat(this.speedSelect.value) || 1.0;
    this.video.src = videoEndpoint;
    this.video.load();
    this.applyVolume();

    // Check if secondary audio track is needed (for 1080p, 720p separate DASH streams)
    fetch(`/api/stream?v=${videoId}&quality=${quality}`)
      .then(res => res.json())
      .then(streamData => {
        if (this.currentVideoId !== videoId || this.isAudioOnly) return;
        if (streamData && streamData.hasSeparateAudio && streamData.proxyAudioUrl) {
          this.hasSeparateAudio = true;
          if (this.audio) {
            this.audio.src = streamData.proxyAudioUrl;
            this.audio.currentTime = this.video.currentTime || startTime || 0;
            this.audio.playbackRate = this.video.playbackRate;
            this.audio.autoplay = autoPlay;
            this.audio.load();
            if (autoPlay && !this.video.paused) {
              this.audio.play().catch(() => {});
            }
          }
          this.applyVolume();
        } else {
          this.hasSeparateAudio = false;
          this.applyVolume();
        }
      })
      .catch(() => {});

    let started = false;
    const startPlayback = () => {
      if (started) return;
      started = true;
      if (this.playerSpinner) this.playerSpinner.classList.remove('active');

      if (startTime > 0) {
        try {
          this.video.currentTime = startTime;
          if (this.audio && this.hasSeparateAudio) {
            this.audio.currentTime = startTime;
          }
        } catch (e) {}
      }
      this.applyVolume();
      if (autoPlay) {
        const playPromise = this.video.play();
        if (playPromise !== undefined) {
          playPromise.then(() => {
            this.updatePlayBtn(true);
            if (this.audio && this.hasSeparateAudio) {
              this.audio.currentTime = this.video.currentTime;
              this.audio.play().catch(() => {});
            }
            this.broadcastState();
          }).catch((err) => {
            console.warn('Autoplay error:', err);
            setTimeout(() => {
              this.video.play().then(() => {
                this.updatePlayBtn(true);
                if (this.audio && this.hasSeparateAudio) this.audio.play().catch(() => {});
              }).catch(() => {
                this.updatePlayBtn(false);
              });
            }, 200);
          });
        }
      }
    };

    const checkAspect = () => {
      if (this.video && this.video.videoWidth > 0 && this.video.videoHeight > 0) {
        if (this.video.videoHeight > this.video.videoWidth) {
          this.wrapper.classList.add('vertical-video');
        } else {
          this.wrapper.classList.remove('vertical-video');
        }
      }
    };

    this.video.onloadedmetadata = () => {
      checkAspect();
      startPlayback();
    };
    this.video.oncanplay = startPlayback;

    this.broadcastState();
  }

  updateAudioModeUI() {
    const title = (window.app && window.app.currentVideo && window.app.currentVideo.title) || '';
    const channel = (window.app && window.app.currentVideo && window.app.currentVideo.uploader) || '';
    const thumb = (window.app && window.app.currentVideo && window.app.currentVideo.thumbnail) || '';

    const titleEl = document.getElementById('audioModeTitle');
    const channelEl = document.getElementById('audioModeChannel');
    const coverEl = document.getElementById('audioModeCover');
    const bgEl = document.getElementById('audioModeBg');

    if (titleEl) titleEl.textContent = title || 'Đang phát âm thanh';
    if (channelEl) channelEl.textContent = channel || 'Kênh YouTube';
    if (coverEl && thumb) coverEl.src = thumb;
    if (bgEl && thumb) bgEl.style.backgroundImage = `url("${thumb}")`;
  }

  enterMiniplayer(title) {
    if (this.miniTitle && title) {
      this.miniTitle.textContent = title;
    }
    this.wrapper.classList.add('miniplayer');
  }

  exitMiniplayer() {
    this.wrapper.classList.remove('miniplayer');
  }

  setPoster(url) {
    if (this.video && url) {
      this.video.poster = url;
    }
  }

  setSponsorSegments(segments) {
    this.sponsorSegments = segments || [];
  }

  toggleAudioOnly() {
    if (!this.currentVideoId || !this.qualitySelect) return;
    if (this.isAudioOnly) {
      const preferred = localStorage.getItem('yt_preferred_quality') || '1080';
      const targetQ = (preferred !== 'audio') ? preferred : '1080';
      this.setQuality(targetQ);
    } else {
      this.setQuality('audio');
    }
  }

  setQuality(quality) {
    if (!this.qualitySelect) return;
    let exists = false;
    for (let i = 0; i < this.qualitySelect.options.length; i++) {
      if (this.qualitySelect.options[i].value === quality) {
        exists = true;
        break;
      }
    }
    if (!exists && quality === 'audio') {
      const opt = document.createElement('option');
      opt.value = 'audio';
      opt.textContent = 'Chỉ Audio';
      this.qualitySelect.appendChild(opt);
    }
    this.qualitySelect.value = quality;
    this.qualitySelect.dispatchEvent(new Event('change'));
  }
}

window.AdFreePlayer = AdFreePlayer;
