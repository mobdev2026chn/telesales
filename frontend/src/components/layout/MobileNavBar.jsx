// MOBILE TOP NAV BAR + the dimmed backdrop behind the open sidebar
import { useDispatch, useSelector } from 'react-redux';
import { Button } from '../../assets/antd';
import { setSidebarOpen } from '../../redux/slices/uiSlice';
import Icon from '../common/Icon';
import Logo from '../common/Logo';

export default function MobileNavBar() {
  const dispatch = useDispatch();
  const open = useSelector(s => s.ui.sidebarOpen);

  return (
    <>
      <div className="mobile-nav-bar" id="mobileNavBar">
        <Button className="hamburger-btn" aria-label="Open menu" icon={<Icon name="menu" />} onClick={() => dispatch(setSidebarOpen())}>
          Menu
        </Button>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <Logo style={{ width: 40, height: 'auto', display: 'block' }} />
          <span className="sidebar-brand">TELESALES</span>
        </div>
        <div style={{ width: 40 }} />
      </div>
      <div className={`sidebar-backdrop${open ? ' active' : ''}`} id="sidebarBackdrop" onClick={() => dispatch(setSidebarOpen(false))} />
    </>
  );
}
