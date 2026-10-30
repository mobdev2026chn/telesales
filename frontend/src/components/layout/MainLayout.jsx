// MAIN APPLICATION VIEWPORT: sidebar + header + the open page, the dialogs, and the
// first load / background refresh timers (same timings as the HTML portal)
import { useEffect, useRef } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { DASH_LIVE_MS, REFRESH_MS } from '../../data/constants';
import { PATHS, tabFromPath } from '../../data/navigation';
import { closeBatch, closeDial, closeLeadForm, setSidebarOpen, setTab } from '../../redux/slices/uiSlice';
import { selectScope } from '../../redux/selectors';
import { closeBottomAudioBar } from '../../utils/audioController';
import { isTyping } from '../../utils/dom';
import { canSeeDemosTab } from '../../utils/scope';
import BatchModal from '../modals/BatchModal';
import DialModal from '../modals/DialModal';
import LeadFormModal from '../modals/LeadFormModal';
import AppHeader from './AppHeader';
import ImpersonationBanner from './ImpersonationBanner';
import MobileNavBar from './MobileNavBar';
import Sidebar from './Sidebar';
import { backgroundRefresh, liveTick, refreshIfStale, syncWithBackend } from '../../utils/actions/syncActions';

export default function MainLayout() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const location = useLocation();
  const { me } = useSelector(selectScope);
  const dial = useSelector(s => s.ui.dialLeadId);
  const lead = useSelector(s => s.ui.leadForm);
  const batch = useSelector(s => s.ui.batchOpen);
  const modals = { dial, lead, batch };
  const modalsRef = useRef(modals);
  modalsRef.current = modals;
  const tab = tabFromPath(location.pathname);

  // The open page drives the live refresh; the mobile menu closes on navigation
  useEffect(() => {
    dispatch(setTab(tab));
    dispatch(setSidebarOpen(false));
  }, [tab, dispatch]);

    // First load after sign-in: sync with backend (stays on user-selected page / dashboard without auto-redirecting to demos)
  useEffect(() => {
    syncWithBackend();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Background refresh every 60 s; the open page's live numbers every 20 s
  useEffect(() => {
    const refresh = setInterval(() => backgroundRefresh(), REFRESH_MS);
    const live = setInterval(() => liveTick(), DASH_LIVE_MS);
    const onVisible = () => refreshIfStale();
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(refresh);
      clearInterval(live);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [dispatch]);

  // Escape: close an open dialog first; otherwise stop audio — but never while typing
  useEffect(() => {
    const onKey = (e) => {
      if (e.key !== 'Escape') return;
      const m = modalsRef.current;
      if (m.dial) { dispatch(closeDial()); return; }
      if (m.lead) { dispatch(closeLeadForm()); return; }
      if (m.batch) { dispatch(closeBatch()); return; }
      if (isTyping()) return;
      closeBottomAudioBar();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dispatch]);

  return (
    <>
      <MobileNavBar />
      <div id="appViewport" style={{ display: 'flex' }}>
        <Sidebar />
        <div className="main-column">
          <AppHeader />
          <main className="main-viewport">
            <div className="main-inner">
              <ImpersonationBanner />
              <div className="tab-view active" key={tab === 'user' ? location.pathname : tab}>
                <Outlet />
              </div>
            </div>
          </main>
        </div>
      </div>
      {modals.dial && <DialModal />}
      {modals.batch && <BatchModal />}
      {modals.lead && <LeadFormModal />}
    </>
  );
}
