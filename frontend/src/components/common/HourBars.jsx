// Calls (or demos, unit="demo") per hour, 10 AM – 7 PM India time
const hourLabel = (h) => (h > 12 ? `${h - 12}PM` : (h === 12 ? '12PM' : `${h}AM`));

export default function HourBars({ byHour, byStatusHour, unit = 'call' }) {
  const hours = [];
  for (let h = 10; h <= 19; h++) {
    const total = byHour[h] || 0;
    const booked = byStatusHour && (byStatusHour.BOOKED[h] || 0);
    const done = byStatusHour && (byStatusHour.DONE[h] || 0);
    const breakdown = byStatusHour ? `: ${booked} booked, ${done} done` : '';
    hours.push([hourLabel(h), total, `${hourLabel(h)} – ${hourLabel(h + 1)}${breakdown}`, booked, done]);
  }
  const maxH = Math.max(1, ...hours.map(([, cnt]) => cnt));
  return hours.map(([lbl, cnt, span, booked, done]) => {
    const pct = Math.round((cnt / maxH) * 80) + 4;
    const cls = cnt === maxH && cnt > 0 ? 'is-peak' : (cnt > 0 ? 'has-calls' : '');
    return (
      <div className="hour-bar-col" key={lbl} title={`${cnt} ${unit}${cnt === 1 ? '' : 's'} ${span}`}>
        <div className="hour-bar-value">{cnt || ''}</div>
        {byStatusHour ? (
          <div className={`hour-bar-stack${cnt ? '' : ' is-empty'}`} style={{ height: cnt ? `${pct}%` : '4px' }}>
            {booked > 0 && <div className="hour-bar-segment is-booked" style={{ flexGrow: booked }} />}
            {done > 0 && <div className="hour-bar-segment is-done" style={{ flexGrow: done }} />}
          </div>
        ) : (
          <div className={`hour-bar ${cls}`} style={{ height: `${pct}%` }} />
        )}
        <div className="hour-bar-label">{lbl}</div>
      </div>
    );
  });
}
