// ==========================================
// PHONE HEALTH: is every agent's phone recording calls? (server numbers per agent)
// Admins, managers, junior managers and team leaders only (RoleRoute guard="health")
// ==========================================
import { useEffect, useRef } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button, Select } from '../assets/antd';
import { Badge, PresenceDot } from '../components/common/Badge';
import DataTable, { Heads, TableRow } from '../components/common/DataTable';
import EmptyState from '../components/common/EmptyState';
import FilterChips from '../components/common/FilterChips';
import { KpiGrid } from '../components/common/Kpi';
import PageHeader from '../components/common/PageHeader';
import Progress from '../components/common/Progress';
import UserLink from '../components/common/UserLink';
import { LEADERBOARD_TYPE_OPTIONS } from '../data/constants';
import { selectPhKey } from '../redux/selectors';
import { setPhDays, setPhTypeFilter } from '../redux/slices/phoneHealthSlice';
import { fmtTs, formatPhone, roleLabel, timeAgo } from '../utils/format';
import { fetchPhoneHealth } from '../utils/actions/phoneHealthActions';

const COLS = '1.5fr 1.15fr 1.1fr 0.95fr 1.3fr 1.7fr';
const OLD_APP_COLS = '1.4fr 1.2fr 1.2fr 0.6fr';
const DAY_OPTIONS = [
  { value: 1, label: 'Today' },
  { value: 7, label: 'Last 7 days' },
  { value: 30, label: 'Last 30 days' },
];

// Server status → order in the table, pill colour, recorded-bar colour
const STATUS = {
  problem: { rank: 0, tone: 'danger', label: 'Problem', bar: 'var(--ds-danger-dot)' },
  warning: { rank: 1, tone: 'warning', label: 'Warning', bar: 'var(--ds-warning-dot)' },
  ok: { rank: 2, tone: 'success', label: 'OK' },
};
const statusOf = (a) => STATUS[a.status] || { rank: 3, tone: 'neutral', label: a.status ? String(a.status) : 'Unknown' };
const num = (v) => Number(v) || 0;
const pctOf = (v) => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Math.round(Number(v)));

// Problems first, then warnings, then OK; within each the lowest recorded share first, then by name
function sortAgents(agents) {
  const pctKey = (a) => { const p = pctOf(a.recordedPercent); return p === null ? 101 : p; };
  return agents.slice().sort((a, b) =>
    (statusOf(a).rank - statusOf(b).rank) ||
    (pctKey(a) - pctKey(b)) ||
    String(a.name || '').localeCompare(String(b.name || '')));
}

