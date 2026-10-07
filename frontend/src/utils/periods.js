// Same India-time periods as the server's getPeriodRange (today / week from Monday / month / one date)
import { CALL_RANGE_DAYS, PERIOD_LABEL } from '../data/constants';
import { istDateStr, istDaysAgoStr, istMidnight } from './format';

function weekStart(today) {
  const [y, m, d] = today.split('-').map(Number);
  const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return istMidnight(istDaysAgoStr((dow + 6) % 7));
}

// [from, to) of a period, ending now (User details page)
export function periodRange(period, date) {
  if (date) {
    const s = istMidnight(date);
    return { from: s, to: new Date(s.getTime() + 24 * 3600 * 1000) };
  }
  const today = istDateStr(new Date());
  let from = istMidnight(today);
  if (period === 'week') from = weekStart(today);
  else if (period === 'month') from = istMidnight(`${today.slice(0, 8)}01`);
  return { from, to: new Date() };
}

// [start, end) of the conversion funnel period (end null = open)
export function funnelRange(period, date) {
  if (date) {
    const [y, m, d] = date.split('-').map(Number);
    return { start: istMidnight(date), end: istMidnight(new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10)) };
  }
  const today = istDateStr(new Date());
  let start = istMidnight(today);
  if (period === 'week') start = weekStart(today);
  else if (period === 'month') start = istMidnight(today.slice(0, 8) + '01');
  return { start, end: null };
}

// [start, end) of the whole period including the rest of it (today / this week / this month / one
// date), for things scheduled ahead such as demo bookings
export function periodWindow(period, date) {
  const { start, end } = funnelRange(period, date);
  if (end) return { start, end };
  if (period === 'month') {
    const [y, m] = istDateStr(new Date()).split('-').map(Number);
    return { start, end: istMidnight(new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10)) };
  }
  const days = period === 'week' ? 7 : 1;
  return { start, end: new Date(start.getTime() + days * 24 * 3600 * 1000) };
}

// Days in the selected period (India time), so WEEK / MONTH compare against daily target × days
export function periodTargetDays(period, customDate) {
  if (customDate || !['week', 'month'].includes(period)) return 1;
  const today = istDateStr(new Date());
  if (period === 'month') return Number(today.slice(8, 10));
  const [y, mo, d] = today.split('-').map(Number);
  return ((new Date(Date.UTC(y, mo - 1, d)).getUTCDay() + 6) % 7) + 1;
}

// "TODAY" / "THIS WEEK" / "12 JAN 2026"
export function periodLabel(period, date) {
  if (date) {
    const d = istMidnight(date);
    return new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', day: 'numeric', month: 'short', year: 'numeric' }).format(d).toUpperCase();
  }
  return PERIOD_LABEL[period] || 'TODAY';
}

// Call Log / Call Recordings date range: from midnight N days ago (India time) to now
export function rangeBounds(range, fallbackDays = 0) {
  const days = CALL_RANGE_DAYS[range] ?? fallbackDays;
  return { from: istMidnight(istDaysAgoStr(days)), to: new Date() };
}
