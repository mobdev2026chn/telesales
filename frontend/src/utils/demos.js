// Demo booking slot helpers (selected day is "YYYY-MM-DD", India time)
import { DEMO_SLOT_MIN } from '../data/constants';
import { istDateStr, istMidnight } from './format';

export function demoDayStr(day) { return day || istDateStr(new Date()); }

export function demoSlotStart(day, m) { return new Date(istMidnight(demoDayStr(day)).getTime() + m * 60000); }

export function fmtDemoClock(m) {
  const h = Math.floor(m / 60) % 24;
  return `${h % 12 || 12}:${String(m % 60).padStart(2, '0')} ${h >= 12 ? 'PM' : 'AM'}`;
}

export function demoSlotLabel(m) { return `${fmtDemoClock(m)}-${fmtDemoClock(m + DEMO_SLOT_MIN)}`; }

export function fmtDemoDay(d) {
  if (!d) return '—';
  return new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }).format(d).toUpperCase();
}

export const demoEndMs = d => d.at.getTime() + d.durationMinutes * 60000;

export function overlapsSlot(day, d, m) {
  const s = demoSlotStart(day, m).getTime();
  return d.at && d.at.getTime() < s + DEMO_SLOT_MIN * 60000 && demoEndMs(d) > s;
}

// Live bookings for the chosen Team Leader (or all)
export function tlDemos(demos, tl) {
  let list = (demos || []).filter(d => d.status === 'BOOKED' && d.at);
  if (tl && tl !== 'ALL') list = list.filter(d => d.teamLeaderId === tl);
  return list;
}

// Blocks that apply to the chosen Team Leader: their own plus the ones for every Team Leader
export function tlBlocks(blocks, tl) {
  const list = blocks || [];
  if (!tl || tl === 'ALL') return list;
  return list.filter(b => !b.teamLeaderId || b.teamLeaderId === tl);
}

// Bookings on the selected day, soonest first (the table and the export)
export function dayDemos(demos, tl, day) {
  const d = demoDayStr(day);
  return (demos || [])
    .filter(x => ['BOOKED', 'DONE'].includes(x.status) && x.at && (!tl || tl === 'ALL' || x.teamLeaderId === tl))
    .filter(x => istDateStr(x.at) === d)
    .sort((a, b) => a.at - b.at);
}

export function demoSlotState(demos, blocks, tl, day, m) {
  const bookings = (demos || [])
    .filter(d => ['BOOKED', 'DONE'].includes(d.status) && d.at && (!tl || tl === 'ALL' || d.teamLeaderId === tl))
    .filter(d => overlapsSlot(day, d, m));
  const blks = tlBlocks(blocks, tl).filter(b => overlapsSlot(day, b, m));
  const past = demoSlotStart(day, m).getTime() + DEMO_SLOT_MIN * 60000 <= Date.now();
  return { bookings, blocks: blks, past };
}

// The next upcoming booked demo's day (default day of the page)
export function nextDemoDay(demos) {
  const next = demos
    .filter(d => d.status === 'BOOKED' && d.at && d.at.getTime() + d.durationMinutes * 60000 > Date.now())
    .sort((a, b) => a.at - b.at)[0];
  return next ? istDateStr(next.at) : null;
}
