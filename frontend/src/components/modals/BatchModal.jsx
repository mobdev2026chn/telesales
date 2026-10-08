// UPLOADED FILE DETAILS (Lead Calling · Upload history): every lead in one file, and the manager's
// split of its unassigned leads among their callers
import { useMemo, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button, Input } from '../../assets/antd';
import { HEAD_ROLES, STAGE_CLASS, STATUS_TO_STAGE } from '../../data/constants';
import { closeBatch } from '../../redux/slices/uiSlice';
import { selectScope, selectScopedLeads } from '../../redux/selectors';
import { exportRows } from '../../utils/excel';
import { fmtIstFull, fmtTs, formatPhone, last10 } from '../../utils/format';
import { dialActivityText, isFreshLead, leadAgentName, leadLabel, leadMatches } from '../../utils/leads';
import { notify } from '../../utils/notify';
import { descendantsOf, isDialable } from '../../utils/scope';
import { Badge, LeadBadge } from '../common/Badge';
import DataTable, { Heads, TableRow } from '../common/DataTable';
import EmptyState from '../common/EmptyState';
import Icon from '../common/Icon';
import SearchField from '../common/SearchField';
import UserLink from '../common/UserLink';
import { distributeBatch } from '../../utils/actions/leadActions';

const COLS = '1.4fr 1.1fr 1fr 1fr 1.3fr 1.3fr';

