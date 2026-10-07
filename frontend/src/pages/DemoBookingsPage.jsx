// ==========================================
// DEMO BOOKINGS (booked by callers in the app; slots can be blocked here)
// ==========================================
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useDispatch, useSelector } from 'react-redux';
import { Button, Tooltip } from '../assets/antd';
import { Badge } from '../components/common/Badge';
import DataTable, { Heads, TableRow } from '../components/common/DataTable';
import DateField from '../components/common/DateField';
import EmptyState from '../components/common/EmptyState';
import { Chip } from '../components/common/FilterChips';
import Icon from '../components/common/Icon';
import PageHeader from '../components/common/PageHeader';
import UserLink from '../components/common/UserLink';
import { DEMO_SLOTS } from '../data/constants';
import { setDemoDay, setDemoTl } from '../redux/slices/demosSlice';
import { selectScope } from '../redux/selectors';
import {
  dayDemos, demoDayStr, demoEndMs, demoSlotLabel, demoSlotStart, demoSlotState, fmtDemoDay, tlDemos,
} from '../utils/demos';
import { onKeyActivate } from '../utils/dom';
import { exportRows } from '../utils/excel';
import { fmtLongDay, fmtTs, formatPhone, istDateStr, istMidnight } from '../utils/format';
import { blockDemoSlot, cancelDemoBooking, fetchDemos, rescheduleDemoBooking, unblockDemoSlot } from '../utils/actions/demoActions';

const COLS = '1.25fr 1.15fr 1.05fr 0.95fr 1fr 1fr 1.5fr 0.95fr';

