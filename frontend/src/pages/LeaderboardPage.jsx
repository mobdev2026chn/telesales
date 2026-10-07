// ==========================================
// 5. LEADERBOARD (server numbers): ranked by connected calls, then talk time
// ==========================================
import { useEffect, useMemo, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button } from '../assets/antd';
import Avatar from '../components/common/Avatar';
import { Badge, CountPill } from '../components/common/Badge';
import DataTable, { TableRow } from '../components/common/DataTable';
import DateField from '../components/common/DateField';
import EmptyState from '../components/common/EmptyState';
import FilterChips from '../components/common/FilterChips';
import Icon from '../components/common/Icon';
import ManagerChain from '../components/common/ManagerChain';
import Pager from '../components/common/Pager';
import MgrFilterSelect from '../components/common/MgrFilterSelect';
import PageHeader from '../components/common/PageHeader';
import Progress from '../components/common/Progress';
import UserLink from '../components/common/UserLink';
import { LEADERBOARD_PAGE_SIZE, PERIOD_OPTIONS } from '../data/constants';
import { setLbDate, setLbMgrFilter, setLbPeriod } from '../redux/slices/leaderboardSlice';
import { selectLbKey, selectScope } from '../redux/selectors';
import { exportRows } from '../utils/excel';
import { fmtTalk, formatPhone, validPickerDate } from '../utils/format';
import { notify } from '../utils/notify';
import { paginate } from '../utils/table';
import { findUserRef, managerChainText, mgrFilterOptions, mgrFilterSet } from '../utils/scope';
import { fetchLeaderboard } from '../utils/actions/statsActions';

const COLS = '0.5fr 1.3fr 1.6fr 1.2fr 0.9fr 1fr 0.9fr 1.3fr';
const MEDALS = [
  { place: '1ST · GOLD', crown: true },
  { place: '2ND · SILVER', crown: false },
  { place: '3RD · BRONZE', crown: false },
];

// Attainment colour: none · low · mid · high · done
function attTone(att) {
  if (att === null) return 'none';
  if (att >= 100) return 'done';
  if (att >= 60) return 'high';
  if (att >= 25) return 'mid';
  return 'low';
}

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
  // Table pages (ranks are worked out on the whole list first; the export still takes every row)
  const [page, setPage] = useState(1);
  useEffect(() => { setPage(1); }, [key, mgrValue]);
  const pager = paginate(shownRows, page, LEADERBOARD_PAGE_SIZE);

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
        <div className={`podium-card podium-${p.label.slice(1)}${p.label === '#1' ? ' is-first' : ''}`} key={p.label}>
          <Badge tone={p.label === '#1' ? 'lime' : 'neutral'}><Icon name="award" size="sm" />{p.place}</Badge>
          <div className="podium-avatar-wrap">
            <Avatar user={refOf(p) || { name: p.name }} className="podium-avatar" />
            <span className="podium-rank">{p.label}</span>
          </div>
          <div className="podium-name">{p.crown && <Icon name="crown" className="podium-crown" />}<UserLink user={{ id: p.id, phone: p.phone, name: p.name }} label={p.name} /></div>
          <div className="podium-stats">
            <div><strong>{p.conn}</strong><span>Connected</span></div>
            <div><strong>{fmtTalk(p.talk)}</strong><span>Talk time</span></div>
          </div>
        </div>
      ));
    if (!rows.length) body = <EmptyState>NO CALLERS IN THIS VIEW</EmptyState>;
    else if (!shownRows.length) body = <EmptyState>Nobody under this manager on the leaderboard</EmptyState>;
    else {
      body = pager.rows.map(s => (
        <TableRow cols={COLS} key={`${s.rank}-${s.id}`} className={`table-body-row lb-row${s.rank <= 3 ? ` is-top is-top-${s.rank}` : ''}`}>
          <span className={`lb-rank${s.rank <= 3 ? ` lb-rank-${s.rank}` : ''}`} aria-label={`Rank ${s.rank}`}>
            {s.rank === 1 ? <Icon name="crown" size="sm" /> : null}{s.rank}
          </span>
          <span className="lb-agent">
            <Avatar user={refOf(s) || { name: s.name }} className="avatar-sm" />
            <span className="cell-primary" style={{ minWidth: 0 }}><UserLink user={{ id: s.id, phone: s.phone, name: s.name }} label={s.name} /></span>
          </span>
          <span className="lb-chain"><ManagerChain user={refOf(s)} /></span>
          <span className="cell-mono lb-phone">{formatPhone(s.phone)}</span>
          <span className="lb-stat"><CountPill n={s.total} /><span className="lb-stat-unit">calls</span></span>
          <span className="lb-stat"><CountPill n={s.conn} /><span className="lb-stat-unit">connected</span></span>
          <span className="lb-talk"><Icon name="clock" size="sm" />{fmtTalk(s.talk)}</span>
          <span className={`lb-att lb-att-${attTone(s.att)}`}>
            <Progress pct={s.att || 0} caption={s.att === null ? 'No target' : <><strong>{s.att}%</strong> · {s.total}/{s.target}</>} />
          </span>
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

      <div className="toolbar">
        <div className="pill-group toolbar-spacer">
          <MgrFilterSelect id="lbMgrFilter" value={mgrValue} options={mgrOptions} onChange={(v) => dispatch(setLbMgrFilter(v))} />
        </div>
      </div>

      <div className="neo-table-card lb-table">
        <DataTable cols={COLS} head={<>
          <span>Rank</span><span>Agent</span>
          <span>Managed by</span>
          <span>Phone / SIM</span><span>Total</span><span>Connected</span><span>Talk time</span><span>Target attainment</span>
        </>}>
          {body}
        </DataTable>
        {shownRows.length > 0 && (
          <Pager label={`PAGE ${pager.page} / ${pager.totalPages} · ${shownRows.length} AGENT${shownRows.length === 1 ? '' : 'S'}`}
            page={pager.page} totalPages={pager.totalPages} onPage={setPage} />
        )}
      </div>
    </>
  );
}
