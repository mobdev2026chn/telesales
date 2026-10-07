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

// Demo bookings scheduled in [start, end) → 24 counts by India time hour (only booked / done ones;
// cancelled and sent back for rescheduling are left out) plus the number per status
export function demoHourCounts(demos, start, end) {
  const byHour = new Array(24).fill(0);
  const status = { BOOKED: 0, DONE: 0, CANCELLED: 0, RESCHEDULE: 0 };
  (Array.isArray(demos) ? demos : []).forEach(d => {
    if (!d.at || d.at < start || d.at >= end) return;
    status[d.status] = (status[d.status] || 0) + 1;
    if (d.status !== 'BOOKED' && d.status !== 'DONE') return;
    const h = Number(istHourFmt.format(d.at));
    if (h >= 0 && h <= 23) byHour[h] += 1;
  });
  return { byHour, status };
}

// Phone-app sign-in status of one person, from a server stats row ({ online, lastSeenAt }).
// online = the app sent a heartbeat in the last 5 minutes and the user has not logged out.
export function appPresence(row) {
  return { online: !!(row && row.online), lastSeenAt: (row && row.lastSeenAt) || null };
}

// Hover text for the green / red dot, e.g. "Signed in to the app · 3 connected calls"
export function presenceTitle(row, connected, fmtTs) {
  const { online, lastSeenAt } = appPresence(row);
  const calls = connected > 0 ? ` · ${connected} connected call${connected === 1 ? '' : 's'}` : '';
  if (online) return `Signed in to the app${calls}`;
  return `Not signed in to the app${lastSeenAt ? ` · last active ${fmtTs(new Date(lastSeenAt))}` : ''}${calls}`;
}