export default function PhoneHealthPage() {
  const dispatch = useDispatch();
  const ph = useSelector(s => s.phoneHealth);
  const key = useSelector(selectPhKey);

  const data = ph.data && ph.dataKey === key ? ph.data : null;
  const failed = ph.errorKey === key;
  const pending = ph.pendingKey === key;

  // Fresh numbers each time the page opens and when the period / type / scope changes; the last
  // numbers for the same request stay on screen while they load
  const fetchedKey = useRef(null);
  useEffect(() => {
    if (fetchedKey.current === key) return;
    fetchedKey.current = key;
    fetchPhoneHealth();
  }, [key]);

  const agents = data ? data.agents : [];
  const counts = { problem: 0, warning: 0, ok: 0 };
  agents.forEach(a => { if (counts[a.status] !== undefined) counts[a.status] += 1; });
  const connected = agents.reduce((s, a) => s + num(a.connectedCalls), 0);
  const recorded = agents.reduce((s, a) => s + num(a.recordedCalls), 0);
  const overall = connected > 0 ? Math.round((recorded / connected) * 100) : null;
  const waitMeta = failed ? 'Could not load' : 'Loading…';
  const val = (v) => (data ? v : '—');

  let body;
  if (!data) {
    body = <EmptyState error={failed}>{failed ? `COULD NOT LOAD PHONE HEALTH — ${ph.error || ''}` : 'LOADING PHONE HEALTH…'}</EmptyState>;
  } else if (!agents.length) {
    body = <EmptyState>NO AGENTS IN THIS VIEW</EmptyState>;
  } else {
    body = sortAgents(agents).map((a, i) => <AgentRow key={a.id || `${a.phone || a.name || 'agent'}-${i}`} a={a} />);
  }

  return (
    <>
      <PageHeader title="Phone health" subtitle="Is every agent's phone recording calls?">
        <label htmlFor="phTypeFilter" className="visually-hidden">Filter by type</label>
        <Select
          id="phTypeFilter"
          className="toolbar-ant-select"
          value={ph.typeFilter || 'ALL'}
          options={LEADERBOARD_TYPE_OPTIONS}
          onChange={(v) => dispatch(setPhTypeFilter(v))}
          style={{ width: 175 }}
        />
        <FilterChips options={DAY_OPTIONS} value={ph.days} onChange={(d) => dispatch(setPhDays(d))} />
        <Button onClick={() => fetchPhoneHealth()} loading={pending} title="Load the latest numbers">Refresh</Button>
      </PageHeader>

      <KpiGrid items={[
        {
          label: 'Problems',
          value: val(counts.problem),
          meta: data ? (counts.problem ? 'Agents to fix first' : 'No agent has a problem') : waitMeta,
          tone: data && counts.problem ? 'danger' : '',
        },
        {
          label: 'Warnings',
          value: val(counts.warning),
          meta: data ? (counts.warning ? 'Agents to keep an eye on' : 'No warnings') : waitMeta,
          tone: data && counts.warning ? 'warning' : '',
        },
        { label: 'OK', value: val(counts.ok), meta: data ? 'Recording normally' : waitMeta, tone: 'success' },
        {
          label: 'Calls recorded',
          value: data && overall !== null ? `${overall}%` : '—',
          meta: data ? (connected ? `${recorded} of ${connected} connected calls` : 'No connected calls in this period') : waitMeta,
          tone: 'dark',
          title: 'Connected calls (10 s or more talk time) that have a recording',
        },
      ]} />

      <div className="neo-table-card">
        <div className="card-header">
          <div className="card-title">Agents</div>
          <span className="card-subtitle">
            Problems first, then warnings, then OK{data && data.since ? ` · since ${fmtTs(data.since)}` : ''}
            {data && failed && <span className="ph-alert"> · Could not refresh — {ph.error}</span>}
          </span>
        </div>
        <DataTable
          cols={COLS}
          head={<Heads labels={['Agent', 'Recorded', 'Recordings', 'Last recording', 'Phone', 'Status']} />}
        >
          {body}
        </DataTable>
      </div>

      {data && data.oldAppClients && <OldAppClients clients={data.oldAppClients} graceOn={data.legacyGraceEnabled} />}
    </>
  );
}

