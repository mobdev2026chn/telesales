// ==========================================
// 4. USER MANAGEMENT: sales agents, managers and who reports to whom
// ==========================================
import { useEffect, useRef, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { useNavigate } from 'react-router-dom';
import { Alert, Button, Input, Segmented, Select } from '../assets/antd';
import ActionIcon from '../components/common/ActionIcon';
import Avatar from '../components/common/Avatar';
import { PresenceDot, RoleBadge } from '../components/common/Badge';
import DataTable, { Heads, TableRow } from '../components/common/DataTable';
import EmptyState from '../components/common/EmptyState';
import Icon from '../components/common/Icon';
import PageHeader from '../components/common/PageHeader';
import PasswordField from '../components/common/PasswordField';
import UserLink from '../components/common/UserLink';
import { DEFAULT_DAILY_TARGET, HEAD_ROLES, ROLE_OPTIONS, TREE_FILTERS } from '../data/constants';
import { PATHS } from '../data/navigation';
import { closeUserForm, setTreeFilter, setUserView, toggleUserForm } from '../redux/slices/uiSlice';
import { selectScope } from '../redux/selectors';
import { fmtTs, formatPhone, last10, roleLabel } from '../utils/format';
import { byRankThenName, isHead, roleRank, statsFor } from '../utils/scope';
import { appPresence, presenceTitle } from '../utils/stats';
import { viewAsUser } from '../utils/actions/syncActions';
import { deleteUser, saveUser } from '../utils/actions/userActions';

const LIST_COLS = '1fr 1.6fr 1.2fr 1fr 1fr 0.9fr 0.8fr 0.8fr 1.4fr';

export default function UserManagementPage() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const scope = useSelector(selectScope);
  const { users, visible, me, isRealAdmin: admin, authId } = scope;
  const usersState = useSelector(s => s.users);
  const { userForm, userView, treeFilter } = useSelector(s => s.ui);
  const today = usersState.todayMembers;

  const viewAs = (uid) => {
    const tab = viewAsUser(uid);
    if (tab) navigate(PATHS[tab]);
  };
  const onDelete = (u) => {
    if (!admin || !u || u.id === authId) return;
    if (!window.confirm(`Delete ${u.name}? This cannot be undone.`)) return;
    deleteUser(u);
  };

  const todayRow = (u) => (today ? statsFor(today, u) : null);
  const connectedToday = (u) => { const s = todayRow(u); return s ? Number(s.connectedCalls) || 0 : 0; };
  const todayCallsText = (u) => {
    if (today === null) return usersState.todayError ? '—' : '…';
    const s = statsFor(today, u);
    return `${s ? Number(s.totalCalls) || 0 : 0}`;
  };

  // ---- User list: signed in to the phone app first (green), then the rest; most connected calls today on top
  let listBody;
  if (!visible.length || (!usersState.loaded && usersState.error)) {
    listBody = <EmptyState>{usersState.error ? `COULD NOT LOAD USERS — ${usersState.error}` : 'LOADING USERS…'}</EmptyState>;
  } else {
    const onlineNow = (u) => u.role !== 'ADMIN' && appPresence(todayRow(u)).online;
    const ordered = visible.map((u, i) => ({ u, i, c: u.role !== 'ADMIN' ? connectedToday(u) : -1, on: onlineNow(u) }))
      .sort((a, b) => (b.on - a.on) || ((b.c > 0) - (a.c > 0)) || (b.c - a.c) || (a.i - b.i))
      .map(x => x.u);
    listBody = ordered.map(u => {
      const mgrUser = users.find(x => x.id === u.mgr);
      const mgrName = mgrUser ? `${mgrUser.name} (${roleLabel(mgrUser.role)})` : '—';
      // Everyone except admins makes calls and is counted on the dashboard / leaderboard
      const isAgent = u.role !== 'ADMIN';
      const canEdit = admin || u.role !== 'ADMIN';
      const canDelete = admin && u.role !== 'ADMIN' && u.id !== authId;
      const canViewAs = admin && u.id !== authId;
      const statsReady = today !== null;
      const uConnected = connectedToday(u);
      const { online } = appPresence(todayRow(u));
      const todayTotal = (() => { const s = todayRow(u); return s ? Number(s.totalCalls) || 0 : 0; })();
      const statusTitle = presenceTitle(todayRow(u), uConnected, fmtTs);
      return (
        <TableRow cols={LIST_COLS} key={u.id}>
          <span className="cell-primary" style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Avatar user={u} className="avatar-sm" /><span style={{ minWidth: 0, overflowWrap: 'anywhere' }}><UserLink user={u} /></span>
          </span>
          <span className="cell-muted" style={{ wordBreak: 'break-all' }}>{u.email || '—'}</span>
          <span className="cell-mono">{formatPhone(u.phone)}</span>
          <span><RoleBadge role={u.role} /></span>
          <span className="cell-muted">{mgrUser ? <UserLink user={mgrUser} label={mgrName} /> : mgrName}</span>
          <span className="tabular">{isAgent ? `${u.target}/day` : '—'}</span>
          <span className="tabular">
            {!isAgent ? '—' : (statsReady
              ? <><span className={`count-pill ${todayTotal > 0 ? 'is-good' : 'is-bad'}`}>{todayTotal}</span> calls</>
              : `${todayCallsText(u)} calls`)}
          </span>
          <span>
            {!isAgent || !statsReady ? <span className="muted">—</span> : (
              <span className={`status-text ${online ? 'text-success' : 'text-danger'}`} title={statusTitle}>
                <PresenceDot online={online} />{online ? 'Signed in' : 'Not signed in'}
              </span>
            )}
          </span>
          <div className="cell-actions">
            {canViewAs && <ActionIcon icon="eye" tone="view" label={`View the portal as ${u.name}`} onClick={() => viewAs(u.id)} />}
            {canEdit && <ActionIcon icon="edit" tone="edit" label={`Edit ${u.name}`} onClick={() => dispatch(toggleUserForm(u.id))} />}
            {canDelete && <ActionIcon icon="delete" tone="delete" label={`Delete ${u.name}`} onClick={() => onDelete(u)} />}
          </div>
        </TableRow>
      );
    });
  }

  // ---- Team tree (by managerId)
  const roots = me.role === 'ADMIN' ? visible.filter(u => u.role === 'ADMIN') : [me];
  const treeRows = [];
  const visited = new Set();
  const walk = (u, depth) => {
    if (!u || visited.has(u.id)) return;
    visited.add(u.id);
    treeRows.push({ u, depth });
    visible.filter(x => x.mgr === u.id).sort(byRankThenName).forEach(k => walk(k, depth + 1));
  };
  roots.forEach(r => walk(r, 0));
  visible.forEach(u => { if (!visited.has(u.id)) walk(u, Math.max(1, roleRank(u.role))); });
  let filteredTree = treeRows;
  if (treeFilter === 'MGR') filteredTree = treeRows.filter(t => HEAD_ROLES.includes(t.u.role));
  else if (treeFilter === 'CALLER') filteredTree = treeRows.filter(t => t.u.role === 'CALLER');

  return (
    <>
      <PageHeader title="User Management" subtitle="Sales agents, managers and who reports to whom">
        <Button type="primary" icon={<Icon name="plus" size="sm" />} onClick={() => dispatch(toggleUserForm())}>Add user</Button>
      </PageHeader>

      <div className="toolbar">
        <Segmented
          value={userView}
          onChange={(v) => dispatch(setUserView(v))}
          options={[
            { value: 'list', label: 'User list', icon: <Icon name="list" size="sm" /> },
            { value: 'tree', label: 'Team hierarchy', icon: <Icon name="layers" size="sm" /> },
          ]}
        />
        {/* Admin-only "view as" quick jump */}
        {admin && (
          <div className="quick-jump-box toolbar-spacer" style={{ display: 'flex' }}>
            <label htmlFor="userQuickJumpSelect">View portal as</label>
            <Select id="userQuickJumpSelect" className="toolbar-ant-select" value="" onChange={(v) => { if (v) viewAs(v); }}
              showSearch optionFilterProp="label" popupMatchSelectWidth={false} suffixIcon={<Icon name="eye" size="sm" />}
              options={[
                { value: '', label: 'SELECT USER TO VIEW AS…' },
                ...users.filter(u => u.id !== authId).map(u => ({ value: u.id, label: `${u.name} (${roleLabel(u.role)})` })),
              ]} />
          </div>
        )}
      </div>

      {userForm.open && <UserForm key={userForm.seq} editingId={userForm.editingId} scope={scope} />}

      {userView === 'list' && (
        <div style={{ marginBottom: 'var(--ds-space-5)' }}>
          <div className="neo-table-card users-table">
            <DataTable cols={LIST_COLS} head={<Heads labels={['Name', 'Login email', 'Phone / SIM', 'Role', 'Manager', 'Target', 'Today', 'Status', 'Actions']} />}>
              {listBody}
            </DataTable>
            <div className="table-pager">
              <span className="pager-label">{visible.length} TEAM MEMBER{visible.length === 1 ? '' : 'S'} TOTAL</span>
            </div>
          </div>
        </div>
      )}

      {userView === 'tree' && (
        <div className="neo-table-card" style={{ marginBottom: 'var(--ds-space-5)' }}>
          <div className="card-header">
            <div>
              <div className="card-title">Reporting tree</div>
              <div className="card-subtitle">Admin → managers → junior managers → team leaders → callers</div>
            </div>
            <Segmented value={treeFilter} onChange={(v) => dispatch(setTreeFilter(v))} options={TREE_FILTERS} />
          </div>
          <div style={{ padding: 'var(--ds-space-5)' }}>
            {!filteredTree.length ? <EmptyState>NO USERS MATCH THIS FILTER</EmptyState> : filteredTree.map(({ u, depth }) => (
              <div className="tree-node" style={{ marginLeft: Math.min(depth * 28, 140) }} key={u.id}>
                {depth > 0
                  ? <span className="tree-branch" aria-hidden="true">↳</span>
                  : <span className="kpi-icon" style={{ width: 26, height: 26 }} aria-hidden="true"><Icon name="award" size="sm" /></span>}
                <Avatar user={u} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <strong><UserLink user={u} /></strong>
                    <RoleBadge role={u.role} />
                    <span className="muted" style={{ fontSize: 'var(--ds-fs-xs)' }}>{todayCallsText(u)} dials today</span>
                  </div>
                  <div className="cell-sub" style={{ wordBreak: 'break-word' }}>{u.email || '—'} · {formatPhone(u.phone)} · Target: {u.target || 0}/day</div>
                </div>
                {admin && u.id !== authId && <ActionIcon icon="eye" tone="view" label={`View the portal as ${u.name}`} onClick={() => viewAs(u.id)} />}
              </div>
            ))}
          </div>
        </div>
      )}
    </>
  );
}

