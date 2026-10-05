// ==========================================
// 1. DASHBOARD: server numbers for the period + the team table
// ==========================================
import { useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { useNavigate } from 'react-router-dom';
import { Col, Row } from '../assets/antd';
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
import { DASH_TEAM_PAGE_SIZE, PERIOD_OPTIONS } from '../data/constants';
import { userPath } from '../data/navigation';
import { setDashDate, setDashMgrFilter, setDashPeriod, setDashTeamPage } from '../redux/slices/dashboardSlice';
import { selectDashKey, selectScope } from '../redux/selectors';
import { fmtDur, fmtTalk, fmtTs, formatPhone, validPickerDate } from '../utils/format';
import { notify } from '../utils/notify';
import { paginate } from '../utils/table';
import { periodTargetDays } from '../utils/periods';
import { managerChainText, mgrFilterOptions, mgrFilterSet, statsFor } from '../utils/scope';
import { appPresence, hourCounts, presenceTitle } from '../utils/stats';
import { fetchDashboard } from '../utils/actions/statsActions';

const TEAM_COLS = '1.3fr 1.3fr 1.1fr 0.8fr 0.9fr 0.9fr 1.4fr';

export default function DashboardPage() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const dash = useSelector(s => s.dashboard);
  const key = useSelector(selectDashKey);
  const usersError = useSelector(s => s.users.error);
  const { users, visible, scoped } = useSelector(selectScope);

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
  const m = server ? {
    total: n(server.totalCalls), connected: n(server.connectedCalls), talkSeconds: n(server.talkSeconds),
    incoming: n(server.incoming), outgoing: n(server.outgoing), missed: n(server.missed), rejected: n(server.rejected),
    neverAttended: n(server.neverAttended), uniqueClients: n(server.uniqueClients),
  } : null;
  const rate = m && m.total ? Math.round((m.connected / m.total) * 100) : 0;
  const avgDur = m && m.connected ? Math.round(m.talkSeconds / m.connected) : 0;
  const inPct = m && m.total ? Math.round((m.incoming / m.total) * 100) : 0;
  const dashTxt = (v) => (m ? v : '—');
  const callsTxt = (k) => (m ? `${m[k]} CALL${m[k] === 1 ? '' : 'S'}` : '—');

  return (
    <>
      <PageHeader title="Dashboard" subtitle="Team performance and call metrics" actionsClass="">
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
          <div className="card">
            <div className="card-header"><div className="card-title">Call activity by hour</div><span className="card-subtitle">10 AM – 7 PM IST</span></div>
            <div className="hour-bars">
              {server && <HourBars byHour={hourCounts(Array.isArray(server.hourlyAll) ? server.hourlyAll : server.hourlyCalls)} />}
            </div>
          </div>
        </Col>
      </Row>

      <TeamPerformance
        server={server}
        failed={failed}
        error={dash.error}
        usersError={usersError}
        callers={scoped}
        users={users}
        mgrOptions={mgrOptions}
        mgrValue={mgrValue}
        page={dash.teamPage}
        targetDays={periodTargetDays(dash.period, dash.customDate)}
        onMgr={(v) => dispatch(setDashMgrFilter(v))}
        onPage={(p) => dispatch(setDashTeamPage(p))}
        onOpen={(id) => navigate(userPath(id))}
      />
    </>
  );
}

// Team table: the people in the active scope, numbers from the same server response
function TeamPerformance({ server, failed, error, usersError, callers, users, mgrOptions, mgrValue, page, targetDays, onMgr, onPage, onOpen }) {
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
    const ordered = callers.map((u, i) => ({ u, i, c: connectedOf(u), on: onlineOf(u) }))
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
        const statusTitle = presenceTitle(row, uConnected, fmtTs);
        const uTalk = row ? Number(row.talkTimeSeconds) || 0 : 0;
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
              <PresenceDot online={online} label={statusTitle} /><span className="truncate"><UserLink user={u} /></span>
            </span>
            <span className="cell-muted" style={{ fontSize: 12, lineHeight: 1.5, overflowWrap: 'anywhere' }} title={managerChainText(users, u)}>
              <ManagerChain user={u} />
            </span>
            <span className="cell-mono">{formatPhone(u.phone)}</span>
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
      <div className="card-header"><div className="card-title">Team performance</div><span className="card-subtitle">Green = signed in to the app · signed-in agents first</span></div>
      <DataTable
        cols={TEAM_COLS}
        head={<>
          <span>Agent</span>
          <MgrFilterSelect id="dashMgrFilter" value={mgrValue} options={mgrOptions} onChange={onMgr} />
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
    </div>
  );
}
