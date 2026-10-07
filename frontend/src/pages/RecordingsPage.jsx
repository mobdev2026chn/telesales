// ==========================================
// 6. CALL RECORDINGS · REVIEWS (saved to the server)
// ==========================================
import { useEffect, useMemo, useRef, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button, Input, Rate, Select } from '../assets/antd';
import { Badge, DirBadge } from '../components/common/Badge';
import EmptyState from '../components/common/EmptyState';
import FilterChips, { Chip } from '../components/common/FilterChips';
import Icon from '../components/common/Icon';
import PageHeader from '../components/common/PageHeader';
import Pager from '../components/common/Pager';
import UserLink from '../components/common/UserLink';
import { CALL_RANGE_OPTIONS, CRIT, REC_FILTERS, REC_PAGE_SIZE } from '../data/constants';
import { setRecFilter, setRecordingDraft, setRecPage } from '../redux/slices/recordingsSlice';
import { selectRecsQueryKey, selectScope } from '../redux/selectors';
import { recordingAudioUrl } from '../utils/api';
import { currentAudioEl, handoffToDock, onAnyAudioPlay, setPlaylist, syncAudioControls } from '../utils/audioController';
import { exportRows } from '../utils/excel';
import { fmtClock, fmtDur, fmtIstFull, fmtTs, formatPhone, istDateStr, roleLabel } from '../utils/format';
import { newRecMeta } from '../utils/mappers';
import { rangeBounds } from '../utils/periods';
import { isShortRecording, reviewAverage } from '../utils/recordings';
import { callBelongsTo } from '../utils/scope';
import { paginate } from '../utils/table';
import { changeRecAgent, changeRecRange, fetchRecordings, reviewRecording, saveRecordingFeedback, setRecordingStar, toggleRecordingPin } from '../utils/actions/recordingActions';

