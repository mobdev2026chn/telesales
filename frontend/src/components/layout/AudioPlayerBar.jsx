// DOCKED BOTTOM AUDIO PLAYER BAR (driven by utils/audioController)
import { useCallback, useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import { Button, Tooltip } from '../../assets/antd';
import {
  audioCtlStep, audioCtlToggle, closeBottomAudioBar, currentAudioEl, onAnyAudioPlay, registerDock, seekCurrentAudio, syncAudioControls,
} from '../../utils/audioController';
import Icon from '../common/Icon';

function fmtTime(sec) {
  if (!Number.isFinite(sec) || sec < 0) return '0:00';
  const total = Math.floor(sec);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

export default function AudioPlayerBar() {
  const audio = useSelector(s => s.ui.audio);
  const dockRef = useCallback((el) => { if (el) registerDock(el); }, []);
  const [time, setTime] = useState({ current: 0, duration: 0 });
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);

  useEffect(() => {
    const el = currentAudioEl();
    if (!audio.visible || !el) return undefined;
    el.volume = volume;
    el.muted = muted;
    const sync = () => {
      setTime({
        current: Number.isFinite(el.currentTime) ? el.currentTime : 0,
        duration: Number.isFinite(el.duration) && el.duration > 0 ? el.duration : 0,
      });
    };
    sync();
    el.addEventListener('timeupdate', sync);
    el.addEventListener('loadedmetadata', sync);
    el.addEventListener('durationchange', sync);
    el.addEventListener('ended', sync);
    return () => {
      el.removeEventListener('timeupdate', sync);
      el.removeEventListener('loadedmetadata', sync);
      el.removeEventListener('durationchange', sync);
      el.removeEventListener('ended', sync);
    };
  }, [audio.visible, audio.title, audio.idx, audio.playing, volume, muted]);

  const pct = time.duration > 0 ? Math.min(100, Math.max(0, (time.current / time.duration) * 100)) : 0;
  const volPct = (muted ? 0 : volume) * 100;
  const onSeek = (e) => {
    const val = Number(e.target.value);
    if (!Number.isFinite(val)) return;
    setTime(prev => ({ ...prev, current: val }));
    seekCurrentAudio(val);
  };
  const onVolume = (e) => {
    const val = Number(e.target.value);
    if (!Number.isFinite(val)) return;
    setVolume(val);
    setMuted(val === 0);
    const el = currentAudioEl();
    if (el) { el.volume = val; el.muted = val === 0; }
  };
  const toggleMute = () => {
    const nextMuted = !muted;
    const nextVol = !nextMuted && volume === 0 ? 1 : volume;
    setMuted(nextMuted);
    setVolume(nextVol);
    const el = currentAudioEl();
    if (el) { el.muted = nextMuted; el.volume = nextVol; }
  };

  return (
    <div id="bottomAudioPlayerBar" style={{ display: audio.visible ? 'flex' : 'none' }}>
      <div className="audio-title-wrap">
        <span className="presence-dot is-online" aria-hidden="true" />
        <div className="audio-title">{audio.title}</div>
      </div>
      <div className="audio-ctl-group">
        <Tooltip title="Previous recording">
          <Button shape="circle" className="audio-ctl-btn" icon={<Icon name="step-back" />} onClick={() => audioCtlStep(-1)} disabled={audio.idx <= 0} aria-label="Previous recording" />
        </Tooltip>
        <Tooltip title={audio.playing ? 'Pause' : 'Play'}>
          <Button shape="circle" type="primary" className="audio-ctl-btn audio-ctl-play" icon={<Icon name={audio.playing ? 'pause' : 'caret-right'} />} onClick={audioCtlToggle} aria-label={audio.playing ? 'Pause' : 'Play'} />
        </Tooltip>
        <Tooltip title="Next recording">
          <Button shape="circle" className="audio-ctl-btn" icon={<Icon name="step-forward" />} onClick={() => audioCtlStep(1)} disabled={audio.idx < 0 || audio.idx >= audio.total - 1} aria-label="Next recording" />
        </Tooltip>
      </div>
      <div className="audio-scrubber-wrap">
        <span className="audio-time mono tabular">{fmtTime(time.current)}</span>
        <input
          type="range"
          className="audio-scrubber"
          aria-label="Seek recording time"
          min={0}
          max={time.duration > 0 ? time.duration : 100}
          step={0.1}
          value={time.duration > 0 ? Math.min(time.current, time.duration) : 0}
          disabled={!(time.duration > 0)}
          onChange={onSeek}
          style={{ background: `linear-gradient(to right, var(--ds-green-500) ${pct}%, rgba(255, 255, 255, 0.22) ${pct}%)` }}
        />
        <span className="audio-time mono tabular">{fmtTime(time.duration)}</span>
      </div>
      <div className="audio-vol-wrap">
        <Tooltip title={muted || volume === 0 ? 'Unmute' : 'Mute'}>
          <Button shape="circle" type="text" className="audio-vol-btn" icon={<Icon name={muted || volume === 0 ? 'sound-off' : 'sound'} size="sm" />} onClick={toggleMute} aria-label={muted || volume === 0 ? 'Unmute' : 'Mute'} />
        </Tooltip>
        <input
          type="range"
          className="audio-scrubber audio-vol-slider"
          aria-label="Volume"
          min={0}
          max={1}
          step={0.05}
          value={muted ? 0 : volume}
          onChange={onVolume}
          style={{ background: `linear-gradient(to right, var(--ds-green-500) ${volPct}%, rgba(255, 255, 255, 0.22) ${volPct}%)` }}
        />
      </div>
      <audio
        id="bottomGlobalAudio"
        ref={dockRef}
        preload="none"
        aria-label="Call recording player"
        style={{ display: 'none' }}
        onPlay={(e) => onAnyAudioPlay(e.currentTarget)}
        onPause={syncAudioControls}
        onEnded={syncAudioControls}
      />
      <Tooltip title="Close player">
        <Button shape="circle" type="text" className="audio-close" icon={<Icon name="x" size="sm" />} onClick={closeBottomAudioBar} aria-label="Close player" />
      </Tooltip>
    </div>
  );
}
