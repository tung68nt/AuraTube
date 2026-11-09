//! GStreamer playback engine (port of PlayerManager.swift's role).
//!
//! One pipeline holds one `uridecodebin` per URL, so yt-dlp's separate video and audio
//! streams play in sync, and HLS (single URL) works through the same path. Video frames
//! go through an appsink as RGBA and are shown as `gdk::MemoryTexture`s on every
//! registered `gtk::Picture` (main player, Shorts, mini player). That needs nothing beyond
//! the GStreamer packages in Ubuntu 22.04.

use gst::prelude::*;
use gtk::prelude::*;
use gtk::{gdk, glib};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::sync::{Arc, Mutex};

struct Frame {
    w: u32,
    h: u32,
    stride: usize,
    data: Vec<u8>,
}

pub enum Event {
    Ready,
    Eos,
    Error(String),
}

#[derive(Default)]
struct Links {
    video: bool,
    audio: bool,
}

pub struct Player {
    pipeline: RefCell<Option<gst::Pipeline>>,
    bus_guard: RefCell<Option<gst::bus::BusWatchGuard>>,
    volume_el: Arc<Mutex<Option<gst::Element>>>,
    pictures: RefCell<Vec<glib::WeakRef<gtk::Picture>>>,
    tx: async_channel::Sender<Frame>,
    volume: Cell<f64>,
    rate: Cell<f64>,
    pending_seek: Cell<Option<f64>>,
    handler: RefCell<Option<Rc<dyn Fn(Event)>>>,
    last_frame: RefCell<Option<gdk::Texture>>,
}

impl Player {
    pub fn new() -> Rc<Self> {
        let (tx, rx) = async_channel::bounded::<Frame>(2);
        let p = Rc::new(Self {
            pipeline: RefCell::new(None),
            bus_guard: RefCell::new(None),
            volume_el: Arc::new(Mutex::new(None)),
            pictures: RefCell::new(Vec::new()),
            tx,
            volume: Cell::new(1.0),
            rate: Cell::new(1.0),
            pending_seek: Cell::new(None),
            handler: RefCell::new(None),
            last_frame: RefCell::new(None),
        });
        let weak = Rc::downgrade(&p);
        glib::spawn_future_local(async move {
            while let Ok(f) = rx.recv().await {
                let Some(p) = weak.upgrade() else { break };
                let bytes = glib::Bytes::from_owned(f.data);
                let tex: gdk::Texture = gdk::MemoryTexture::new(f.w as i32, f.h as i32, gdk::MemoryFormat::R8g8b8a8, &bytes, f.stride).upcast();
                p.pictures.borrow_mut().retain(|w| w.upgrade().is_some());
                for w in p.pictures.borrow().iter() {
                    if let Some(pic) = w.upgrade() {
                        pic.set_paintable(Some(&tex));
                    }
                }
                *p.last_frame.borrow_mut() = Some(tex);
            }
        });
        p
    }

    pub fn set_handler(&self, f: impl Fn(Event) + 'static) {
        *self.handler.borrow_mut() = Some(Rc::new(f));
    }

    pub fn add_picture(&self, pic: &gtk::Picture) {
        if let Some(t) = self.last_frame.borrow().as_ref() {
            pic.set_paintable(Some(t));
        }
        self.pictures.borrow_mut().push(pic.downgrade());
    }

    pub fn remove_picture(&self, pic: &gtk::Picture) {
        self.pictures.borrow_mut().retain(|w| w.upgrade().map(|p| &p != pic).unwrap_or(false));
    }

    fn emit(&self, e: Event) {
        let h = self.handler.borrow().clone();
        if let Some(h) = h {
            glib::idle_add_local_once(move || h(e));
        }
    }

    pub fn has_media(&self) -> bool {
        self.pipeline.borrow().is_some()
    }