function AgentRow({ a }) {
  const st = statusOf(a);
  const pct = pctOf(a.recordedPercent);
  const lost = num(a.issues && a.issues.lost);
  const dev = a.device && typeof a.device === 'object' ? a.device : null;
  const reasons = Array.isArray(a.statusReasons) ? a.statusReasons.filter(Boolean) : [];
  const who = [a.role ? roleLabel(String(a.role).toUpperCase()) : '', a.managerName ? `Manager: ${a.managerName}` : (a.team || '')]
    .filter(Boolean).join(' · ');
  const presence = a.online
    ? 'Signed in to the app'
    : `Not signed in to the app${a.lastSeenAt ? ` · last seen ${fmtTs(a.lastSeenAt)}` : ''}`;

  return (
    <TableRow cols={COLS}>
      <span className="cell-primary" style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
        <PresenceDot online={!!a.online} label={presence} />
        <span style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
            <UserLink user={{ id: a.id, name: a.name, phone: a.phone }} />
            {a.autoRecordEnabled === false && <Badge tone="danger" title="Call recording is turned OFF in the app on this phone">Rec off</Badge>}
          </span>
          <span className="cell-sub">{formatPhone(a.phone)}</span>
          {who && <span className="cell-sub">{who}</span>}
        </span>
      </span>

      <span>
        {pct === null
          ? <><span className="muted">—</span><span className="cell-sub">No connected calls</span></>
          : <Progress pct={pct} color={st.bar} caption={<><strong>{pct}%</strong> · {num(a.recordedCalls)}/{num(a.connectedCalls)}</>} />}
      </span>

      <span>
        <strong className="tabular">{num(a.recordings)}</strong>
        <span className="cell-sub" title="Phone recorder: the phone's own call recorder (both voices). Mic only: AskEVA's microphone (the customer's voice may be missing).">
          Phone recorder {num(a.phoneRecorder)} · Mic only {num(a.micOnly)}
        </span>
        {lost > 0 && <span className="cell-sub ph-alert">{lost} {lost === 1 ? 'call' : 'calls'} not recorded</span>}
      </span>

      <span>
        {a.lastRecordingAt
          ? <><span className="cell-date-time">{timeAgo(a.lastRecordingAt) || '—'}</span><span className="cell-sub">{fmtTs(a.lastRecordingAt)}</span></>
          : <span className="muted">None in this period</span>}
      </span>

      <span style={{ minWidth: 0 }}>
        {dev ? (
          <>
            <span className="cell-primary" style={{ display: 'block' }}>{dev.phone || 'Unknown phone'}</span>
            <span className="cell-sub">
              {[dev.android && `Android ${dev.android}`, dev.appVersion && `App ${dev.appVersion}`].filter(Boolean).join(' · ') || '—'}
            </span>
            <span className="cell-sub">
              {dev.dialer ? `Dialer: ${dev.dialer} · ` : ''}{dev.reportedAt ? `reported ${timeAgo(dev.reportedAt)}` : ''}
            </span>
            {dev.accessibilityEnabled === false && <span className="cell-sub ph-alert">Accessibility off</span>}
          </>
        ) : <span className="muted">No report yet</span>}
        {a.oldAppSeenAt && (
          <span style={{ display: 'block', marginTop: 4 }}>
            <Badge tone="warning" title={`Used the server without logging in (an old app build) · last ${fmtTs(a.oldAppSeenAt)}`}>Old app</Badge>
          </span>
        )}
      </span>

      <span>
        <Badge tone={st.tone} dot>{st.label}</Badge>
        {reasons.length > 0 && (
          <ul className="ph-reasons">
            {reasons.map((r, i) => <li key={i}>{r}</li>)}
          </ul>
        )}
      </span>
    </TableRow>
  );
}

// Admins only (the server leaves the list out for everyone else)
function OldAppClients({ clients, graceOn }) {
  return (
    <div className="neo-table-card ph-section">
      <div className="card-header">
        <div className="card-title">Phones still on an old app (no login)</div>
        {graceOn !== null && (
          <Badge tone={graceOn ? 'warning' : 'neutral'} title="LEGACY_CLIENT_GRACE on the server">
            Old-app access {graceOn ? 'on' : 'off'}
          </Badge>
        )}
      </div>
      <p className="ph-note">
        {graceOn === false
          ? 'The server’s old-app access (LEGACY_CLIENT_GRACE) is already switched off.'
          : 'When this list stays empty, the server’s old-app access (LEGACY_CLIENT_GRACE) can be switched off.'}
      </p>
      {clients.length ? (
        <DataTable cols={OLD_APP_COLS} head={<Heads labels={['Name', 'Phone', 'Last seen', 'Requests']} />}>
          {clients.map((c, i) => (
            <TableRow cols={OLD_APP_COLS} key={`${c.phone || ''}-${c.name || ''}-${i}`}>
              <span className="cell-primary">{c.name ? <UserLink user={{ name: c.name, phone: c.phone }} /> : '—'}</span>
              <span className="cell-phone-number">{formatPhone(c.phone)}</span>
              <span>
                <span className="cell-date-time">{fmtTs(c.lastSeenAt)}</span>
                {c.lastSeenAt && <span className="cell-sub">{timeAgo(c.lastSeenAt)}</span>}
              </span>
              <span className="tabular">{num(c.requests)}</span>
            </TableRow>
          ))}
        </DataTable>
      ) : <EmptyState>No phone used the old app in this period</EmptyState>}
    </div>
  );
}
