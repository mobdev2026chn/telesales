// ==========================================
// 5. LEADERBOARD (server numbers): ranked by connected calls, then talk time
// ==========================================
import { useEffect, useMemo } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button } from '../assets/antd';
import { Badge, CountPill } from '../components/common/Badge';
import DataTable, { TableRow } from '../components/common/DataTable';
import DateField from '../components/common/DateField';
import EmptyState from '../components/common/EmptyState';
import FilterChips from '../components/common/FilterChips';
import Icon from '../components/common/Icon';
import ManagerChain from '../components/common/ManagerChain';
import MgrFilterSelect from '../components/common/MgrFilterSelect';
import PageHeader from '../components/common/PageHeader';
import Progress from '../components/common/Progress';
import UserLink from '../components/common/UserLink';
import { PERIOD_OPTIONS } from '../data/constants';
import { setLbDate, setLbMgrFilter, setLbPeriod } from '../redux/slices/leaderboardSlice';
import { selectLbKey, selectScope } from '../redux/selectors';
import { exportRows } from '../utils/excel';
import { fmtTalk, formatPhone, validPickerDate } from '../utils/format';
import { notify } from '../utils/notify';
import { findUserRef, managerChainText, mgrFilterOptions, mgrFilterSet } from '../utils/scope';
import { fetchLeaderboard } from '../utils/actions/statsActions';

const COLS = '0.5fr 1.3fr 1.6fr 1.2fr 0.9fr 1fr 0.9fr 1.3fr';
const MEDALS = [
  { place: '1ST · GOLD', crown: true },
  { place: '2ND · SILVER', crown: false },
  { place: '3RD · BRONZE', crown: false },
];

// Places are decided by connected calls (then talk time, then total calls), recomputed on every live refresh
function rankRows(data) {
  const n = (v) => Number(v) || 0;
  return data.slice().sort((a, b) =>
    (n(b.connectedCalls) - n(a.connectedCalls)) ||
    (n(b.talkTimeSeconds) - n(a.talkTimeSeconds)) ||
    (n(b.totalCalls) - n(a.totalCalls)) ||
    String(a.name || '').localeCompare(String(b.name || ''))
  ).map((e, i) => {
    const total = n(e.totalCalls);
    const target = n(e.dailyTarget);
    return {
      rank: i + 1,
      id: e.id ? String(e.id) : '',
      name: e.name || '—',
      phone: e.phone || '',
      total,
      conn: n(e.connectedCalls),
      talk: n(e.talkTimeSeconds),
      target,
      att: target > 0 ? Math.min(100, Math.round(total / target * 100)) : null,
    };
  });
}