// Add / Edit form
function UserForm({ editingId, scope }) {
  const dispatch = useDispatch();
  const { users, visible, me, isRealAdmin: admin, realRole } = scope;
  const editUser = editingId ? users.find(x => x.id === editingId) : null;
  // Managers this person may report to (only an admin may pick "top level")
  const mgrChoices = visible.filter(u => u.id !== editingId && isHead(u)).sort(byRankThenName);
  const firstMgr = admin ? '' : (mgrChoices[0] ? mgrChoices[0].id : '');

  const [form, setForm] = useState(() => (editUser ? {
    name: editUser.name, email: editUser.email, phone: editUser.phone || '', password: '',
    role: editUser.role, mgr: editUser.mgr || firstMgr, target: String(editUser.target),
  } : {
    name: '', email: '', phone: '', password: '', role: 'CALLER',
    mgr: (me.role !== 'ADMIN' && mgrChoices.some(m => m.id === me.id)) ? me.id : firstMgr,
    target: String(DEFAULT_DAILY_TARGET),
  }));
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const nameRef = useRef(null);
  const set = (k) => (v) => setForm(f => ({ ...f, [k]: v }));
  const ev = (k) => (e) => set(k)(e.target.value);

  useEffect(() => {
    const t = setTimeout(() => { try { nameRef.current.focus(); } catch { /* ignore */ } }, 50);
    return () => clearTimeout(t);
  }, []);

  const save = async () => {
    const name = form.name.trim();
    const email = form.email.trim();
    const phone = form.phone.trim();
    const { password, role, mgr } = form;
    const rawTarget = form.target.trim();
    const target = rawTarget === '' ? (role === 'CALLER' ? DEFAULT_DAILY_TARGET : 0) : Number(rawTarget);

    setError('');
    if (!name) return setError('Name is required.');
    if (!last10(phone)) return setError('A valid 10-digit phone number is required.');
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return setError('Enter a valid email address or leave it blank.');
    if (!editingId && password.length < 6) return setError('Set a password of at least 6 characters.');
    if (editingId && password && password.length < 6) return setError('New password must be at least 6 characters.');
    if (!Number.isFinite(target) || target < 0 || target > 1000) return setError('Target must be a number between 0 and 1000.');
    if (role === 'ADMIN' && !admin) return setError('Only an admin can create or promote an admin.');

    const mgrUser = users.find(x => x.id === mgr);
    const payload = {
      name,
      email,
      phone,
      role: role.toLowerCase(),
      dailyTarget: Math.round(target),
      managerId: mgr || '',
      managerName: mgrUser ? mgrUser.name : '',
    };
    if (password) payload.password = password;
    if (!editingId) payload.team = (mgrUser && mgrUser.team) || me.team || 'Telesales Team';

    setBusy(true);
    const res = await saveUser(editingId, payload);
    setBusy(false);
    if (res.ok) dispatch(closeUserForm());
    else setError(res.error);
    return undefined;
  };

  const roleDisabled = (value) => (value === 'ADMIN' && !admin) || (value === 'MANAGER' && !(admin || realRole === 'MANAGER'));

  return (
    <div className="card" style={{ marginBottom: 'var(--ds-space-4)', animation: 'fadeUp 0.25s ease both' }}>
      <div className="card-header"><div className="card-title">{editUser ? `EDIT ${editUser.name.toUpperCase()}` : 'ADD NEW TEAM MEMBER'}</div></div>
      <div className="user-form-grid">
        <div>
          <label className="user-form-label" htmlFor="fUserName">Name *</label>
          <Input id="fUserName" ref={nameRef} placeholder="Full name" autoComplete="off" value={form.name} onChange={ev('name')} />
        </div>
        <div>
          <label className="user-form-label" htmlFor="fUserEmail">Login email</label>
          <Input type="email" id="fUserEmail" placeholder="name@company.com" autoComplete="off" value={form.email} onChange={ev('email')} />
        </div>
        <div>
          <label className="user-form-label" htmlFor="fUserPhone">Phone / SIM *</label>
          <Input type="tel" id="fUserPhone" placeholder="10-digit mobile" autoComplete="off" value={form.phone} onChange={ev('phone')} />
        </div>
        <div>
          <label className="user-form-label" htmlFor="fUserPassword">Password *</label>
          <PasswordField id="fUserPassword" autoComplete="new-password" value={form.password} onChange={set('password')}
            placeholder={editUser ? 'Leave blank to keep current password' : 'Min 6 characters'} />
        </div>
        <div>
          <label className="user-form-label" htmlFor="fUserRole">Role</label>
          <Select id="fUserRole" className="form-ant-select" value={form.role} onChange={set('role')}
            options={ROLE_OPTIONS.map(o => ({ ...o, disabled: roleDisabled(o.value) }))} />
        </div>
        <div>
          <label className="user-form-label" htmlFor="fUserMgr">Reports to</label>
          <Select id="fUserMgr" className="form-ant-select" value={form.mgr} onChange={set('mgr')}
            showSearch optionFilterProp="label" popupMatchSelectWidth={false}
            options={[
              ...(admin ? [{ value: '', label: 'TOP LEVEL / ADMIN' }] : []),
              ...mgrChoices.map(m => ({ value: m.id, label: `${m.name.toUpperCase()} (${roleLabel(m.role)})` })),
            ]} />
        </div>
        <div>
          <label className="user-form-label" htmlFor="fUserTarget">Target / day</label>
          <Input type="number" id="fUserTarget" min="0" max="1000" step="1" value={form.target} onChange={ev('target')} />
        </div>
        <Button type="primary" icon={<Icon name="save" size="sm" />} onClick={save} loading={busy}>{busy ? 'Saving…' : 'Save user'}</Button>
      </div>
      {error && <Alert className="form-alert" type="error" showIcon role="alert" title={error} />}
    </div>
  );
}
