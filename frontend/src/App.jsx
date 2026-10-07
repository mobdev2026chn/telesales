// Root: the sign-in screen until a portal user is signed in, then the routed portal.
// The toast and docked audio player live outside both.
import { useEffect } from 'react';
import { useSelector } from 'react-redux';
import Toast from './components/common/Toast';
import AudioPlayerBar from './components/layout/AudioPlayerBar';
import LoginPage from './pages/LoginPage';
import AppRoutes from './routes/AppRoutes';
import { getToken } from './utils/api';
import { checkSession } from './utils/actions/authActions';
import { connectRealtime, disconnectRealtime } from './utils/realtime';

export default function App() {
  const status = useSelector(s => s.auth.status);

  useEffect(() => { checkSession(); }, []);

  useEffect(() => {
    if (status !== 'signedIn') return undefined;
    connectRealtime(getToken());
    return disconnectRealtime;
  }, [status]);

  return (
    <>
      <Toast />
      {status === 'signedIn' ? <AppRoutes /> : <LoginPage />}
      <AudioPlayerBar />
    </>
  );
}