export default function LeaderboardPage() {
  const dispatch = useDispatch();
  const lb = useSelector(s => s.leaderboard);
  const key = useSelector(selectLbKey);
  const { users, visible } = useSelector(selectScope);

  const data = lb.dataKey === key ? lb.data : null;
  useEffect(() => {
    if (!data && lb.pendingKey !== key && lb.errorKey !== key) fetchLeaderboard();
  }, [data, key, lb.pendingKey, lb.errorKey, dispatch]);

  const mgrOptions = mgrFilterOptions(users, visible);
  const mgrValue = mgrOptions.some(o => o.value === lb.mgrFilter) ? lb.mgrFilter : 'ALL';
  useEffect(() => {
    if (data && mgrValue !== lb.mgrFilter) dispatch(setLbMgrFilter('ALL'));
  }, [data, mgrValue, lb.mgrFilter, dispatch]);

  const rows = useMemo(() => (data ? rankRows(data) : []), [data]);
  const refOf = (s) => findUserRef(users, { id: s.id, phone: s.phone, name: s.name });
  const lbSet = mgrFilterSet(users, mgrValue);
  const shownRows = lbSet ? rows.filter(s => { const u = refOf(s); return u && lbSet.has(u.id); }) : rows;

  const onDate = (val) => {
    if (!val) { dispatch(setLbDate(null)); return; }
    if (!validPickerDate(val)) {
      notify('PLEASE SELECT A VALID YEAR (2020 - 2030)');
      dispatch(setLbDate(null));
      return;
    }
    dispatch(setLbDate(val));
  };

  const exportLeaderboard = () => {
    const period = lb.customDate || lb.period;
    exportRows(shownRows.map(s => ({
      Rank: s.rank,
      Agent: s.name,
      'Managed by': managerChainText(users, refOf(s)),
      Phone: s.phone,
      'Total calls': s.total,
      Connected: s.conn,
      'Talk time (s)': s.talk,
      'Daily target': s.target,
      'Attainment %': s.att === null ? '' : s.att,
    })), 'Leaderboard', `leaderboard-${period}.xlsx`);
  };

  // Podium: #2 · #1 · #3
  const top = rows.slice(0, 3);
  const podium = [];
  if (top[1]) podium.push({ ...top[1], ...MEDALS[1], label: '#2' });
  if (top[0]) podium.push({ ...top[0], ...MEDALS[0], label: '#1' });
  if (top[2]) podium.push({ ...top[2], ...MEDALS[2], label: '#3' });

  let podiumEl = null;
  let body;
  if (!data) {
    const failed = lb.errorKey === key;
    body = <EmptyState>{failed ? `COULD NOT LOAD LEADERBOARD — ${lb.error || ''}` : 'LOADING LEADERBOARD…'}</EmptyState>;
  } else {
    podiumEl = (!rows.length || rows.every(s => s.total === 0))
      ? <div className="card" style={{ width: '100%' }}><EmptyState>NO CALL ACTIVITY RECORDED FOR THIS TIMEFRAME</EmptyState></div>
      : podium.map(p => (
        <div className={`podium-card${p.label === '#1' ? ' is-first' : ''}`} key={p.label}>
          <Badge tone={p.label === '#1' ? 'lime' : 'neutral'}><Icon name="award" size="sm" />{p.place}</Badge>
          <div className="podium-rank">{p.label}</div>
          <div className="podium-name">{p.crown && <Icon name="crown" className="podium-crown" />}<UserLink user={{ id: p.id, phone: p.phone, name: p.name }} label={p.name} /></div>
          <div className="podium-meta">{p.conn} connected · {fmtTalk(p.talk)}</div>
        </div>
      ));
    if (!rows.length) body = <EmptyState>NO CALLERS IN THIS VIEW</EmptyState>;
    else if (!shownRows.length) body = <EmptyState>Nobody under this manager on the leaderboard</EmptyState>;
    else {
      body = shownRows.map(s => (
        <TableRow cols={COLS} key={`${s.rank}-${s.id}`}>
          <span className="rank-num">#{s.rank}</span>
          <span className="cell-primary"><UserLink user={{ id: s.id, phone: s.phone, name: s.name }} label={s.name} /></span>
          <span className="cell-muted" style={{ fontSize: 12, lineHeight: 1.5, overflowWrap: 'anywhere' }}><ManagerChain user={refOf(s)} /></span>
          <span className="cell-mono">{formatPhone(s.phone)}</span>
          <span><CountPill n={s.total} /> <span className="muted">calls</span></span>
          <span><CountPill n={s.conn} /> <span className="muted">connected</span></span>
          <span className="tabular">{fmtTalk(s.talk)}</span>
          <Progress pct={s.att || 0} caption={s.att === null ? 'No target' : `${s.total}/${s.target} (${s.att}%)`} />
        </TableRow>
      ));
    }
  }

  return (
    <>
      <PageHeader title="Leaderboard" subtitle="Ranked by connected calls, then talk time">
        <FilterChips id="lbPeriodChips" options={PERIOD_OPTIONS} value={lb.customDate ? null : lb.period} onChange={(p) => dispatch(setLbPeriod(p))}>
          <DateField id="lbDateInput" value={lb.customDate} onChange={onDate} label="Leaderboard date" title="Filter leaderboard by date (2020-2030)" />
        </FilterChips>
        <Button icon={<Icon name="download" size="sm" />} onClick={exportLeaderboard} title="Export the leaderboard to Excel">Export</Button>
      </PageHeader>

      <div id="leaderboardPodium">{podiumEl}</div>

      <div className="neo-table-card">
        <DataTable cols={COLS} head={<>
          <span>Rank</span><span>Agent</span>
          <MgrFilterSelect id="lbMgrFilter" value={mgrValue} options={mgrOptions} onChange={(v) => dispatch(setLbMgrFilter(v))} />
          <span>Phone / SIM</span><span>Total</span><span>Connected</span><span>Talk time</span><span>Target attainment</span>
        </>}>
          {body}
        </DataTable>
      </div>
    </>
  );
}