export default function RecordingsPage() {
  const dispatch = useDispatch();
  const rs = useSelector(s => s.recordings);
  const queryKey = useSelector(selectRecsQueryKey);
  const authUser = useSelector(s => s.auth.authUser);
  const { users, scoped, isCallInScope } = useSelector(selectScope);
  const topRef = useRef(null);

  // Agent filter: the same people as the Call Log's agent filter
  const agentValid = rs.agent === 'ALL' || scoped.some(u => u.id === rs.agent);
  useEffect(() => {
    if (!agentValid) changeRecAgent('ALL');
  }, [agentValid, dispatch]);

  const isPinned = (c) => !!(rs.recMeta[c.id] && rs.recMeta[c.id].pinned);

  // Recordings in view before the chip filter: scope, date range and agent
  const base = useMemo(() => {
    const { from } = rangeBounds(rs.range, 0);
    let recs = rs.list.filter(isCallInScope).filter(c => !isShortRecording(c)).filter(c => c.ts && c.ts >= from);
    if (rs.agent !== 'ALL') {
      const agent = users.find(u => u.id === rs.agent);
      recs = agent ? recs.filter(c => callBelongsTo(c, agent)) : [];
    }
    return recs;
  }, [rs.list, rs.range, rs.agent, isCallInScope, users]);

  const recs = useMemo(() => {
    const f = rs.filter;
    let list = base;
    if (f === 'PINNED') list = list.filter(isPinned);
    if (f === 'UNPINNED') list = list.filter(c => !isPinned(c));
    if (f === 'IN') list = list.filter(c => c.dir === 'IN');
    if (f === 'OUT') list = list.filter(c => c.dir === 'OUT');
    if (f === '5+') list = list.filter(c => c.dur >= 300);
    if (f === '-5') list = list.filter(c => c.dur < 300);
    if (['PENDING', 'APPROVED', 'FLAGGED'].includes(f)) list = list.filter(c => (rs.recMeta[c.id] ? rs.recMeta[c.id].status : 'PENDING') === f);
    return list;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [base, rs.filter, rs.recMeta]);

  const recIds = useMemo(() => recs.map(c => c.id), [recs]);
  useEffect(() => { setPlaylist('rec', recIds); }, [recIds]);

  const pinnedCount = base.filter(isPinned).length;
  const pg = paginate(recs, rs.page, REC_PAGE_SIZE);

  // Only part of the list is loaded at a time: unfiltered, show the server's full count for this scope
  // (the server's count includes the hidden 1-second files, so those loaded are taken off)
  const shortLoaded = rs.list.filter(c => isCallInScope(c) && isShortRecording(c)).length;
  const recTotal = rs.filter === 'ALL' && rs.scopeKey === `${queryKey}|${rs.range}` ? Math.max((rs.total || 0) - shortLoaded, recs.length) : recs.length;

  const filters = [
    ...REC_FILTERS,
    { value: 'PINNED', label: <>Pinned · <span>{pinnedCount}</span></>, title: 'Recordings pinned for the app' },
    { value: 'UNPINNED', label: <>Unpinned · <span>{base.length - pinnedCount}</span></> },
  ];

  const changePage = (p) => {
    dispatch(setRecPage(p));
    try { topRef.current.scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch { /* ignore */ }
  };

  const exportReviews = () => {
    exportRows(recs.map(c => {
      const meta = rs.recMeta[c.id] || newRecMeta();
      const { avg } = reviewAverage(meta.crit);
      const row = {
        Agent: c.agent,
        Client: c.client || '',
        Phone: c.phone,
        'Date / Time (IST)': fmtIstFull(c.ts),
        Direction: c.dir === 'IN' ? 'Inbound' : (c.dir === 'OUT' ? 'Outbound' : ''),
        'Duration (s)': c.dur,
        Status: meta.status,
        Pinned: meta.pinned ? 'Yes' : 'No',
      };
      CRIT.forEach(([k, label]) => { row[label] = Number(meta.crit[k]) || 0; });
      row['Average score'] = avg !== null ? Number(avg.toFixed(2)) : '';
      row.Feedback = (meta.comments || []).map(cm => `${cm.by || 'Reviewer'}: ${cm.text}`).join(' | ');
      row.File = c.fileName;
      return row;
    }), 'Recording reviews', `recording-reviews-${istDateStr(new Date())}.xlsx`);
  };

  let listBody;
  if (recs.length === 0) {
    let msg = 'NO RECORDINGS MATCH THIS FILTER.';
    if (rs.error) msg = `COULD NOT LOAD RECORDINGS — ${rs.error}`;
    else if (!rs.loaded) msg = 'LOADING RECORDINGS…';
    listBody = <div className="card"><EmptyState error={!!rs.error}>{msg}</EmptyState></div>;
  } else {
    listBody = pg.rows.map(c => <RecordingCard key={c.id} rec={c} meta={rs.recMeta[c.id] || newRecMeta()} users={users} />);
  }

  return (
    <div ref={topRef}>
      <PageHeader
        title="Call Recordings"
        subtitle={`${recTotal} recording${recTotal === 1 ? '' : 's'}${recTotal > recs.length ? ` (${recs.length} loaded)` : ''} · review, score and coach`}
      >
        <span className="muted" style={{ fontSize: 'var(--ds-fs-sm)' }}>Reviewer</span>
        <span className="badge badge-outline badge-lg">{(authUser && authUser.name ? authUser.name : '—').toUpperCase()}</span>
        <Button icon={<Icon name="download" size="sm" />} onClick={exportReviews} title="Export the filtered recording reviews to Excel">Export reviews</Button>
      </PageHeader>

      <div className="toolbar">
        <FilterChips id="recFilterChips" options={filters} value={rs.filter} onChange={(v) => dispatch(setRecFilter(v))} />
        <div className="pill-group toolbar-spacer">
          <label htmlFor="recRangeSelect" className="visually-hidden">Date range</label>
          <Select id="recRangeSelect" className="toolbar-ant-select" value={rs.range} onChange={(v) => changeRecRange(v)}
            options={CALL_RANGE_OPTIONS} suffixIcon={<Icon name="calendar" size="sm" />} />
          <label htmlFor="recAgentFilter" className="visually-hidden">Agent</label>
          <Select id="recAgentFilter" className="toolbar-ant-select" value={agentValid ? rs.agent : 'ALL'} onChange={(v) => changeRecAgent(v)}
            showSearch optionFilterProp="label" popupMatchSelectWidth={false}
            options={[{ value: 'ALL', label: 'ALL AGENTS' }, ...scoped.map(u => ({ value: u.id, label: `${u.name.toUpperCase()} (${roleLabel(u.role)})` }))]} />
        </div>
      </div>

      <div className="stack" style={{ gap: 'var(--ds-space-4)' }}>{listBody}</div>
      <Pager className="pager-bar" label={`PAGE ${pg.page} / ${pg.totalPages} · ${recs.length} RECORDINGS`} page={pg.page} totalPages={pg.totalPages} onPage={changePage}>
        {rs.hasMore && <Chip icon={<Icon name="history" size="sm" />} onClick={() => fetchRecordings(true)}>Load older</Chip>}
      </Pager>
    </div>
  );
}

function RecordingCard({ rec: c, meta, users }) {
  const audioRef = useRef(null);
  const [clock, setClock] = useState({ cur: 0, total: c.dur });
  const agentUser = users.find(u => u.id === c.callerId) || null;
  const mgrUser = agentUser ? users.find(m => m.id === agentUser.mgr) : null;
  const teamName = mgrUser ? mgrUser.name.toUpperCase() : 'MANAGEMENT';
  const on = !!meta.pinned;
  // Source file and quality audit open from the card's Details toggle
  const [open, setOpen] = useState(false);
  const st = meta.status || 'PENDING';
  const detailsId = `recDetails_${String(c.id).replace(/[^A-Za-z0-9_-]/g, '_')}`;

  // Card time: "current / total" — total is the audio file's length once known, else the call's talk time
  const updateClock = (el) => {
    const total = el.duration && isFinite(el.duration) && el.duration > 0 ? el.duration : c.dur;
    setClock({ cur: el.currentTime, total });
  };

  // The card leaves the list while its recording plays: keep playing in the docked player
  useEffect(() => {
    const el = audioRef.current;
    return () => {
      if (el && currentAudioEl() === el && !el.paused && !el.ended) {
        const time = el.currentTime;
        try { el.pause(); } catch { /* ignore */ }
        handoffToDock(c.id, time);
      }
    };
  }, [c.id]);

  return (
    <div className={`card rec-card${open ? ' is-open' : ''}`}>
      <div className="rec-card-top">
        <div style={{ minWidth: 0, display: 'flex', alignItems: 'center', gap: 12 }}>
          <span className="kpi-icon" style={{ width: 38, height: 38 }}><Icon name="headphones" /></span>
          <div style={{ minWidth: 0 }}>
            <div className="rec-card-title">
              <UserLink user={{ id: c.callerId, phone: c.callerPhone, name: c.agent }} label={c.agent} /> <span className="muted">→</span> {c.client || formatPhone(c.phone)}
            </div>
            <div className="rec-card-meta">
              {fmtTs(c.ts)} · <strong className="text-2">{fmtDur(c.dur)}</strong> <DirBadge dir={c.dir} />{c.sim && <> <span>SIM {c.sim}</span></>}
            </div>
          </div>
          <span>
            <Button size="small" aria-pressed={on} disabled={meta.pinBusy} onClick={() => toggleRecordingPin(c.id)}
              title={on ? 'Unpin: remove from the top of the app list' : 'Pin: show this recording first in the app'}
              className={on ? 'btn-lime-ant' : ''} icon={<Icon name={on ? 'pin-filled' : 'pin'} size="sm" />}>
              {on ? 'Pinned · Unpin' : 'Pin'}
            </Button>
          </span>
        </div>
        <div className="rec-audio-wrap">
          <span className="rec-timer"><Icon name="clock" size="sm" /><span aria-label="Played / total length">{fmtClock(clock.cur)} / {fmtClock(clock.total)}</span></span>
          <audio
            ref={audioRef}
            data-rec-id={c.id}
            data-dur={c.dur}
            controls
            preload="metadata"
            aria-label={`Recording: ${c.agent} and ${c.client || formatPhone(c.phone)}`}
            src={recordingAudioUrl(c.id)}
            onPlay={(e) => onAnyAudioPlay(e.currentTarget)}
            onPause={syncAudioControls}
            onEnded={syncAudioControls}
            onLoadedMetadata={(e) => updateClock(e.currentTarget)}
            onTimeUpdate={(e) => updateClock(e.currentTarget)}
          />
          <Button className="rec-toggle" aria-expanded={open} aria-controls={detailsId} onClick={() => setOpen(v => !v)}
            title={open ? 'Hide details' : 'Show source file and quality audit'}>
            <Badge tone={st === 'APPROVED' ? 'success' : (st === 'FLAGGED' ? 'danger' : 'neutral')}>{st}</Badge>
            Details<Icon name="down" size="sm" className="rec-toggle-chevron" />
          </Button>
        </div>
      </div>
      <div className="rec-details" id={detailsId} inert={!open}>
        <div className="rec-details-inner">
          <div className="rec-source">
            <div style={{ minWidth: 0, overflowWrap: 'anywhere' }}><Icon name="file" size="sm" /> <strong>Source file:</strong> <span className="muted">{c.fileName || '—'}</span></div>
            <div><Icon name="users" size="sm" /> <strong>Team audit:</strong> {teamName}&apos;S TEAM</div>
          </div>
          <div className="rec-review">
            <ReviewSection id={c.id} meta={meta} />
          </div>
        </div>
      </div>
    </div>
  );
}

function ReviewSection({ id, meta }) {
  const dispatch = useDispatch();
  const st = meta.status || 'PENDING';
  const stTone = st === 'APPROVED' ? 'success' : (st === 'FLAGGED' ? 'danger' : 'neutral');
  const { scored, avg } = reviewAverage(meta.crit);
  const overallText = avg !== null ? `${avg.toFixed(1)} / 5 · ${scored}/6 SCORED` : 'NOT SCORED YET';
  const saveTone = meta.saveState === 'NOT SAVED' ? 'text-danger' : 'muted';
  const draftId = `recDraft_${String(id).replace(/[^A-Za-z0-9_-]/g, '_')}`;

  return (
    <>
      <div className="rec-review-head">
        <span className="card-title" style={{ fontSize: 'var(--ds-fs-base)' }}>Quality audit <span className="card-subtitle">· click the stars to rate</span></span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          {meta.saveState && <span className={`${saveTone} fw-600`} style={{ fontSize: 'var(--ds-fs-xs)' }} role="status">{meta.saveState}</span>}
          <Badge tone={stTone} dot>{st}</Badge>
        </span>
      </div>
      <div className="criteria-grid">
        {CRIT.map(([k, label]) => {
          const rating = Number(meta.crit[k]) || 0;
          return (
            <div className="criteria-item" key={k}>
              <span>{label}</span>
              <Rate className="crit-rate" value={rating} allowClear={false} aria-label={`${label} rating`}
                tooltips={[1, 2, 3, 4, 5].map(i => `${label}: ${i} of 5`)}
                onChange={(i) => setRecordingStar(id, k, i)} />
            </div>
          );
        })}
      </div>
      <div className="rec-review-foot">
        <span className="fw-600" style={{ fontSize: 'var(--ds-fs-sm)' }}>Overall · <span className="text-2">{overallText}</span></span>
        <div className="cell-actions">
          <Button type="primary" size="small" icon={<Icon name="check" size="sm" />} onClick={() => reviewRecording(id, 'APPROVED')}>Approve</Button>
          <Button danger size="small" icon={<Icon name="flag" size="sm" />} onClick={() => reviewRecording(id, 'FLAGGED')}>Flag for coaching</Button>
        </div>
      </div>
      {(meta.comments || []).map((cm, i) => (
        <div className="comment-bubble" key={i}>
          <strong>{cm.by || 'Reviewer'}{cm.byRole ? ` (${roleLabel(String(cm.byRole).toUpperCase())})` : ''}{cm.at ? ` · ${fmtTs(cm.at)}` : ''}:</strong> {cm.text}
        </div>
      ))}
      <div className="rec-feedback-row">
        <label htmlFor={draftId} className="visually-hidden">Coaching feedback</label>
        <Input id={draftId} value={meta.draft || ''} placeholder="Provide coaching feedback for this caller…"
          onChange={(e) => dispatch(setRecordingDraft({ id, draft: e.target.value }))}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); saveRecordingFeedback(id); } }} />
        <Button className="btn-ink" icon={<Icon name="send" size="sm" />} onClick={() => saveRecordingFeedback(id)}>Send feedback</Button>
      </div>
    </>
  );
}
