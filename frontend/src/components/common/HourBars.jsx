// Calls (or demos, unit="demo") per hour, 10 AM – 7 PM India time
const hourLabel = (h) => (h > 12 ? `${h - 12}PM` : (h === 12 ? '12PM' : `${h}AM`));

export default function HourBars({ byHour, unit = 'call' }) {
  const hours = [];
  for (let h = 10; h <= 19; h++) hours.push([hourLabel(h), byHour[h] || 0, `${hourLabel(h)} – ${hourLabel(h + 1)}`]);
  const maxH = Math.max(1, ...hours.map(([, c]) => c));
  return hours.map(([lbl, cnt, span]) => {
    const pct = Math.round((cnt / maxH) * 80) + 4;
    const cls = cnt === maxH && cnt > 0 ? 'is-peak' : (cnt > 0 ? 'has-calls' : '');
    return (
      <div className="hour-bar-col" key={lbl} title={`${cnt} ${unit}${cnt === 1 ? '' : 's'} ${span}`}>
        <div className="hour-bar-value">{cnt || ''}</div>
        <div className={`hour-bar ${cls}`} style={{ height: `${pct}%` }} />
        <div className="hour-bar-label">{lbl}</div>
      </div>
    );
  });
}
