// GLOBAL TOAST NOTIFICATION: an Ant Design message for 3.2 s
import { useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { AntApp } from '../../assets/antd';
import { TOAST_MS } from '../../data/constants';
import { hideToast } from '../../redux/slices/uiSlice';

export default function Toast() {
  const dispatch = useDispatch();
  const { message } = AntApp.useApp();
  const { msg, seq } = useSelector(s => s.ui.toast);

  useEffect(() => {
    if (!msg) return undefined;
    message.open({ key: 'globalToast', type: 'info', content: msg, duration: TOAST_MS / 1000, className: 'global-toast' });
    const t = setTimeout(() => dispatch(hideToast()), TOAST_MS);
    return () => clearTimeout(t);
  }, [msg, seq, dispatch, message]);

  return null;
}
