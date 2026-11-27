// ==========================================
// 1. DASHBOARD: server numbers for the period + the team table
// ==========================================
import { useEffect, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { useNavigate } from 'react-router-dom';
import { Col, Row, Select } from '../assets/antd';
import { CountPill, PresenceDot } from '../components/common/Badge';
import DataTable, { TableRow } from '../components/common/DataTable';
import DateField from '../components/common/DateField';
import EmptyState from '../components/common/EmptyState';
import FilterChips from '../components/common/FilterChips';
import HourBars from '../components/common/HourBars';
import { KpiGrid } from '../components/common/Kpi';
import ManagerChain from '../components/common/ManagerChain';
import MgrFilterSelect from '../components/common/MgrFilterSelect';
import PageHeader from '../components/common/PageHeader';
import Pager from '../components/common/Pager';
import Progress from '../components/common/Progress';
import UserLink from '../components/common/UserLink';
import { DASH_TEAM_PAGE_SIZE, LEADERBOARD_TYPE_OPTIONS, PERIOD_OPTIONS } from '../data/constants';
import { userPath } from '../data/navigation';
import { setDashDate, setDashMgrFilter, setDashPeriod, setDashTeamPage, setDashTypeFilter } from '../redux/slices/dashboardSlice';
import { selectDashKey, selectScope } from '../redux/selectors';
import { fmtDur, fmtTalk, fmtTs, formatPhone, istDateStr, istMidnight, validPickerDate } from '../utils/format';
import { mapRecording } from '../utils/mappers';
import { notify } from '../utils/notify';
import { paginate } from '../utils/table';
import { periodLabel, periodTargetDays, periodWindow } from '../utils/periods';
import { managerChainText, mgrFilterOptions, mgrFilterSet, statsFor } from '../utils/scope';
import { appPresence, demoHourCounts, hourCounts, presenceTitle } from '../utils/stats';
import { recordingService } from '../utils/services';
import { fetchDemos } from '../utils/actions/demoActions';
import { fetchDashboard } from '../utils/actions/statsActions';

const TEAM_COLS = '1.3fr 1.3fr 1.1fr 0.8fr 0.9fr 0.9fr 1.4fr';
const presenceTime = (value) => {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : fmtTs(date);
};

export default function DashboardPage() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const dash = useSelector(s => s.dashboard);
  const key = useSelector(selectDashKey);
  const usersError = useSelector(s => s.users.error);
  const { users, visible, scoped } = useSelector(selectScope);
  const dashboardCallers = scoped.filter(u => u.role === 'CALLER');

  const server = dash.data && dash.dataKey === key ? dash.data : null;
  const failed = dash.errorKey === key;

  // Fetch when the period / scope changes and nothing is cached, pending or failed for it
  useEffect(() => {
    if (!server && dash.pendingKey !== key && dash.errorKey !== key) fetchDashboard();
  }, [key, server, dash.pendingKey, dash.errorKey, dispatch]);

  // Managed-by filter: falls back to ALL when the chosen person left the view
  const mgrOptions = mgrFilterOptions(users, visible);
  const mgrValue = mgrOptions.some(o => o.value === dash.mgrFilter) ? dash.mgrFilter : 'ALL';
  useEffect(() => {
    if (server && mgrValue !== dash.mgrFilter) dispatch(setDashMgrFilter('ALL'));
  }, [server, mgrValue, dash.mgrFilter, dispatch]);

  const onDate = (val) => {
    if (!val) { dispatch(setDashDate(null)); return; }
    if (!validPickerDate(val)) {
      notify('PLEASE SELECT A VALID YEAR (2020 - 2030)');
      dispatch(setDashDate(null));
      return;
    }
    dispatch(setDashDate(val));
  };

  const n = (v) => Number(v) || 0;
  const typeValue = dash.typeFilter || 'ALL';

  // Client-side fallback / instant filter over teamMembers when a type is chosen
  const typeMembers = server && Array.isArray(server.teamMembers) && typeValue !== 'ALL'
    ? server.teamMembers.filter(member => {
        const u = users.find(x => x.id === member.id || x.phone === member.phone);
        const empType = (u && u.employeeType) || member.employeeType || 'sales_team';
        return empType === typeValue;
      })
    : null;

  const m = server ? (typeMembers ? {
    total: typeMembers.reduce((s, r) => s + n(r.totalCalls), 0),
    connected: typeMembers.reduce((s, r) => s + n(r.connectedCalls), 0),
    talkSeconds: typeMembers.reduce((s, r) => s + n(r.talkTimeSeconds), 0),
    incoming: typeMembers.reduce((s, r) => s + n(r.incomingCalls), 0),
    outgoing: typeMembers.reduce((s, r) => s + n(r.outgoingCalls), 0),
    missed: typeMembers.reduce((s, r) => s + n(r.missedCalls), 0),
    rejected: typeMembers.reduce((s, r) => s + n(r.rejectedCalls), 0),
    neverAttended: typeMembers.reduce((s, r) => s + n(r.neverAttendedCalls), 0),
    uniqueClients: n(server.uniqueClients),
  } : {
    total: n(server.totalCalls), connected: n(server.connectedCalls), talkSeconds: n(server.talkSeconds),
    incoming: n(server.incoming), outgoing: n(server.outgoing), missed: n(server.missed), rejected: n(server.rejected),
    neverAttended: n(server.neverAttended), uniqueClients: n(server.uniqueClients),
  }) : null;
  const rate = m && m.total ? Math.round((m.connected / m.total) * 100) : 0;
  const avgDur = m && m.connected ? Math.round(m.talkSeconds / m.connected) : 0;
  const inPct = m && m.total ? Math.round((m.incoming / m.total) * 100) : 0;
  const dashTxt = (v) => (m ? v : '—');
  const callsTxt = (k) => (m ? `${m[k]} CALL${m[k] === 1 ? '' : 'S'}` : '—');

  // Days in the period: per-user targets and the team target are daily target × these days
  const targetDays = periodTargetDays(dash.period, dash.customDate);
  // Team target: the server's sum of the agents' (callers') daily targets in scope (0 / missing = no
  // card). When the Type filter narrows the numbers above here, the agents of that type are summed so
  // calls and target match.
  const typeCallers = typeMembers ? typeMembers.filter(r => String(r.role || 'caller').toLowerCase() === 'caller') : null;
  const teamDailyTarget = server && n(server.teamDailyTarget) > 0
    ? (typeCallers && typeCallers.every(r => r.dailyTarget !== undefined)
      ? typeCallers.reduce((s, r) => s + n(r.dailyTarget), 0)
      : n(server.teamDailyTarget))
    : 0;
  const showTeamTarget = !!m && teamDailyTarget > 0;

  return (
    <>
      <PageHeader title="Dashboard" subtitle="Team performance and call metrics">
        <label htmlFor="dashTypeFilter" className="visually-hidden">Filter by type</label>
        <Select
          id="dashTypeFilter"
          className="toolbar-ant-select"
          value={typeValue}
          options={LEADERBOARD_TYPE_OPTIONS}
          onChange={(v) => dispatch(setDashTypeFilter(v))}
          style={{ width: 175 }}
        />
        <FilterChips options={PERIOD_OPTIONS} value={dash.customDate ? null : dash.period} onChange={(p) => dispatch(setDashPeriod(p))}>
          <DateField id="dashDateInput" value={dash.customDate} onChange={onDate} label="Dashboard date" title="Filter by date (2020-2030)" />
        </FilterChips>
      </PageHeader>

      <KpiGrid items={[
        { label: 'Total calls', value: dashTxt(m && m.total), meta: m ? `${fmtTalk(m.talkSeconds)} total talk time` : (failed ? 'Could not load' : 'Loading…'), tone: 'dark' },
        { label: 'Incoming', value: dashTxt(m && m.incoming), meta: m ? `${m.incoming} inbound received` : 'Inbound calls received', tone: 'success' },
        { label: 'Outgoing', value: dashTxt(m && m.outgoing), meta: m ? `${m.outgoing} outbound dialed` : 'Outbound calls dialed' },
        { label: 'Connected', value: dashTxt(m && m.connected), meta: m ? `${rate}% connect rate` : '—', tone: 'brand' },
        { label: 'Missed calls', value: dashTxt(m && m.missed), meta: 'Unanswered inbound calls', tone: 'danger' },
        { label: 'Rejected / no answer', value: dashTxt(m && m.rejected), meta: 'Declined or not picked up', tone: 'warning' },
        { label: 'Never attended', value: dashTxt(m && m.neverAttended), meta: 'Missed + rejected follow-ups' },
        { label: 'Unique calls', value: dashTxt(m && m.uniqueClients), meta: 'Distinct clients reached', tone: 'lime' },
      ]} />

      <Row gutter={[16, 16]} className="equal-row">
        <Col xs={24} lg={showTeamTarget ? 15 : 24}>
          <TeamNowCard
            server={server}
            failed={failed}
            error={dash.error}
            usersError={usersError}
            callers={dashboardCallers}
            typeFilter={typeValue}
            users={users}
            mgrValue={mgrValue}
          />
        </Col>
        {showTeamTarget && (
          <Col xs={24} lg={9}>
            <TeamTargetCard
              calls={m.total}
              dailyTarget={teamDailyTarget}
              days={targetDays}
              label={periodLabel(dash.period, dash.customDate)}
            />
          </Col>
        )}
      </Row>

      <Row gutter={[16, 16]} className="equal-row">
        <Col xs={24} lg={9}>
          <div className="card">
            <div className="card-header"><div className="card-title">Call mix</div><span className="card-subtitle">Inbound vs outbound</span></div>
            <div className="mix-bar">
              <div style={{ background: 'var(--ds-green-500)', width: `${m && m.total ? Math.max(3, inPct) : 0}%` }} />
              <div style={{ flex: 1 }} />
            </div>
            <div className="mix-legend">
              <span><span className="legend-swatch" style={{ background: 'var(--ds-green-500)' }} />Inbound · <strong>{callsTxt('incoming')}</strong></span>
              <span><span className="legend-swatch" style={{ background: 'var(--ds-ink-900)' }} />Outbound · <strong>{callsTxt('outgoing')}</strong></span>
            </div>
            <div className="stat-list">
              <div className="stat-row"><span>Connect rate</span><strong>{m ? `${rate}%` : '—'}</strong></div>
              <div className="stat-row"><span>Avg connected duration</span><strong>{m ? fmtDur(avgDur) : '—'}</strong></div>
              <div className="stat-row"><span>Unique clients reached</span><strong>{dashTxt(m && m.uniqueClients)}</strong></div>
            </div>
          </div>
        </Col>

        <Col xs={24} lg={15}>
          <HourlyCard server={server} period={dash.period} customDate={dash.customDate} />
        </Col>
      </Row>

      <TeamPerformance
        server={server}
        failed={failed}
        error={dash.error}
        usersError={usersError}
        callers={dashboardCallers}
        typeFilter={typeValue}
        users={users}
        mgrOptions={mgrOptions}
        mgrValue={mgrValue}
        page={dash.teamPage}
        targetDays={targetDays}
        onMgr={(v) => dispatch(setDashMgrFilter(v))}
        onPage={(p) => dispatch(setDashTeamPage(p))}
        onOpen={(id) => navigate(userPath(id))}
      />
    </>
  );
}