    pub fn stop(&self) {
        self.bus_guard.borrow_mut().take();
        if let Some(p) = self.pipeline.borrow_mut().take() {
            let _ = p.set_state(gst::State::Null);
        }
        *self.volume_el.lock().unwrap() = None;
        self.pending_seek.set(None);
        *self.last_frame.borrow_mut() = None;
        for w in self.pictures.borrow().iter() {
            if let Some(pic) = w.upgrade() {
                pic.set_paintable(None::<&gdk::Paintable>);
            }
        }
    }

    pub fn load(self: &Rc<Self>, video: &str, audio: Option<&str>, start: f64) {
        self.stop();
        let pipeline = gst::Pipeline::new();
        let links = Arc::new(Mutex::new(Links::default()));
        for uri in std::iter::once(video).chain(audio) {
            let src = match gst::ElementFactory::make("uridecodebin").property("uri", uri).build() {
                Ok(s) => s,
                Err(e) => {
                    self.emit(Event::Error(format!("Thiếu plugin GStreamer: {e}")));
                    return;
                }
            };
            let _ = pipeline.add(&src);
            self.connect_pads(&pipeline, &src, links.clone());
        }
        let weak = Rc::downgrade(self);
        let guard = pipeline.bus().and_then(|bus| {
            bus.add_watch_local(move |_, msg| {
                if let Some(p) = weak.upgrade() {
                    match msg.view() {
                        gst::MessageView::Eos(_) => p.emit(Event::Eos),
                        gst::MessageView::Error(e) => p.emit(Event::Error(e.error().to_string())),
                        gst::MessageView::AsyncDone(_) => {
                            if let Some(t) = p.pending_seek.take() {
                                p.seek(t);
                            } else {
                                p.emit(Event::Ready);
                            }
                        }
                        _ => {}
                    }
                }
                glib::ControlFlow::Continue
            })
            .ok()
        });
        *self.bus_guard.borrow_mut() = guard;
        self.pending_seek.set(if start > 1.0 { Some(start) } else { None });
        self.rate.set(1.0);
        let _ = pipeline.set_state(gst::State::Playing);
        *self.pipeline.borrow_mut() = Some(pipeline);
    }

    fn connect_pads(&self, pipeline: &gst::Pipeline, src: &gst::Element, links: Arc<Mutex<Links>>) {
        let pw = pipeline.downgrade();
        let tx = self.tx.clone();
        let vol = self.volume_el.clone();
        let volume = self.volume.get();
        src.connect_pad_added(move |_, pad| {
            let Some(pipeline) = pw.upgrade() else { return };
            let caps = pad.current_caps().unwrap_or_else(|| pad.query_caps(None));
            let name = caps.structure(0).map(|s| s.name().to_string()).unwrap_or_default();
            let mut l = links.lock().unwrap();
            let sink = if name.starts_with("video/") && !l.video {
                l.video = true;
                build_video(&pipeline, tx.clone())
            } else if name.starts_with("audio/") && !l.audio {
                l.audio = true;
                build_audio(&pipeline, &vol, volume)
            } else {
                build_fakesink(&pipeline)
            };
            if let Some(sp) = sink {
                let _ = pad.link(&sp);
            }
        });
    }

    pub fn is_playing(&self) -> bool {
        self.pipeline.borrow().as_ref().map(|p| p.current_state() == gst::State::Playing).unwrap_or(false)
    }

    pub fn play(&self) {
        if let Some(p) = self.pipeline.borrow().as_ref() {
            let _ = p.set_state(gst::State::Playing);
        }
    }

    pub fn pause(&self) {
        if let Some(p) = self.pipeline.borrow().as_ref() {
            let _ = p.set_state(gst::State::Paused);
        }
    }

    pub fn toggle(&self) {
        if self.is_playing() {
            self.pause()
        } else {
            self.play()
        }
    }

    pub fn position(&self) -> f64 {
        self.pipeline
            .borrow()
            .as_ref()
            .and_then(|p| p.query_position::<gst::ClockTime>())
            .map(|t| t.mseconds() as f64 / 1000.0)
            .unwrap_or(0.0)
    }

