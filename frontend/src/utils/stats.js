// Server hourly rows ([{ hourOfDay, calls }]) → 24 counts (India time hours)
export function hourCounts(rows) {
  const byHour = new Array(24).fill(0);
  (Array.isArray(rows) ? rows : []).forEach(hc => {
    const h = Number(hc.hourOfDay);
    if (h >= 0 && h <= 23) byHour[h] = Number(hc.calls) || 0;
  });
  return byHour;
}

const istHourFmt = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour: '2-digit', hourCycle: 'h23' });

// Demo bookings created in [start, end) → counts by creation hour and status, in India time.
export function demoHourCounts(demos, start, end) {
  const byHour = new Array(24).fill(0);
  const byStatusHour = {
    BOOKED: new Array(24).fill(0),
    DONE: new Array(24).fill(0),
  };
  const status = { BOOKED: 0, DONE: 0, CANCELLED: 0, RESCHEDULE: 0 };
  (Array.isArray(demos) ? demos : []).forEach(d => {
    if (!d.bookedAt || Number.isNaN(d.bookedAt.getTime()) || d.bookedAt < start || d.bookedAt >= end) return;
    status[d.status] = (status[d.status] || 0) + 1;
    if (d.status !== 'BOOKED' && d.status !== 'DONE') return;
    const hour = Number(istHourFmt.format(d.bookedAt));
    if (hour >= 0 && hour <= 23) {
      byHour[hour] += 1;
      byStatusHour[d.status][hour] += 1;
    }
  });
  return { byHour, byStatusHour, status };
}

// Sign-in status comes from the employee's latest explicit login/logout timestamps.
export function appPresence(row) {
  return { online: !!(row && row.online) };
}

// Hover text for the green / red dot, e.g. "Signed in to the app · 3 connected calls"
export function presenceTitle(row, connected) {
  const { online } = appPresence(row);
  const calls = connected > 0 ? ` · ${connected} connected call${connected === 1 ? '' : 's'}` : '';
  if (online) return `Signed in to the app${calls}`;
  return `Not signed in to the app${calls}`;
}