// "Team right now" groups, in display order. A break wins over a recent call.
const TEAM_NOW_GROUPS = [
  { key: 'onCall', label: 'On call', color: 'var(--ds-green-700)', title: 'Made or took a call in the last 15 minutes' },
  { key: 'available', label: 'Available', color: 'var(--ds-green-400)', title: 'Signed in to the app, no call in the last 15 minutes' },
  { key: 'onBreak', label: 'On break', color: 'var(--ds-warning-dot)', title: 'On a break in the app' },
  { key: 'offline', label: 'Offline', color: 'var(--ds-chain-sep)', title: 'Not signed in to the app' },
];

// Each person in view → on call / available / on break / offline, plus whether call recording is off.
// Reads the same live rows the presence events update (teamMembers, callerLiveStatuses).
function teamNowGroups(server, people) {
  const groups = { onCall: [], available: [], onBreak: [], offline: [], recOff: [] };
  const disabled = Array.isArray(server.disabledRecorders) ? server.disabledRecorders : [];
  people.forEach(u => {
    const row = statsFor(server.teamMembers, u);
    const live = statsFor(server.callerLiveStatuses, u);
    if (row && row.onBreak) {
      const since = row.breakStartedAt ? ` since ${presenceTime(row.breakStartedAt)}` : '';
      groups.onBreak.push({ u, note: `${row.breakType || 'Break'}${since}` });
    } else if (live && live.status === 'ON CALL') {
      groups.onCall.push({ u });
    } else if (row ? appPresence(row).online : (live && live.status === 'ONLINE')) {
      groups.available.push({ u });
    } else {
      groups.offline.push({ u, note: row && row.lastSeenAt ? `last seen ${presenceTime(row.lastSeenAt)}` : '' });
    }
    const off = statsFor(disabled, u);
    if (off || (row && row.autoRecordEnabled === false)) {
      const at = (off && off.disabledAt) || (row && row.autoRecordDisabledAt);
      groups.recOff.push({ u, note: at ? `off since ${presenceTime(at)}` : '' });
    }
  });
  return groups;
}

