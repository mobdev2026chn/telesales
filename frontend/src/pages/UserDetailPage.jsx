// ==========================================
// 9. USER DETAILS (/user/:id): calls, recordings and leads for one person
// ==========================================
import { useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { Button, Col, Row } from '../assets/antd';
import Avatar from '../components/common/Avatar';
import { Badge, DirBadge, LeadBadge, OutcomeBadge, PresenceDot, RoleBadge } from '../components/common/Badge';
import DataTable, { Heads, TableRow } from '../components/common/DataTable';
import DateField from '../components/common/DateField';
import EmptyState from '../components/common/EmptyState';
import { Chip } from '../components/common/FilterChips';
import HourBars from '../components/common/HourBars';
import { KpiGrid } from '../components/common/Kpi';
import PageHeader from '../components/common/PageHeader';
import Pager from '../components/common/Pager';
import PlayButton from '../components/common/PlayButton';
import Icon from '../components/common/Icon';
import Progress from '../components/common/Progress';
import UserLink from '../components/common/UserLink';
import { PERIOD_OPTIONS, PIPELINE_STAGES, STAGE_CLASS, STAGE_TITLE, USER_DETAIL_PAGE_SIZE } from '../data/constants';
import { PATHS } from '../data/navigation';
import { setUdDate, setUdPage, setUdPeriod, udUserSet } from '../redux/slices/userDetailSlice';
import { selectScope, selectUdKey } from '../redux/selectors';
import { playCallAudioDirect } from '../utils/audioController';
import { fmtDur, fmtTalk, fmtTs, formatPhone, last10, roleLabel, validPickerDate } from '../utils/format';
import { periodLabel, periodRange } from '../utils/periods';
import { statsFor } from '../utils/scope';
import { hourCounts } from '../utils/stats';
import { fetchUserDetail } from '../utils/actions/userDetailActions';

const CALL_COLS = '1.1fr 1.4fr 1.2fr 0.9fr 0.9fr 0.7fr 0.4fr';
const REC_COLS = '1.1fr 1.6fr 1.2fr 0.8fr 0.8fr 0.4fr';
const LEAD_COLS = '1.4fr 1.1fr 1fr 1.2fr';

function TableCard({ title, sub, cols, head, extra, footer, children }) {
  return (
    <div className="neo-table-card" style={{ marginBottom: 'var(--ds-space-4)' }}>
      <div className="card-header"><div className="card-title">{title}</div><span className="card-subtitle">{sub}</span></div>
      {extra}
      <DataTable cols={cols} head={<Heads labels={head} />}>{children}</DataTable>
      {footer}
    </div>
  );
}

function DetailLine({ label, children }) {
  return <div className="detail-row"><span className="detail-label">{label}</span><span className="detail-value">{children}</span></div>;
}

export default function UserDetailPage() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const location = useLocation();
  const { id: rawId } = useParams();
  const id = rawId || '';
  const ud = useSelector(s => s.userDetail);
  const key = useSelector(selectUdKey);
  const usersState = useSelector(s => s.users);
  const leadsState = useSelector(s => s.leads);
  const { users, visibleIds } = useSelector(selectScope);

  useEffect(() => {
    dispatch(udUserSet(id));
    try { window.scrollTo(0, 0); const main = document.querySelector('main'); if (main) main.scrollTop = 0; } catch { /* ignore */ }
  }, [id, dispatch]);

  const u = users.find(x => x.id === id);
  const inView = !!u && visibleIds.has(u.id);
  const data = ud.ud && ud.ud.key === key ? ud.ud : null;

  useEffect(() => {
    if (ud.userId === id && inView && !data && ud.pendingKey !== key) fetchUserDetail();
  }, [ud.userId, id, inView, data, ud.pendingKey, key, dispatch]);

  // Back: browser history when opened from inside the portal, else the dashboard
  const close = () => {
    if (location.key !== 'default') navigate(-1);
    else navigate(PATHS.dash);
  };
  const onDate = (val) => { if (validPickerDate(val)) dispatch(setUdDate(val)); };

  const header = (title) => (
    <PageHeader title={title} subtitle="Calls, recordings and leads for one person" actionsClass="">
      <div className="pill-group">
        <Button icon={<Icon name="back" size="sm" />} onClick={close}>Back</Button>
        {PERIOD_OPTIONS.map(o => {
          const on = !ud.date && ud.period === o.value;
          return <Chip key={o.value} active={on} pressed onClick={() => dispatch(setUdPeriod(o.value))}>{o.label}</Chip>;
        })}
        <DateField id="udDateInput" value={ud.date} onChange={onDate} label="User details date" />
      </div>
    </PageHeader>
  );

  if (!u) {
    return <>{header('USER DETAILS')}<EmptyState>{usersState.loaded || usersState.error ? 'THIS USER WAS NOT FOUND — THEY MAY HAVE BEEN DELETED.' : 'LOADING USER…'}</EmptyState></>;
  }
  if (!inView) {
    return <>{header('USER DETAILS')}<EmptyState>THIS USER IS NOT IN YOUR TEAM VIEW.</EmptyState></>;
  }

  const periodTxt = periodLabel(ud.period, ud.date);
  const d = data && data.dash ? data.dash : null;
  const row = d ? statsFor(d.teamMembers, u) : null;
  const num = (v) => Math.round(Number(v) || 0);
  const total = num(d && d.totalCalls);
  const connected = num(d && d.connectedCalls);
  const talk = num(d && d.talkSeconds);
  const rate = total ? Math.round(connected / total * 100) : 0;
  const isAgent = u.role !== 'ADMIN';
  const active = connected > 0;
  const mgrUser = users.find(x => x.id === u.mgr);
  const target = Number(u.target) || 0;
  const todayRow = statsFor(usersState.todayMembers, u);
  const todayCalls = todayRow ? num(todayRow.totalCalls) : 0;
  const pct = target > 0 ? Math.min(100, Math.round(todayCalls / target * 100)) : 0;
  const online = !!((row && row.online) || (todayRow && todayRow.online));
  const loadingTxt = data ? '' : 'LOADING…';

  // Call history (this user's calls in the period), 25 per page
  const { from, to } = periodRange(ud.period, ud.date);
  const recs = data && data.recs ? data.recs : [];
  const recFor = (c) => {
    if (c.recordingId) return c.recordingId;
    const p = last10(c.phone);
    const r = recs.find(x => x.ts && last10(x.phone) === p && Math.abs(x.ts - c.ts) < 3 * 60 * 1000);
    return r ? r.id : null;
  };
  const calls = data && data.calls ? data.calls : [];
  const totalPages = Math.max(1, Math.ceil(calls.length / USER_DETAIL_PAGE_SIZE));
  const page = Math.min(Math.max(1, ud.page), totalPages);
  const pageCalls = calls.slice((page - 1) * USER_DETAIL_PAGE_SIZE, page * USER_DETAIL_PAGE_SIZE);
  let callRows;
  if (!data) callRows = <EmptyState>LOADING CALLS…</EmptyState>;
  else if (data.callsError && !data.calls) callRows = <EmptyState error>COULD NOT LOAD CALLS — {data.callsError}</EmptyState>;
  else if (!calls.length) callRows = <EmptyState>NO CALLS {periodTxt}</EmptyState>;
  else {
    callRows = pageCalls.map(c => {
      const recId = recFor(c);
      return (
        <TableRow cols={CALL_COLS} key={c.id}>
          <span className="cell-muted">{fmtTs(c.ts)}</span>
          <span className={c.client ? 'cell-primary' : 'cell-unknown'}>{c.client || 'Unknown caller'}</span>
          <span className="cell-mono phone-number">{formatPhone(c.phone)}</span>
          <DirBadge dir={c.dir} />
          <OutcomeBadge out={c.out} />
          <span className="tabular">{fmtDur(c.dur)}</span>
          <span>{recId ? (
            <PlayButton onClick={() => playCallAudioDirect(recId, 'log')} label={`Play recording of call with ${c.client || formatPhone(c.phone)}`} />
          ) : <span className="muted">—</span>}</span>
        </TableRow>
      );
    });
  }
  const callCount = data ? (data.callsTotal || calls.length) : 0;
  const callCountTxt = data ? `${callCount} CALL${callCount === 1 ? '' : 'S'} ${periodTxt}` : '';
  const pager = data && calls.length > USER_DETAIL_PAGE_SIZE ? (
    <Pager label={`PAGE ${page} / ${totalPages}${data.callsHasMore ? ' · SHOWING THE LATEST 1000' : ''}`} page={page} totalPages={totalPages} onPage={(p) => dispatch(setUdPage(p))} />
  ) : null;

  // Recordings in the period
  const periodRecs = recs.filter(r => r.ts && r.ts >= from && r.ts < to);
  let recRows;
  if (!data) recRows = <EmptyState>LOADING RECORDINGS…</EmptyState>;
  else if (data.recsError && !data.recs) recRows = <EmptyState error>COULD NOT LOAD RECORDINGS — {data.recsError}</EmptyState>;
  else if (!periodRecs.length) recRows = <EmptyState>NO RECORDINGS {periodTxt}</EmptyState>;
  else {
    recRows = periodRecs.slice(0, 50).map(r => (
      <TableRow cols={REC_COLS} key={r.id}>
        <span className="cell-muted">{fmtTs(r.ts)}</span>
        <span className={r.client ? 'cell-primary' : 'cell-unknown'}>{r.client || 'Unknown caller'}</span>
        <span className="cell-mono phone-number">{formatPhone(r.phone)}</span>
        <DirBadge dir={r.dir} />
        <span className="tabular">{fmtDur(r.dur)}</span>
        <span><PlayButton onClick={() => playCallAudioDirect(r.id, 'log')} label={`Play recording with ${r.client || formatPhone(r.phone)}`} /></span>
      </TableRow>
    ));
  }

  // Leads assigned to this user
  const uName = String(u.name || '').trim().toLowerCase();
  const myLeads = leadsState.list.filter(l => (l.agentId ? l.agentId === u.id : String(l.agent || '').trim().toLowerCase() === uName));
  const stageCount = (s) => myLeads.filter(l => l.stage === s).length;
  const recentLeads = myLeads.slice().sort((a, b) => ((b.lastCallDate || b.updatedAt || b.createdAt || 0) - (a.lastCallDate || a.updatedAt || a.createdAt || 0))).slice(0, 10);
  const leadRows = !leadsState.loaded && !leadsState.error ? <EmptyState>LOADING LEADS…</EmptyState>
    : (!myLeads.length ? <EmptyState>NO LEADS ASSIGNED</EmptyState>
      : recentLeads.map(l => (
        <TableRow cols={LEAD_COLS} key={l.id}>
          <span className="cell-primary">{l.name}</span>
          <span className="cell-mono phone-number">{formatPhone(l.phone)}</span>
          <LeadBadge lead={l} />
          <span className="cell-muted">{l.lastCallDate ? `${l.attempts || 0}× · LAST ${fmtTs(l.lastCallDate)}` : 'NOT DIALED YET'}</span>
        </TableRow>
      )));

  const val = (v) => (data ? v : '…');

  return (
    <>
      {header(`${String(u.name || 'USER').toUpperCase()} · DETAILS`)}
      {data && data.dashError && <EmptyState error>COULD NOT LOAD THE NUMBERS — {data.dashError}</EmptyState>}
      <Row gutter={[16, 16]} className="equal-row">
        <Col xs={24} lg={9}>
          <div className="card">
            <div className="user-hero">
              <Avatar user={u} className="avatar-lg" />
              <div style={{ minWidth: 0 }}>
                <div className="user-hero-name">{u.name}</div>
                <div className="user-hero-tags">
                  <RoleBadge role={u.role} />
                  {isAgent && data && (
                    <span className={`status-text ${active ? 'text-success' : 'text-danger'}`}>
                      <PresenceDot online={active} />{active ? `${connected} CONNECTED ${periodTxt}` : `NO CONNECTED CALLS ${periodTxt}`}
                    </span>
                  )}
                </div>
              </div>
            </div>
            <div className="detail-list">
              <DetailLine label="Login email">{u.email || '—'}</DetailLine>
              <DetailLine label="Phone / SIM"><span className="mono phone-number">{formatPhone(u.phone)}</span></DetailLine>
              <DetailLine label="Reports to">{mgrUser ? <><UserLink user={mgrUser} /> ({roleLabel(mgrUser.role)})</> : 'Top Level / Admin'}</DetailLine>
              <DetailLine label="Team">{u.team || '—'}</DetailLine>
              <DetailLine label="App status">
                {online ? <Badge tone="success" dot>SIGNED IN</Badge>
                  : <span className="muted">NOT SIGNED IN</span>}
              </DetailLine>
            </div>
            {isAgent && (
              <div style={{ paddingTop: 12 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                  <span className="detail-label">Today vs daily target</span>
                  <strong className="tabular">{target > 0 ? `${todayCalls}/${target} (${pct}%)` : 'NO TARGET'}</strong>
                </div>
                <Progress pct={pct} lg />
              </div>
            )}
          </div>
        </Col>
        <Col xs={24} lg={15}>
          <div className="card">
            <div className="card-header"><div className="card-title">Call activity by hour</div><span className="card-subtitle">{periodTxt}</span></div>
            <div className="hour-bars"><HourBars byHour={hourCounts(d && d.hourlyAll)} /></div>
            <div className="stat-list">
              <div className="stat-row"><span>Connect rate</span><strong>{loadingTxt || `${rate}%`}</strong></div>
              <div className="stat-row"><span>Avg connected duration</span><strong>{loadingTxt || fmtDur(num(d && d.avgDurationSeconds))}</strong></div>
              <div className="stat-row"><span>Unique clients reached</span><strong>{loadingTxt || num(d && d.uniqueClients)}</strong></div>
            </div>
          </div>
        </Col>
      </Row>

      <KpiGrid items={[
        { label: `Total calls · ${periodTxt}`, value: val(total), meta: `${fmtTalk(talk)} talk time`, tone: 'dark' },
        { label: 'Connected', value: val(connected), meta: `${rate}% connect rate`, tone: 'brand' },
        { label: 'Incoming', value: val(num(d && d.incoming)), meta: 'Inbound calls received' },
        { label: 'Outgoing', value: val(num(d && d.outgoing)), meta: 'Outbound calls dialed' },
        { label: 'Missed calls', value: val(num(d && d.missed)), meta: 'Unanswered inbound calls', tone: 'danger' },
        { label: 'Rejected / no answer', value: val(num(d && d.rejected)), meta: 'Declined or not picked up', tone: 'warning' },
        { label: 'Recordings', value: val(periodRecs.length), meta: 'Calls with a recording' },
        { label: 'Leads assigned', value: myLeads.length, meta: `${stageCount('CONVERTED')} converted`, tone: 'lime' },
      ]} />

      <TableCard title="Call history" sub={callCountTxt} cols={CALL_COLS} head={['Time', 'Client', 'Phone', 'Direction', 'Outcome', 'Duration', 'Rec']} footer={pager}>
        {callRows}
      </TableCard>
      <TableCard title="Call recordings" sub={`${periodTxt}${periodRecs.length > 50 ? ' · LATEST 50' : ''}`} cols={REC_COLS} head={['Time', 'Client', 'Phone', 'Direction', 'Duration', 'Play']}>
        {recRows}
      </TableCard>
      <TableCard
        title="Assigned leads"
        sub={`${myLeads.length} total · latest 10 shown`}
        cols={LEAD_COLS}
        head={['Lead', 'Phone', 'Status', 'Dial activity']}
        extra={(
          <div className="pill-group" style={{ padding: '12px var(--ds-space-5)' }}>
            {PIPELINE_STAGES.map(s => <span key={s} className={`badge ${STAGE_CLASS[s]}`}>{STAGE_TITLE[s]} · {stageCount(s)}</span>)}
          </div>
        )}
      >
        {leadRows}
      </TableCard>
    </>
  );
}