export default function DemoBookingsPage() {
  const dispatch = useDispatch();
  const ds = useSelector(s => s.demos);
  const { visible } = useSelector(selectScope);
  const [menu, setMenu] = useState(null);   // { m, rect }
  const closeMenu = useCallback(() => setMenu(null), []);
  // Demos being sent back to reschedule: they fade out before the list reloads without them
  const [fading, setFading] = useState(() => new Set());
  const fadeOut = useCallback((id, on) => setFading(prev => {
    const next = new Set(prev);
    if (on) next.add(id); else next.delete(id);
    return next;
  }), []);

  useEffect(() => {
    if (!ds.loaded && !ds.pending && !ds.error) fetchDemos();
  }, [ds.loaded, ds.pending, ds.error, dispatch]);

  // Team leader chips: every team leader in view plus any named on a booking
  const tls = new Map();
  visible.filter(u => u.role === 'TEAM_LEADER').forEach(u => tls.set(u.id, u.name));
  ds.list.forEach(d => { if (d.teamLeaderId && !tls.has(d.teamLeaderId)) tls.set(d.teamLeaderId, d.teamLeaderName || '—'); });
  const tl = ds.tl && ds.tl !== 'ALL' && !tls.has(ds.tl) ? 'ALL' : (ds.tl || 'ALL');
  useEffect(() => {
    if (tl !== ds.tl) dispatch(setDemoTl('ALL'));
  }, [tl, ds.tl, dispatch]);

  const day = demoDayStr(ds.day);
  const list = dayDemos(ds.list, tl, ds.day);

  const changeDay = (val) => { setMenu(null); dispatch(setDemoDay(val)); };
  const shiftDay = (delta) => {
    const d = new Date(istMidnight(day).getTime() + delta * 24 * 60 * 60 * 1000 + 12 * 60 * 60 * 1000);
    changeDay(istDateStr(d));
  };
  const openMenu = (e, m) => {
    e.stopPropagation();
    setMenu({ m, rect: e.currentTarget.getBoundingClientRect() });
  };

  const exportDemos = () => {
    exportRows(list.map(d => ({
      'Demo date': fmtDemoDay(d.at),
      'Time slot': d.slot,
      Client: d.clientName,
      Phone: d.clientPhone,
      Course: d.course,
      'Team leader': d.teamLeaderName,
      Agent: d.agent,
      Notes: d.reason,
      'Booked on': d.bookedAt ? fmtTs(d.bookedAt) : '',
    })), 'Demo bookings', `demo-bookings-${day}.xlsx`);
  };

  let body;
  if (!ds.loaded) {
    body = <EmptyState>{ds.error ? `COULD NOT LOAD DEMO BOOKINGS — ${ds.error}` : 'LOADING DEMO BOOKINGS…'}</EmptyState>;
  } else if (!list.length) {
    body = <EmptyState>No demo bookings on this day</EmptyState>;
  } else {
    body = list.map(d => {
      const isPast = demoEndMs(d) < Date.now();
      return (
        <TableRow cols={COLS} key={d.id} style={{ opacity: fading.has(d.id) ? 0 : (isPast ? 0.7 : 1), transition: 'opacity .35s ease' }}>
          <div style={{ minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 4 }}>
            <span className="cell-primary" style={{ fontSize: 13 }}>{fmtDemoDay(d.at)}</span>
            <Badge tone={isPast ? 'neutral' : 'lime'}>{d.slot || fmtTs(d.at)}</Badge>
          </div>
          <span className="cell-primary" style={{ overflowWrap: 'anywhere' }}>{d.clientName || '—'}</span>
          <span className="cell-mono">{d.clientPhone ? formatPhone(d.clientPhone) : '—'}</span>
          <span style={{ overflowWrap: 'anywhere' }}>{d.course || '—'}</span>
          <span>{d.teamLeaderName ? <UserLink user={{ id: d.teamLeaderId, name: d.teamLeaderName }} label={d.teamLeaderName} /> : <span className="muted">—</span>}</span>
          <span>{d.agent ? <UserLink user={{ id: d.callerId, name: d.agent }} label={d.agent} /> : '—'}</span>
          <span className="cell-muted" style={{ overflowWrap: 'anywhere', whiteSpace: 'pre-line' }}>{d.reason || '—'}</span>
          <span className="cell-muted">{d.bookedAt ? fmtTs(d.bookedAt) : '—'}</span>
        </TableRow>
      );
    });
  }

  return (
    <>
      <PageHeader title="Demo Bookings" subtitle={`${list.length} demo booking${list.length === 1 ? '' : 's'} in this view`}>
        <Button className="btn-ink" icon={<Icon name="download" size="sm" />} onClick={exportDemos} title="Export the listed demo bookings to Excel">Export</Button>
      </PageHeader>

      <div className="demo-tl-row">
        <span className="demo-tl-label">Team leader</span>
        <div className="pill-group">
          {[['ALL', 'All'], ...Array.from(tls.entries()).sort((a, b) => String(a[1]).localeCompare(String(b[1])))].map(([id, name]) => (
            <Chip key={id} active={tl === id} icon={id === 'ALL' ? <Icon name="users" size="sm" /> : <Icon name="user" size="sm" />} onClick={() => { setMenu(null); dispatch(setDemoTl(id)); }}>{name}</Chip>
          ))}
        </div>
      </div>

      <div className="demo-slot-card">
        <div className="demo-slot-head">
          <div className="demo-day-nav">
            <Tooltip title="Previous day">
              <Button shape="circle" size="small" icon={<Icon name="left" size="sm" />} onClick={() => shiftDay(-1)} aria-label="Previous day" />
            </Tooltip>
            <strong>{fmtLongDay(istMidnight(day))}</strong>
            <Tooltip title="Next day">
              <Button shape="circle" size="small" icon={<Icon name="right" size="sm" />} onClick={() => shiftDay(1)} aria-label="Next day" />
            </Tooltip>
            <Chip active={day === istDateStr(new Date())} icon={<Icon name="calendar" size="sm" />} onClick={() => changeDay(null)}>Today</Chip>
            <DateField id="demoDayInput" value={day} onChange={changeDay} label="Pick a date" allowClear={false} placement="bottomLeft" />
          </div>
          <span className="demo-slot-hint">10:00 AM – 7:00 PM · 30-min slots</span>
        </div>
        <div className="demo-slot-grid">
          {DEMO_SLOTS.map(m => {
            const st = demoSlotState(ds.list, ds.blocks, tl, ds.day, m);
            const live = st.bookings.filter(d => !fading.has(d.id));
            let cls = 'demo-slot';
            let sub = '';
            if (st.blocks.length) {
              cls += ' is-blocked';
              sub = `Blocked${tl === 'ALL' ? ` · ${st.blocks[0].teamLeaderName || 'All'}` : ''}`;
            } else if (live.length) {
              cls += ' is-booked';
              sub = live[0].clientName || '—';
              if (live.length > 1) sub += ` +${live.length - 1}`;
            } else if (st.bookings.length) {
              cls += ' is-fading';
              sub = st.bookings[0].clientName || '—';
            }
            if (st.past) cls += ' is-past';
            return (
              <div key={m} className={cls} role="button" tabIndex={0} onClick={(e) => openMenu(e, m)} onKeyDown={onKeyActivate((e) => openMenu(e, m))}>
                <button type="button" className="demo-slot-act" title="Slot actions" aria-label="Slot actions" onClick={(e) => openMenu(e, m)}><Icon name="ellipsis" /></button>
                <span className="demo-slot-time">{demoSlotLabel(m)}</span>
                {sub && <span className="demo-slot-sub">{sub}</span>}
              </div>
            );
          })}
        </div>
        <div className="demo-slot-legend">
          <span><i className="lg-free" />Free</span><span><i className="lg-booked" />Booked</span><span><i className="lg-blocked" />Blocked</span>
          <span className="muted">Use <Icon name="ellipsis" size="sm" /> on a slot to block or unblock it. Blocked slots show red in the callers&apos; app.</span>
        </div>
      </div>

      <div className="neo-table-card">
        <DataTable cols={COLS} head={<Heads labels={['Demo date · slot', 'Client', 'Phone', 'Course', 'Team leader', 'Agent', 'Notes', 'Booked on']} />}>
          {body}
        </DataTable>
      </div>

      {menu && <SlotMenu menu={menu} tl={tl} visible={visible} onClose={closeMenu} onFade={fadeOut} />}
    </>
  );
}