// Live team board: counts per state for the people in the team table's view; a count opens the names
function TeamNowCard({ server, failed, error, usersError, callers, typeFilter = 'ALL', users, mgrValue }) {
  const [open, setOpen] = useState(null);
  const toggle = (k) => setOpen(cur => (cur === k ? null : k));

  let body;
  if (!server) {
    body = <EmptyState error={failed}>{failed ? `COULD NOT LOAD DASHBOARD — ${error || ''}` : 'LOADING LIVE NUMBERS…'}</EmptyState>;
  } else if (!callers.length) {
    body = <EmptyState>{usersError ? `COULD NOT LOAD USERS — ${usersError}` : 'NO TEAM MEMBERS IN THIS VIEW'}</EmptyState>;
  } else {
    // Same people as the team table: callers in view, then the Type and "Managed by" filters
    const set = mgrFilterSet(users, mgrValue);
    const people = callers
      .filter(u => typeFilter === 'ALL' || ((u && u.employeeType) || 'sales_team') === typeFilter)
      .filter(u => !set || set.has(u.id));
    const groups = teamNowGroups(server, people);
    const openMeta = open === 'recOff' ? { label: 'Recording off' } : TEAM_NOW_GROUPS.find(g => g.key === open);
    const openGroup = openMeta ? { label: openMeta.label, list: groups[open] } : null;
    const recOff = groups.recOff.length;

    body = (
      <>
        <div className="team-now-grid">
          {TEAM_NOW_GROUPS.map(g => (
            <button
              type="button"
              key={g.key}
              className={`team-now-tile${open === g.key ? ' is-active' : ''}`}
              aria-expanded={open === g.key}
              aria-controls="teamNowNames"
              title={`${g.title} · click for names`}
              onClick={() => toggle(g.key)}
            >
              <span className="team-now-label"><span className="team-now-swatch" style={{ background: g.color }} aria-hidden="true" />{g.label}</span>
              <span className="team-now-count">{groups[g.key].length}</span>
            </button>
          ))}
        </div>
        <div className="team-now-foot">
          <button
            type="button"
            className={`team-now-recoff${recOff ? ' has-off' : ''}${open === 'recOff' ? ' is-active' : ''}`}
            aria-expanded={open === 'recOff'}
            aria-controls="teamNowNames"
            title="Callers whose phone has call recording turned off · click for names"
            onClick={() => toggle('recOff')}
          >
            Recording off: <strong>{recOff}</strong>
          </button>
          <span className="card-subtitle">{people.length} {people.length === 1 ? 'caller' : 'callers'} in this view</span>
        </div>
        {openGroup && (
          <div className="team-now-names" id="teamNowNames" role="region" aria-label={`${openGroup.label}: names`}>
            <span className="team-now-names-title">{openGroup.label}</span>
            {openGroup.list.length
              ? openGroup.list
                .slice()
                .sort((a, b) => String(a.u.name).localeCompare(String(b.u.name)))
                .map(({ u, note }) => (
                  <span key={u.id} className="team-now-name">
                    <UserLink user={u} />{note && <span className="team-now-note"> · {note}</span>}
                  </span>
                ))
              : <span className="muted">Nobody right now</span>}
          </div>
        )}
      </>
    );
  }

  return (
    <div className="card">
      <div className="card-header">
        <div className="card-title">Team right now</div>
        <span className="card-subtitle">Live · on call = a call in the last 15 min</span>
      </div>
      {body}
    </div>
  );
}