    pub fn duration(&self) -> f64 {
        self.pipeline
            .borrow()
            .as_ref()
            .and_then(|p| p.query_duration::<gst::ClockTime>())
            .map(|t| t.mseconds() as f64 / 1000.0)
            .unwrap_or(0.0)
    }

    pub fn seek(&self, secs: f64) {
        let Some(p) = self.pipeline.borrow().clone() else { return };
        let pos = gst::ClockTime::from_mseconds((secs.max(0.0) * 1000.0) as u64);
        let _ = p.seek(
            self.rate.get(),
            gst::SeekFlags::FLUSH | gst::SeekFlags::KEY_UNIT,
            gst::SeekType::Set,
            pos,
            gst::SeekType::None,
            gst::ClockTime::NONE,
        );
    }

    pub fn seek_by(&self, delta: f64) {
        self.seek(self.position() + delta);
    }

    pub fn set_rate(&self, rate: f64) {
        self.rate.set(rate);
        let pos = self.position();
        self.seek(pos);
    }

    pub fn volume(&self) -> f64 {
        self.volume.get()
    }

    pub fn set_volume(&self, v: f64) {
        self.volume.set(v);
        if let Some(e) = self.volume_el.lock().unwrap().as_ref() {
            e.set_property("volume", v);
        }
    }
}

fn add_chain(pipeline: &gst::Pipeline, elems: &[gst::Element]) -> Option<gst::Pad> {
    pipeline.add_many(elems).ok()?;
    gst::Element::link_many(elems).ok()?;
    for e in elems {
        let _ = e.sync_state_with_parent();
    }
    elems.first()?.static_pad("sink")
}

fn make(name: &str) -> Option<gst::Element> {
    gst::ElementFactory::make(name).build().ok()
}

fn build_video(pipeline: &gst::Pipeline, tx: async_channel::Sender<Frame>) -> Option<gst::Pad> {
    let queue = make("queue")?;
    let conv = gst::ElementFactory::make("videoconvert").property("n-threads", 0u32).build().ok().or_else(|| make("videoconvert"))?;
    let caps = gst_video::VideoCapsBuilder::new().format(gst_video::VideoFormat::Rgba).build();
    let sink = gst_app::AppSink::builder().caps(&caps).max_buffers(2).drop(true).build();
    sink.set_callbacks(
        gst_app::AppSinkCallbacks::builder()
            .new_sample(move |sink| {
                let sample = sink.pull_sample().map_err(|_| gst::FlowError::Eos)?;
                let (Some(buffer), Some(caps)) = (sample.buffer(), sample.caps()) else {
                    return Err(gst::FlowError::Error);
                };
                let info = gst_video::VideoInfo::from_caps(caps).map_err(|_| gst::FlowError::Error)?;
                let map = buffer.map_readable().map_err(|_| gst::FlowError::Error)?;
                let _ = tx.try_send(Frame { w: info.width(), h: info.height(), stride: info.stride()[0] as usize, data: map.as_slice().to_vec() });
                Ok(gst::FlowSuccess::Ok)
            })
            .build(),
    );
    add_chain(pipeline, &[queue, conv, sink.upcast()])
}

fn build_audio(pipeline: &gst::Pipeline, vol: &Arc<Mutex<Option<gst::Element>>>, volume: f64) -> Option<gst::Pad> {
    let mut elems = vec![make("queue")?, make("audioconvert")?];
    // Keeps pitch when the playback speed changes.
    if let Some(st) = make("scaletempo") {
        elems.push(st);
        elems.push(make("audioconvert")?);
    }
    elems.push(make("audioresample")?);
    let v = gst::ElementFactory::make("volume").property("volume", volume).build().ok()?;
    *vol.lock().unwrap() = Some(v.clone());
    elems.push(v);
    elems.push(make("autoaudiosink")?);
    add_chain(pipeline, &elems)
}

fn build_fakesink(pipeline: &gst::Pipeline) -> Option<gst::Pad> {
    let f = gst::ElementFactory::make("fakesink").property("sync", true).property("async", false).build().ok()?;
    add_chain(pipeline, &[f])
}
