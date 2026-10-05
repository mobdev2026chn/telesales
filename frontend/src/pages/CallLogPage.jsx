// ==========================================
// 2. CALL LOG: every SIM-tracked call from the team's phones
// ==========================================
import { useEffect, useMemo, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button, Select } from '../assets/antd';
import ActionIcon from '../components/common/ActionIcon';
import { DirBadge, OutcomeBadge } from '../components/common/Badge';
import DataTable, { Heads, TableRow } from '../components/common/DataTable';
import EmptyState from '../components/common/EmptyState';
import FilterChips, { Chip } from '../components/common/FilterChips';
import Icon from '../components/common/Icon';
import PageHeader from '../components/common/PageHeader';
import Pager from '../components/common/Pager';
import PlayButton from '../components/common/PlayButton';
import SearchField from '../components/common/SearchField';
import UserLink from '../components/common/UserLink';
import {
  CALL_DIR_FILTERS, CALL_PAGE_SIZE, CALL_RANGE_LABEL, CALL_RANGE_OPTIONS,
} from '../data/constants';
import { callsScopeReset, setCallAgent, setCallFilter, setCallPage, setCallSearch } from '../redux/slices/callsSlice';
import { openLeadForm } from '../redux/slices/uiSlice';
import { selectScope } from '../redux/selectors';
import { playCallAudioDirect, setPlaylist } from '../utils/audioController';
import { exportRows } from '../utils/excel';
import { fmtDur, fmtIstFull, fmtTalk, fmtTs, formatPhone, istDateStr, last10, roleLabel } from '../utils/format';
import { leadPhoneSet } from '../utils/leads';
import { notify } from '../utils/notify';
import { paginate } from '../utils/table';
import { recIdForCall } from '../utils/recordings';
import { callBelongsTo } from '../utils/scope';
import { changeCallRange, fetchCalls } from '../utils/actions/callActions';

const COLS = '1fr 1.5fr 1.3fr 0.9fr 0.9fr 0.7fr 1.1fr 0.5fr 0.6fr';

function filterCalls(list, { filter, agent, search }, users) {
  // The server already returned only calls in the active scope
  let fc = list.slice();
  if (filter === 'IN') fc = fc.filter(c => c.dir === 'IN');
  if (filter === 'OUT') fc = fc.filter(c => c.dir === 'OUT');
  if (filter === 'MISSED') fc = fc.filter(c => c.out === 'MISSED');
  if (filter === 'NO ANSWER') fc = fc.filter(c => c.out === 'NO ANSWER');
  if (agent !== 'ALL') {
    const su = users.find(u => u.id === agent);
    fc = su ? fc.filter(c => callBelongsTo(c, su)) : [];
  }
  const q = search.trim().toLowerCase();
  if (q) {
    const qDigits = q.replace(/\D/g, '');
    fc = fc.filter(c =>
      (c.client || '').toLowerCase().includes(q) ||
      (qDigits && String(c.phone).replace(/\D/g, '').includes(qDigits)) ||
      (c.agent || '').toLowerCase().includes(q) ||
      (c.out || '').toLowerCase().includes(q));
  }
  return fc;
}

