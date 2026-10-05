// App header: the open page's name, "Synced 10:42 AM" and today's date (India time)
import { useSelector } from 'react-redux';
import { TAB_TITLES } from '../../data/navigation';
import { fmtLongDay, fmtTime12 } from '../../utils/format';
import Icon from '../common/Icon';

export default function AppHeader() {
  const tab = useSelector(s => s.ui.tab);
  const lastSync = useSelector(s => s.ui.lastSync);
  const time = lastSync ? fmtTime12(new Date(lastSync)) : '';

  return (
    <header className="app-header">
      <div className="app-breadcrumb">
        <span>Telesales</span><span aria-hidden="true">/</span><strong>{TAB_TITLES[tab] || ''}</strong>
      </div>
      <div className="app-header-meta">
        <span><span className="sync-dot" aria-hidden="true" />{time ? `Synced ${time}` : 'Syncing…'}</span>
        <span><Icon name="calendar" size="sm" /> {fmtLongDay(new Date())}</span>
      </div>
    </header>
  );
}
