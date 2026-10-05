// DOCKED BOTTOM AUDIO PLAYER BAR (driven by utils/audioController)
import { useCallback } from 'react';
import { useSelector } from 'react-redux';
import { Button, Tooltip } from '../../assets/antd';
import {
  audioCtlStep, audioCtlToggle, closeBottomAudioBar, onAnyAudioPlay, registerDock, syncAudioControls,
} from '../../utils/audioController';
import Icon from '../common/Icon';

export default function AudioPlayerBar() {
  const audio = useSelector(s => s.ui.audio);
  const dockRef = useCallback((el) => { if (el) registerDock(el); }, []);

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
        <span className="muted mono" style={{ fontSize: 'var(--ds-fs-2xs)', whiteSpace: 'nowrap' }}>
          {audio.idx >= 0 ? `${audio.idx + 1} / ${audio.total}` : ''}
        </span>
      </div>
      <audio
        id="bottomGlobalAudio"
        ref={dockRef}
        controls
        preload="none"
        aria-label="Call recording player"
        style={{ display: audio.showNative ? 'block' : 'none' }}
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