export default function CallLogPage() {
  const dispatch = useDispatch();
  const calls = useSelector(s => s.calls);
  const recordings = useSelector(s => s.recordings.list);
  const leads = useSelector(s => s.leads.list);
  const { users, scoped, scopeParam } = useSelector(selectScope);
  const [searchText, setSearchText] = useState(calls.search);

  // The chosen agent left the view: back to all agents
  const agentValue = calls.agent !== 'ALL' && !scoped.some(u => u.id === calls.agent) ? 'ALL' : calls.agent;
  useEffect(() => {
    if (agentValue !== calls.agent) dispatch(setCallAgent('ALL'));
  }, [agentValue, calls.agent, dispatch]);

  // "View as" changed since these calls were loaded: reload them for the new scope
  useEffect(() => {
    if (calls.loaded && calls.scopeKey !== scopeParam) {
      dispatch(callsScopeReset());
      fetchCalls(false);
    }
  }, [calls.loaded, calls.scopeKey, scopeParam, dispatch]);

  const fc = useMemo(
    () => filterCalls(calls.list, { filter: calls.filter, agent: agentValue, search: calls.search }, users),
    [calls.list, calls.filter, agentValue, calls.search, users],
  );

  // Prev / Next in the docked player walk through every playable call in this filtered list
  const playIds = useMemo(() => {
    const seen = new Set();
    return fc.map(c => recIdForCall(recordings, c)).filter(id => id && !seen.has(id) && seen.add(id));
  }, [fc, recordings]);
  useEffect(() => { setPlaylist('log', playIds); }, [playIds]);

  const pg = paginate(fc, calls.page, CALL_PAGE_SIZE);

  // Unfiltered: the server's count for the period (counted like the dashboard). Filtered: the matching rows.
  const unfiltered = calls.filter === 'ALL' && agentValue === 'ALL' && !calls.search.trim();
  const shownCount = unfiltered ? Math.max(calls.meta.total || 0, fc.length) : fc.length;
  const rangeTxt = CALL_RANGE_LABEL[calls.range] || '';
  const moreTxt = calls.meta.hasMore ? ` · ${calls.list.length} LOADED` : '';
  // Talk time of exactly the calls listed (follows the agent / search / type filters)
  const talkSec = fc.reduce((sum, c) => sum + (c.dur > 0 ? c.dur : 0), 0);
  const knownLeadPhones = useMemo(() => leadPhoneSet(leads), [leads]);

  const onTyping = (val) => { setSearchText(val); dispatch(setCallSearch(val)); };
  const doSearch = () => {
    const q = searchText.trim();
    dispatch(setCallSearch(q));
    notify(`FILTERED BY: "${q || 'ALL'}"`);
  };
  const clearSearch = () => { setSearchText(''); dispatch(setCallSearch('')); };

  const [loadingOlder, setLoadingOlder] = useState(false);
  const loadOlder = async () => {
    setLoadingOlder(true);
    await fetchCalls(true);
    setLoadingOlder(false);
  };

  const addLeadFromCall = (c) => {
    dispatch(openLeadForm({ name: '', phone: c.phone, agentId: c.callerId, notes: `From ${c.dir === 'IN' ? 'inbound' : 'outbound'} call on ${fmtTs(c.ts)}` }));
  };

  const exportCallLog = () => {
    const rows = fc.map(c => ({
      Agent: c.agent,
      Client: c.client || '',
      Phone: c.phone,
      Direction: c.dir === 'IN' ? 'Inbound' : 'Outbound',
      Outcome: c.out,
      'Duration (s)': c.dur,
      'Date / Time (IST)': fmtIstFull(c.ts),
      SIM: c.sim,
      Recording: recIdForCall(recordings, c) ? 'Yes' : 'No',
    }));
    exportRows(rows, 'Call Log', `call-log-${istDateStr(new Date())}.xlsx`);
  };

  let body;
  if (pg.rows.length === 0) {
    let msg = 'NO CALLS MATCH THESE FILTERS.';
    if (calls.error) msg = `COULD NOT LOAD CALLS — ${calls.error}`;
    else if (!calls.loaded) msg = 'LOADING CALLS…';
    body = <EmptyState>{msg}</EmptyState>;
  } else {
    body = (
      <>
        {calls.error && <EmptyState error style={{ padding: 12 }}>SHOWING LAST LOADED DATA — REFRESH FAILED: {calls.error}</EmptyState>}
        {pg.rows.map(c => {
          const clientText = c.client || 'Unknown caller';
          const p10 = last10(c.phone);
          const showAddLead = !c.client && p10 && !knownLeadPhones.has(p10);
          const playId = recIdForCall(recordings, c);
          return (
            <TableRow cols={COLS} key={c.id}>
              <span className="cell-primary"><UserLink user={{ id: c.callerId, phone: c.callerPhone, name: c.agent }} label={c.agent} /></span>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <span className={c.client ? 'fw-600' : 'cell-unknown'}>{clientText}</span>
                {showAddLead && (
                  <ActionIcon icon="plus" tone="add" label="Add this caller as a lead" onClick={() => addLeadFromCall(c)} />
                )}
              </div>
              <span className="cell-mono">{formatPhone(c.phone)}</span>
              <DirBadge dir={c.dir} />
              <OutcomeBadge out={c.out} />
              <span className="tabular">{c.dur ? fmtDur(c.dur) : '—'}</span>
              <span className="cell-muted">{fmtTs(c.ts)}</span>
              <span className="cell-muted">SIM {c.sim}</span>
              <span>
                {playId ? (
                  <PlayButton onClick={() => playCallAudioDirect(playId, 'log')} label={`Play recording of call with ${clientText}`} />
                ) : <span className="muted">—</span>}
              </span>
            </TableRow>
          );
        })}
      </>
    );
  }

  return (
    <>
      <PageHeader title="Call Log" subtitle="Every SIM-tracked call from the team's phones">
        <SearchField id="callSearchInput" label="Search calls" placeholder="Search agent, client, phone…"
          value={searchText} onChange={onTyping} onEnter={doSearch} onClear={clearSearch} />
        <Button className="btn-ink" icon={<Icon name="search" size="sm" />} onClick={doSearch}>Search</Button>
        <Button icon={<Icon name="download" size="sm" />} onClick={exportCallLog} title="Export the filtered call log to Excel">Export</Button>
      </PageHeader>

      <div className="toolbar">
        <FilterChips id="callDirChips" options={CALL_DIR_FILTERS} value={calls.filter} onChange={(v) => dispatch(setCallFilter(v))} />
        <div className="pill-group toolbar-spacer">
          <label htmlFor="callRangeSelect" className="visually-hidden">Date range</label>
          <Select id="callRangeSelect" className="toolbar-ant-select" value={calls.range} onChange={(v) => changeCallRange(v)}
            options={CALL_RANGE_OPTIONS} suffixIcon={<Icon name="calendar" size="sm" />} />
          <label htmlFor="callAgentFilter" className="visually-hidden">Agent</label>
          <Select id="callAgentFilter" className="toolbar-ant-select" value={agentValue} onChange={(v) => dispatch(setCallAgent(v))}
            showSearch optionFilterProp="label" popupMatchSelectWidth={false}
            options={[{ value: 'ALL', label: 'ALL AGENTS' }, ...scoped.map(u => ({ value: u.id, label: `${u.name.toUpperCase()} (${roleLabel(u.role)})` }))]} />
        </div>
      </div>

      <div className="neo-table-card">
        <DataTable cols={COLS} head={<Heads labels={['Agent', 'Client', 'Phone', 'Type', 'Outcome', 'Duration', 'Date · time', 'SIM', 'Rec']} />}>
          {body}
        </DataTable>
        <Pager
          live
          label={`PAGE ${pg.page} / ${pg.totalPages} · ${shownCount} CALLS ${rangeTxt} · ${fmtTalk(talkSec)} TALK TIME${moreTxt}`}
          page={pg.page}
          totalPages={pg.totalPages}
          onPage={(p) => dispatch(setCallPage(p))}
        >
          {calls.meta.hasMore && (
            <Chip loading={loadingOlder} icon={<Icon name="history" size="sm" />} onClick={loadOlder}>{loadingOlder ? 'Loading…' : 'Load older'}</Chip>
          )}
        </Pager>
      </div>
    </>
  );
}