// The file's leads in view; a file still waiting in history shows its sheet rows merged with the server copy
function batchLeads(scopedLeads, pending, batchName) {
  const fromDb = scopedLeads.filter(l => l.batchName === batchName);
  if (!pending || pending.fileName !== batchName) return fromDb;
  const byPhone = new Map(fromDb.map(l => [last10(l.phone), l]));
  return (pending.rows || []).filter(r => last10(r.phone)).map((r, index) => {
    const db = byPhone.get(last10(r.phone)) || {};
    return {
      ...db,
      id: `pending_${index}`,
      name: r.name || db.name || '',
      phone: r.phone || '',
      status: db.status || 'new',
      attempts: db.attempts || 0,
      agentId: db.agentId || pending.assignedCallerId || pending.targetCallerId || '',
      agent: db.agent || pending.assignedCallerName || '',
      managerId: db.managerId || pending.managerId || '',
      managerName: db.managerName || pending.managerName || '',
      notes: r.notes || db.notes || '',
      batchName: pending.fileName,
      source: 'pending-upload',
      lastCallDate: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
  });
}

// The manager who owns most of the file's leads
function batchOwnerId(leads) {
  const counts = {};
  leads.forEach(l => { if (l.managerId) counts[l.managerId] = (counts[l.managerId] || 0) + 1; });
  return Object.keys(counts).sort((a, b) => counts[b] - counts[a])[0] || '';
}

export default function BatchModal() {
  const dispatch = useDispatch();
  const batchName = useSelector(s => s.ui.batchOpen);
  const pending = useSelector(s => s.leads.pendingUpload);
  const scopedLeads = useSelector(selectScopedLeads);
  const { users, me, visibleIds, dialable } = useSelector(selectScope);
  const [search, setSearch] = useState('');
  const [split, setSplit] = useState({});
  const [splitMsg, setSplitMsg] = useState('');
  const [splitting, setSplitting] = useState(false);

  const leads = useMemo(() => batchLeads(scopedLeads, pending, batchName), [scopedLeads, pending, batchName]);
  const unassigned = leads.filter(l => !l.agentId && isFreshLead(l)).length;
  const ownerId = batchOwnerId(leads);
  const owner = ownerId ? users.find(u => u.id === ownerId) : null;
  // Callers who can receive this file's leads: the owning manager's team (everyone dialable when no owner)
  const callers = (ownerId ? descendantsOf(users, ownerId) : dialable)
    .filter(u => isDialable(u) && visibleIds.has(u.id))
    .sort((a, b) => a.name.localeCompare(b.name));

  const close = () => dispatch(closeBatch());
  const splitOf = (id) => Number((!unassigned && !splitMsg ? {} : split)[id]) || 0;
  const allocated = callers.reduce((s, u) => s + splitOf(u.id), 0);
  const over = allocated > unassigned;

  const uploaded = leads.reduce((min, l) => (l.createdAt && (!min || l.createdAt < min) ? l.createdAt : min), null);
  const count = (fn) => leads.filter(fn).length;
  const chips = [
    ['TOTAL', leads.length, 'badge badge-dark'],
    ['NOT DIALED', count(isFreshLead), 'badge badge-outline'],
    ['DIALED', count(l => !isFreshLead(l)), 'badge badge-success'],
    ['INTERESTED', count(l => STATUS_TO_STAGE[l.status] === 'INTERESTED'), `badge ${STAGE_CLASS['INTERESTED']}`],
    ['FOLLOW-UP', count(l => STATUS_TO_STAGE[l.status] === 'FOLLOW-UP'), `badge ${STAGE_CLASS['FOLLOW-UP']}`],
    ['CONVERTED', count(l => STATUS_TO_STAGE[l.status] === 'CONVERTED'), `badge ${STAGE_CLASS['CONVERTED']}`],
    ['NOT INTERESTED', count(l => STATUS_TO_STAGE[l.status] === 'NOT INTERESTED'), `badge ${STAGE_CLASS['NOT INTERESTED']}`],
  ];

  const byAgent = {};
  leads.forEach(l => { const a = leadAgentName(users, l); byAgent[a] = (byAgent[a] || 0) + 1; });
  const agentEntries = Object.entries(byAgent).sort((a, b) => b[1] - a[1]);

  const q = search.trim().toLowerCase();
  const list = leads.filter(l => leadMatches(users, l, q)).sort((a, b) => a.name.localeCompare(b.name));

  const splitEvenly = () => {
    if (!callers.length) return;
    const base = Math.floor(unassigned / callers.length);
    let extra = unassigned % callers.length;
    const next = {};
    callers.forEach(u => { next[u.id] = base + (extra-- > 0 ? 1 : 0); });
    setSplit(next);
    setSplitMsg('');
  };

  const assignSplit = async () => {
    if (unassigned === 0) {
      setSplit({});
      setSplitMsg('✓ THIS FILE IS ALREADY ASSIGNED TO ITS CALLER(S)');
      return;
    }
    const allocations = callers.map(u => ({ callerId: u.id, count: Math.max(0, Math.floor(Number(split[u.id]) || 0)) })).filter(a => a.count > 0);
    const total = allocations.reduce((s, a) => s + a.count, 0);
    if (!total) { notify('ENTER HOW MANY LEADS EACH CALLER SHOULD GET'); return; }
    if (total > unassigned) { notify(`ONLY ${unassigned} UNASSIGNED LEADS LEFT — REDUCE THE NUMBERS`); return; }
    setSplitting(true);
    const res = await distributeBatch(batchName, allocations);
    setSplitting(false);
    if (res.ok) {
      setSplit({});
      setSplitMsg(res.message);
    }
  };

  const exportLeads = () => {
    const rows = leads.map(l => ({
      Lead: l.name,
      Phone: l.phone,
      Agent: leadAgentName(users, l),
      Status: leadLabel(l),
      Dials: l.attempts || 0,
      'Last call (IST)': l.lastCallDate ? fmtIstFull(l.lastCallDate) : '',
      Notes: l.notes || '',
      File: l.batchName,
    }));
    const safe = String(batchName || 'upload').replace(/\.[^.]+$/, '').replace(/[^A-Za-z0-9_-]+/g, '_');
    exportRows(rows, 'Leads', `${safe}-leads.xlsx`);
  };

  const showSplit = HEAD_ROLES.includes(me.role) && (unassigned > 0 || !!splitMsg);

  return (
    <div id="batchModal" className="modal-overlay active" role="dialog" aria-modal="true" aria-labelledby="batchModalTitle"
      onClick={(e) => { if (e.target === e.currentTarget) close(); }}>
      <div className="modal-card" style={{ width: 960, maxWidth: 'calc(100vw - 32px)', maxHeight: '88vh' }}>
        <div className="modal-header">
          <div style={{ minWidth: 0 }}>
            <div className="modal-eyebrow">Uploaded file details</div>
            <div id="batchModalTitle" className="modal-title" style={{ marginTop: 2 }}>{batchName}</div>
            <div className="muted" style={{ fontSize: 'var(--ds-fs-sm)', marginTop: 2 }}>
              UPLOADED {uploaded ? fmtTs(uploaded) : '—'} · {leads.length} LEAD{leads.length === 1 ? '' : 'S'}
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
            <Button size="small" icon={<Icon name="download" size="sm" />} onClick={exportLeads} title="Export this file's leads to Excel">Export</Button>
            <Button type="text" size="small" icon={<Icon name="x" size="sm" />} onClick={close} aria-label="Close file details">Close</Button>
          </div>
        </div>

        <div className="pill-group" style={{ marginBottom: 12 }}>
          {chips.map(([label, n, cls]) => <span key={label} className={`${cls} badge-lg`}>{label} · {n}</span>)}
        </div>
        <div className="text-2" style={{ fontSize: 'var(--ds-fs-sm)', marginBottom: 12, lineHeight: 1.6 }}>
          {agentEntries.length > 0 && <>Assigned to: {agentEntries.map(([a, n], i) => (
            <span key={a}>{i > 0 && ' · '}<strong style={{ color: 'var(--ds-text)' }}>{a}</strong> {n}</span>
          ))}</>}
        </div>

        {showSplit && (
          <div className="split-panel">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10, flexWrap: 'wrap', marginBottom: 10 }}>
              <span className="card-title" style={{ fontSize: 'var(--ds-fs-base)' }}>
                Split leads to callers{owner && <span className="card-subtitle"> · {owner.name}&apos;s team</span>}
              </span>
              <Badge tone={unassigned ? 'warning' : 'success'}>{unassigned} UNASSIGNED LEAD{unassigned === 1 ? '' : 'S'} LEFT</Badge>
            </div>
            {splitMsg && <div className="text-success fw-600" style={{ fontSize: 'var(--ds-fs-sm)', marginBottom: 10 }}>{splitMsg}</div>}
            {unassigned > 0 && (!callers.length ? (
              <EmptyState>{owner ? `${owner.name.toUpperCase()} HAS NO CALLERS YET — ADD THEM IN USER MANAGEMENT` : 'NO CALLERS IN YOUR VIEW'}</EmptyState>
            ) : (
              <>
                <div className="split-grid">
                  {callers.map(u => {
                    const has = leads.filter(l => l.agentId === u.id);
                    return (
                      <label className="split-item" key={u.id}>
                        <span style={{ minWidth: 0 }}>
                          <strong className="truncate" style={{ display: 'block' }}>{u.name}</strong>
                          <span className="muted" style={{ fontSize: 'var(--ds-fs-xs)' }}>Has {has.length} · {has.filter(l => !isFreshLead(l)).length} called</span>
                        </span>
                        <Input type="number" className="split-input" min="0" max={unassigned} step="1" inputMode="numeric"
                          value={splitOf(u.id) || ''} placeholder="0" aria-label={`Leads to give ${u.name}`}
                          onChange={(e) => setSplit(prev => ({ ...prev, [u.id]: Math.max(0, Math.floor(Number(e.target.value) || 0)) }))} />
                      </label>
                    );
                  })}
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginTop: 12 }}>
                  <span className="fw-600 tabular" style={{ fontSize: 'var(--ds-fs-sm)', color: over ? 'var(--ds-danger)' : 'var(--ds-text)' }}>
                    ALLOCATED {allocated} / {unassigned}{over ? ' · MORE THAN AVAILABLE' : ''}
                  </span>
                  <Button size="small" style={{ marginLeft: 'auto' }} icon={<Icon name="users" size="sm" />} onClick={splitEvenly}>Split evenly</Button>
                  <Button type="text" size="small" icon={<Icon name="x" size="sm" />} onClick={() => { setSplit({}); setSplitMsg(''); }}>Clear</Button>
                  <Button type="primary" size="small" loading={splitting} icon={<Icon name="check-plain" size="sm" />} onClick={assignSplit}>{splitting ? 'Assigning…' : 'Assign'}</Button>
                </div>
              </>
            ))}
          </div>
        )}

        <SearchField id="batchSearchInput" label="Search this file's leads" placeholder="Search lead, phone or agent…"
          style={{ maxWidth: 'none', marginBottom: 12 }} value={search} onChange={setSearch} />
        <div className="neo-table-card">
          <DataTable cols={COLS} head={<Heads labels={['Lead', 'Phone', 'Agent', 'Status', 'Dial activity', 'Notes']} />}>
            {list.length ? list.map(l => {
              const fresh = isFreshLead(l);
              const agentName = leadAgentName(users, l);
              return (
                <TableRow cols={COLS} key={l.id}>
                  <span className="cell-primary">{l.name}</span>
                  <span className="cell-mono phone-number">{last10(l.phone) ? formatPhone(l.phone) : <Badge tone="danger">NO PHONE</Badge>}</span>
                  <span><UserLink user={{ id: l.agentId, name: agentName }} label={agentName} /></span>
                  <LeadBadge lead={l} />
                  <span className={fresh ? 'cell-muted' : 'text-success fw-600'} style={{ fontSize: 'var(--ds-fs-sm)' }}>{dialActivityText(l, fmtTs)}</span>
                  <span className="cell-muted" style={{ overflowWrap: 'anywhere' }}>{l.notes || '—'}</span>
                </TableRow>
              );
            }) : <EmptyState>{leads.length ? 'NO LEADS MATCH THIS SEARCH' : 'NO LEADS FROM THIS FILE IN YOUR VIEW'}</EmptyState>}
          </DataTable>
        </div>
      </div>
    </div>
  );
}
