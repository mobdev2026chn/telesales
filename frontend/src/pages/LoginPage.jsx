// LOGIN: admins, managers, junior managers and team leaders (POST /auth/admin-login)
import { useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Alert, Button, Input } from '../assets/antd';
import Icon from '../components/common/Icon';
import Logo from '../components/common/Logo';
import PasswordField from '../components/common/PasswordField';
import { clearLoginError } from '../redux/slices/authSlice';
import { login } from '../utils/actions/authActions';

export default function LoginPage() {
  const dispatch = useDispatch();
  const storeError = useSelector(s => s.auth.loginError);
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const shownError = error || storeError;

  const submit = async (e) => {
    e.preventDefault();
    setError('');
    dispatch(clearLoginError());
    const id = identifier.trim();
    if (!id || !password) {
      setError('Enter your email (or phone) and password.');
      return;
    }
    setBusy(true);
    const res = await login(id, password);
    if (res.ok) return;   // the portal opens; this page unmounts
    setBusy(false);
    setError(res.error);
  };

  return (
    <div id="webLoginOverlay">
      <div className="login-card">
        <div className="login-logo"><Logo /></div>
        <div className="login-title">Telesales Monitor</div>
        <div className="login-subtitle">Admin, manager &amp; team leader portal</div>

        {shownError && <Alert className="login-alert" type="error" showIcon role="alert" title={shownError} />}
        <form onSubmit={submit} noValidate>
          <div className="form-group">
            <label className="form-label" htmlFor="webLoginEmail">Email or phone</label>
            <Input id="webLoginEmail" size="large" prefix={<Icon name="user" size="sm" />} autoComplete="username" inputMode="email"
              autoCapitalize="off" spellCheck="false" required value={identifier} onChange={(e) => setIdentifier(e.target.value)} />
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="webLoginPassword">Password</label>
            <PasswordField id="webLoginPassword" size="large" autoComplete="current-password" required value={password} onChange={setPassword} />
          </div>

          <Button type="primary" htmlType="submit" size="large" block style={{ marginTop: 6 }} loading={busy} icon={<Icon name="login" />}>
            {busy ? 'Signing in…' : 'Sign in'}
          </Button>
          <div className="login-note">Admins, managers &amp; junior managers only.</div>
        </form>
      </div>
    </div>
  );
}