const TARGET_VIEWS = [{ value: 'target', label: 'Team target' }, { value: 'recordings', label: 'Recordings' }];

// Team target: calls in the period against the team's daily target × days in the period,
// or (toggle) today's recordings breakdown (viewed / unviewed / non-recorded) + overall & today counts
function TeamTargetCard({ calls, dailyTarget, days, label }) {
  const [view, setView] = useState('target');
  const authUser = useSelector(s => s.auth.authUser);
  const [recStats, setRecStats] = useState({ loaded: false, overall: 0, today: 0, viewed: 0, unviewed: 0 });

  useEffect(() => {
    if (view !== 'recordings') return undefined;
    let live = true;
    const todayStr = istDateStr(new Date());
    const from = istMidnight(todayStr);
    const to = new Date();
    const qsToday = `?limit=500&from=${encodeURIComponent(from.toISOString())}&to=${encodeURIComponent(to.toISOString())}`;

    let viewedIds = new Set();
    try {
      const raw = localStorage.getItem(`rec_viewed_${(authUser && authUser.id) || 'default'}`);
      const arr = raw ? JSON.parse(raw) : [];
      if (Array.isArray(arr)) viewedIds = new Set(arr.map(String));
    } catch { /* ignore */ }

    Promise.all([
      recordingService.list('?limit=1'),
      recordingService.list(qsToday),
    ]).then(([allJson, todayJson]) => {
      if (!live) return;
      const todayRecs = (todayJson && Array.isArray(todayJson.recordings) ? todayJson.recordings : [])
        .map(mapRecording)
        .filter(r => r.id && r.dur > 1);
      const viewed = todayRecs.filter(r =>
        viewedIds.has(String(r.id)) ||
        (r.review && (r.review.status !== 'PENDING' || (r.review.comments && r.review.comments.length > 0))),
      ).length;
      const unviewed = Math.max(0, todayRecs.length - viewed);
      const overall = Number(allJson && allJson.total) || 0;
      const todayTotal = Number(todayJson && todayJson.total) || todayRecs.length;
      setRecStats({ loaded: true, overall, today: todayTotal, viewed, unviewed });
    }).catch(() => {
      if (live) setRecStats(prev => ({ ...prev, loaded: true }));
    });
    return () => { live = false; };
  }, [view, authUser]);

  const target = dailyTarget * days;
  const pct = target > 0 ? Math.round((calls / target) * 100) : 0;
  const left = Math.max(0, target - calls);

  const pieItems = [
    ['Viewed', recStats.viewed, 'var(--ds-ink-900)'],
    ['Unviewed', recStats.unviewed, 'var(--ds-green-500)'],
  ];

  return (
    <div className="card">
      <div className="card-header">
        <div className="card-title">
          {view === 'target' ? 'Team target' : 'Recordings'}
          <span className="card-subtitle" style={{ marginLeft: 8 }}>{view === 'target' ? label : 'TODAY'}</span>
        </div>
        <FilterChips options={TARGET_VIEWS} value={view} onChange={setView} />
      </div>
      {view === 'target' ? (
        <>
          <div className="team-target-figure">
            <strong>{calls}</strong><span> / {target} calls</span>
          </div>
          <Progress lg pct={Math.min(100, pct)} caption={<strong>{pct}%</strong>} />
          <div className="stat-list">
            <div className="stat-row">
              <span>{left > 0 ? 'Still to go' : 'Status'}</span>
              <strong>{left > 0 ? `${left} to go` : 'Target reached'}</strong>
            </div>
            <div className="stat-row">
              <span>Daily team target</span>
              <strong>{dailyTarget}{days > 1 ? ` × ${days} days` : ''}</strong>
            </div>
          </div>
        </>
      ) : (
        <>
          <RecordingsMiniPie items={pieItems} loaded={recStats.loaded} />
          <div className="stat-list" style={{ marginTop: 10 }}>
            <div className="stat-row">
              <span>Overall records</span>
              <strong>{recStats.loaded ? recStats.overall : '—'}</strong>
            </div>
            <div className="stat-row">
              <span>Today records</span>
              <strong>{recStats.loaded ? recStats.today : '—'}</strong>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function RecordingsMiniPie({ items, loaded }) {
  const [hovered, setHovered] = useState(null);
  const total = items.reduce((s, [, n]) => s + n, 0);
  const nonZero = items.filter(([, n]) => n > 0);
  const cx = 70;
  const cy = 70;
  const r = 60;

  let angle = -Math.PI / 2;
  const slices = nonZero.map(([label, n, color]) => {
    const frac = n / total;
    const sweep = frac * Math.PI * 2;
    const start = angle;
    const end = angle + sweep;
    angle = end;
    const x1 = cx + r * Math.cos(start);
    const y1 = cy + r * Math.sin(start);
    const x2 = cx + r * Math.cos(end);
    const y2 = cy + r * Math.sin(end);
    const largeArc = sweep > Math.PI ? 1 : 0;
    return {
      label,
      n,
      color,
      pct: Math.round(frac * 100),
      d: `M ${cx} ${cy} L ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 ${largeArc} 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z`,
    };
  });

  return (
    <div className="funnel-pie-wrap" style={{ gap: 16, padding: '4px 0' }}>
      <svg style={{ width: 136, height: 136 }} className="funnel-pie-svg" viewBox="0 0 140 140" role="img" aria-label="Recordings breakdown pie chart">
        {!loaded || total === 0 ? (
          <circle cx={cx} cy={cy} r={r} fill="var(--ds-surface-muted)" stroke="var(--ds-border)" strokeWidth="2" />
        ) : slices.length === 1 ? (
          <circle
            cx={cx}
            cy={cy}
            r={r}
            fill={slices[0].color}
            stroke="#ffffff"
            strokeWidth="2"
            onMouseEnter={() => setHovered(slices[0].label)}
            onMouseLeave={() => setHovered(null)}
          >
            <title>{`${slices[0].label}: ${slices[0].n} (100%)`}</title>
          </circle>
        ) : (
          slices.map(s => (
            <path
              key={s.label}
              d={s.d}
              fill={s.color}
              stroke="#ffffff"
              strokeWidth="2"
              style={{
                transformOrigin: `${cx}px ${cy}px`,
                transform: hovered === s.label ? 'scale(1.05)' : 'scale(1)',
                opacity: hovered && hovered !== s.label ? 0.65 : 1,
                transition: 'transform 0.2s ease, opacity 0.18s ease',
                cursor: 'pointer',
              }}
              onMouseEnter={() => setHovered(s.label)}
              onMouseLeave={() => setHovered(null)}
            >
              <title>{`${s.label}: ${s.n} (${s.pct}%)`}</title>
            </path>
          ))
        )}
      </svg>
      <div className="funnel-pie-legend" style={{ flex: '1 1 130px', gap: 6 }}>
        {items.map(([label, n, color]) => {
          const pct = total > 0 ? Math.round((n / total) * 100) : 0;
          return (
            <div
              key={label}
              className={`funnel-pie-row${hovered === label ? ' is-active' : ''}`}
              onMouseEnter={() => setHovered(label)}
              onMouseLeave={() => setHovered(null)}
            >
              <span className="funnel-pie-swatch" style={{ background: color }} aria-hidden="true" />
              <span className="funnel-pie-label">{label}</span>
              <span className="funnel-pie-val tabular">{loaded ? n : '—'}</span>
              <span className="funnel-pie-pct tabular">{loaded ? `${pct}%` : ''}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

const HOURLY_VIEWS = [{ value: 'calls', label: 'Calls' }, { value: 'demos', label: 'Demo bookings' }];

// Calls by hour, or (toggle) demo bookings grouped by their creation hour
function HourlyCard({ server, period, customDate }) {
  const [view, setView] = useState('calls');
  const demos = useSelector(s => s.demos);
  const showDemos = view === 'demos';

  useEffect(() => {
    if (showDemos && !demos.loaded && !demos.pending && !demos.error) fetchDemos();
  }, [showDemos, demos.loaded, demos.pending, demos.error]);

  let bars = null;
  let footer = null;
  if (!showDemos) {
    if (server) bars = <HourBars byHour={hourCounts(Array.isArray(server.hourlyAll) ? server.hourlyAll : server.hourlyCalls)} />;
  } else if (demos.loaded) {
    const { start, end } = periodWindow(period, customDate);
    const { byHour, byStatusHour, status } = demoHourCounts(demos.list, start, end);
    bars = <HourBars byHour={byHour} byStatusHour={byStatusHour} unit="demo" />;
    footer = (
      <div className="mix-legend">
        <span><span className="legend-swatch" style={{ background: 'var(--ds-green-400)' }} />Booked · <strong>{status.BOOKED}</strong></span>
        <span><span className="legend-swatch" style={{ background: 'var(--ds-green-700)' }} />Done · <strong>{status.DONE}</strong></span>
        <span><span className="legend-swatch" style={{ background: 'var(--ds-surface-sunken)' }} />Cancelled · <strong>{status.CANCELLED}</strong></span>
      </div>
    );
  } else {
    footer = <EmptyState>{demos.error ? `COULD NOT LOAD DEMO BOOKINGS — ${demos.error}` : 'LOADING DEMO BOOKINGS…'}</EmptyState>;
  }

  return (
    <div className="card">
      <div className="card-header">
        <div className="card-title">{showDemos ? 'Demo bookings by hour' : 'Call activity by hour'}</div>
        <FilterChips options={HOURLY_VIEWS} value={view} onChange={setView} pressed />
      </div>
      <div className="card-subtitle" style={{ marginBottom: 8 }}>
        {showDemos ? `${periodLabel(period, customDate)} · booking created time, cancelled not counted · 10 AM – 7 PM IST` : '10 AM – 7 PM IST'}
      </div>
      <div className="hour-bars">{bars}</div>
      {footer}
    </div>
  );
}

// Team table: the people in the active scope, numbers from the same server response
function TeamPerformance({ server, failed, error, usersError, callers, typeFilter = 'ALL', users, mgrOptions, mgrValue, page, targetDays, onMgr, onPage, onOpen }) {
  let body;
  let pager = { page: 1, totalPages: 1, count: 0 };
  if (!server) {
    body = <EmptyState>{failed ? `COULD NOT LOAD DASHBOARD — ${error || ''}` : 'LOADING LIVE NUMBERS…'}</EmptyState>;
  } else if (!callers.length) {
    body = <EmptyState>{usersError ? `COULD NOT LOAD USERS — ${usersError}` : 'NO TEAM MEMBERS IN THIS VIEW'}</EmptyState>;
  } else {
    // Signed in to the phone app first (green), then everyone else (red); within each group the
    // most connected calls on top, the existing order breaks ties. Re-sorted on every live refresh (20 s).
    const connectedOf = (u) => { const r = statsFor(server.teamMembers, u); return r ? Number(r.connectedCalls) || 0 : 0; };
    const onlineOf = (u) => appPresence(statsFor(server.teamMembers, u)).online;
    const set = mgrFilterSet(users, mgrValue);
    const typeFilteredCallers = typeFilter !== 'ALL'
      ? callers.filter(u => ((u && u.employeeType) || 'sales_team') === typeFilter)
      : callers;
    const ordered = typeFilteredCallers.map((u, i) => ({ u, i, c: connectedOf(u), on: onlineOf(u) }))
      .sort((a, b) => (b.on - a.on) || ((b.c > 0) - (a.c > 0)) || (b.c - a.c) || (a.i - b.i))
      .map(x => x.u)
      .filter(u => !set || set.has(u.id));
    if (!ordered.length) {
      body = <EmptyState>Nobody under this manager in this view</EmptyState>;
    } else {
      const pg = paginate(ordered, page, DASH_TEAM_PAGE_SIZE);
      pager = { page: pg.page, totalPages: pg.totalPages, count: ordered.length };
      body = pg.rows.map(u => {
        const row = statsFor(server.teamMembers, u);
        const uTotal = row ? Number(row.totalCalls) || 0 : 0;
        const uConnected = row ? Number(row.connectedCalls) || 0 : 0;
        const { online } = appPresence(row);
        const statusTitle = presenceTitle(row, uConnected);
        const uTalk = row ? Number(row.talkTimeSeconds) || 0 : 0;
        const logoutTime = row?.loggedOutAt &&
          (!row.lastLoginAt || new Date(row.loggedOutAt) >= new Date(row.lastLoginAt))
          ? row.loggedOutAt
          : null;
        const target = (Number(u.target) || 0) * targetDays;  // daily target × days in the period
        const attain = target > 0 ? Math.round((uTotal / target) * 100) : 0;
        return (
          <TableRow
            cols={TEAM_COLS}
            key={u.id}
            data-open-user={u.id}
            title={`Open ${u.name}'s details`}
            onClick={(e) => { if (!e.target.closest('a, button, input, select, audio')) onOpen(u.id); }}
          >
            <span className="cell-primary" style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              <PresenceDot online={online} label={statusTitle} />
              <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <span className="truncate" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <UserLink user={u} />
                  {row?.autoRecordEnabled === false && (
                    <span
                      title="Call recording is turned OFF on this caller's device"
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        padding: '1px 5px',
                        background: 'var(--ds-red-600, #E02424)',
                        color: '#fff',
                        fontSize: 10,
                        fontWeight: 800,
                        borderRadius: 3,
                        letterSpacing: '0.04em',
                        lineHeight: '14px',
                      }}
                    >
                      REC OFF
                    </span>
                  )}
                </span>
                <span className="cell-sub" style={{ display: 'flex', flexDirection: 'column' }}>
                  <span>LOGIN · {presenceTime(row?.lastLoginAt)}</span>
                  <span>LAST SEEN · {presenceTime(row?.lastSeenAt)}</span>
                  <span>LOGOUT · {presenceTime(logoutTime)}</span>
                </span>
              </span>
            </span>
            <span className="cell-muted" style={{ fontSize: 12, lineHeight: 1.5, overflowWrap: 'anywhere' }} title={managerChainText(users, u)}>
              <ManagerChain user={u} />
            </span>
            <span className="cell-phone-number">{formatPhone(u.phone)}</span>
            <span><CountPill n={uTotal} /></span>
            <span><CountPill n={uConnected} /></span>
            <span className="tabular">{fmtTalk(uTalk)}</span>
            <Progress pct={Math.min(100, attain)} caption={target > 0 ? <>{uTotal}/{target} · <strong>{attain}%</strong></> : 'No target'} />
          </TableRow>
        );
      });
    }
  }

  return (
    <div className="neo-table-card">
      <div className="card-header"><div className="card-title">Team performance</div><div className="pill-group">
          <span className="card-subtitle">Green = signed in to the app · signed-in agents first</span>
          <MgrFilterSelect id="dashMgrFilter" value={mgrValue} options={mgrOptions} onChange={onMgr} />
        </div>
      </div>
      <DataTable
        cols={TEAM_COLS}
        head={<>
          <span>Agent</span>
          <span>Managed by</span>
          <span>Phone / SIM</span><span>Calls</span><span>Connected</span><span>Talk time</span><span>Daily target</span>
        </>}
      >
        {body}
      </DataTable>
      <Pager
        label={`PAGE ${pager.page} / ${pager.totalPages} · ${pager.count} CALLERS`}
        page={pager.page}
        totalPages={pager.totalPages}
        onPage={onPage}
      />
      <p></p>
    </div>
  );
}
