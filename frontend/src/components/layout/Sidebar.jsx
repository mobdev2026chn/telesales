// LEFT SIDEBAR: navigation, signed-in profile card, log out
import { useDispatch, useSelector } from 'react-redux';
import { NavLink, useNavigate } from 'react-router-dom';
import { Button, NAV_ICONS } from '../../assets/antd';
import { NAV_ITEMS, PATHS } from '../../data/navigation';
import { setSidebarOpen } from '../../redux/slices/uiSlice';
import { selectScope } from '../../redux/selectors';
import { onKeyActivate } from '../../utils/dom';
import { roleLabel } from '../../utils/format';
import { canSeeDemosTab, canSeeUsersTab } from '../../utils/scope';
import Avatar from '../common/Avatar';
import Icon from '../common/Icon';
import Logo from '../common/Logo';
import { logout } from '../../utils/actions/authActions';

export default function Sidebar() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const { me } = useSelector(selectScope);
  const open = useSelector(s => s.ui.sidebarOpen);

  const allowed = (item) => {
    if (item.guard === 'users') return canSeeUsersTab(me);
    if (item.guard === 'demos') return canSeeDemosTab(me);
    return true;
  };
  const openProfile = () => navigate(PATHS.profile);

  return (
    <aside className={`sidebar${open ? ' mobile-open' : ''}`} id="appSidebar">
      <div className="sidebar-header">
        <Logo className="sidebar-logo" />
        <div className="sidebar-brand">TELESALES<br />MONITOR</div>
        <Button
          type="text"
          onClick={() => dispatch(setSidebarOpen(false))}
          aria-label="Close menu"
          className="sidebar-close-btn"
          style={{ display: open ? 'inline-flex' : 'none' }}
          icon={<Icon name="x" />}
        />
      </div>

      <div className="sidebar-section-label">Workspace</div>
      <nav className="sidebar-nav-list" aria-label="Main">
        {NAV_ITEMS.filter(allowed).map(item => (
          <NavLink key={item.tab} to={item.path} className={({ isActive }) => `nav-pill${isActive ? ' active' : ''}`}>
            <Icon name={NAV_ICONS[item.tab]} />
            {item.label}
          </NavLink>
        ))}
      </nav>

      <div className="sidebar-footer">
        <div className="sidebar-profile-card" role="button" tabIndex={0} aria-label="View profile" onClick={openProfile} onKeyDown={onKeyActivate(openProfile)}>
          <Avatar user={me} className="sidebar-avatar" as="div" />
          <div style={{ minWidth: 0, flex: 1 }}>
            <div className="sidebar-user-name truncate">{me.name}</div>
            <div className="sidebar-user-role">{roleLabel(me.role)} · VIEW PROFILE</div>
          </div>
        </div>
        <Button className="sidebar-logout-btn" icon={<Icon name="logout" size="sm" />} onClick={() => logout()}>Log out</Button>
      </div>
    </aside>
  );
}