// Slot action menu (⋯): block / unblock a slot, or cancel / reschedule the demo booked in it
function SlotMenu({ menu, tl, visible, onClose, onFade }) {
  const ds = useSelector(s => s.demos);
  const ref = useRef(null);
  const [pos, setPos] = useState({ left: 0, top: 0, ready: false });
  const { m, rect } = menu;
  const st = demoSlotState(ds.list, ds.blocks, tl, ds.day, m);
  const tlName = tl && tl !== 'ALL'
    ? ((visible.find(u => u.id === tl) || {}).name || (tlDemos(ds.list, tl)[0] || {}).teamLeaderName || 'this team leader')
    : 'all team leaders';

  // Below the slot, or above it when there is no room
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const w = el.offsetWidth;
    const h = el.offsetHeight;
    const left = Math.max(8, Math.min(rect.right - w, window.innerWidth - w - 8));
    const top = rect.bottom + 6 + h > window.innerHeight ? Math.max(8, rect.top - h - 6) : rect.bottom + 6;
    setPos({ left: left + window.scrollX, top: top + window.scrollY, ready: true });
  }, [rect]);

  // Any click elsewhere or Escape closes it
  useEffect(() => {
    const close = () => onClose();
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('click', close);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('click', close);
      document.removeEventListener('keydown', onKey);
    };
  }, [onClose]);

  const act = (run) => { onClose(); run(); };
  const cancel = (id) => {
    if (!window.confirm('Cancel this demo booking? The slot becomes free again.')) return;
    act(() => cancelDemoBooking(id));
  };
  // Sends the demo back to the caller who booked it: the slot becomes free and they book a new one in the app
  const reschedule = (d) => {
    if (!window.confirm(`Send this demo back to ${d.agent || 'the caller'} to reschedule? The slot becomes free and they book a new slot in the app.`)) return;
    act(() => {
      onFade(d.id, true);
      setTimeout(() => rescheduleDemoBooking(d.id).finally(() => onFade(d.id, false)), 350);
    });
  };

  return createPortal(
    <div ref={ref} className="demo-slot-menu" onClick={(e) => e.stopPropagation()}
      style={{ left: pos.left, top: pos.top, visibility: pos.ready ? 'visible' : 'hidden' }}>
      <div className="demo-menu-head">{fmtDemoDay(demoSlotStart(ds.day, m))} · {demoSlotLabel(m)}</div>
      {st.past && <p className="demo-menu-note">This slot has passed.</p>}
      {st.bookings.map(d => (
        <div className="demo-menu-item" key={d.id}>
          <strong>{d.clientName || '—'}</strong>
          <span>{[d.clientPhone ? formatPhone(d.clientPhone) : '', d.teamLeaderName, d.agent ? `by ${d.agent}` : ''].filter(Boolean).join(' · ')}</span>
          {!st.past && (
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              <Button size="small" icon={<Icon name="missed" size="sm" />} onClick={() => cancel(d.id)}>Cancel demo</Button>
              <Button size="small" icon={<Icon name="clock" size="sm" />} onClick={() => reschedule(d)}>Reschedule</Button>
            </div>
          )}
        </div>
      ))}
      {st.blocks.map(b => (
        <div className="demo-menu-item is-blocked" key={b.id}>
          <strong>Blocked · {b.teamLeaderName || 'All team leaders'}</strong>
          <span>{b.blockedByName ? `by ${b.blockedByName}` : ''}</span>
          <Button size="small" icon={<Icon name="check" size="sm" />} onClick={() => act(() => unblockDemoSlot(b.id))}>Unblock slot</Button>
        </div>
      ))}
      {!st.past && !st.blocks.length && !st.bookings.length && (
        <>
          <p className="demo-menu-note">Free slot. Blocking it stops callers booking it for {tlName}.</p>
          <Button type="primary" danger icon={<Icon name="slash" size="sm" />}
            onClick={() => act(() => blockDemoSlot(tl !== 'ALL' ? tl : '', demoSlotStart(ds.day, m), demoSlotLabel(m)))}>Block slot</Button>
        </>
      )}
    </div>,
    document.body,
  );
}
