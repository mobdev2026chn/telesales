// LEAD DIAL MODAL: records the outcome on the lead (the phone app logs the actual call)
import { useEffect, useRef, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Alert, Button, Input } from '../../assets/antd';
import { DIAL_OUTCOMES } from '../../data/constants';
import { closeDial } from '../../redux/slices/uiSlice';
import { formatPhone, initialOf } from '../../utils/format';
import { leadAgentName, leadLabel } from '../../utils/leads';
import { commitDialOutcome } from '../../utils/actions/leadActions';
import { Chip } from '../common/FilterChips';
import Icon from '../common/Icon';

export default function DialModal() {
  const dispatch = useDispatch();
  const leadId = useSelector(s => s.ui.dialLeadId);
  const leads = useSelector(s => s.leads.list);
  const users = useSelector(s => s.users.list);
  // The lead as it was when the dialog opened
  const [lead] = useState(() => leads.find(l => l.id === leadId) || null);
  const [outcome, setOutcome] = useState('INTERESTED');
  const [note, setNote] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const noteRef = useRef(null);

  useEffect(() => {
    if (!lead) { dispatch(closeDial()); return undefined; }
    const t = setTimeout(() => { try { noteRef.current.focus(); } catch { /* ignore */ } }, 50);
    return () => clearTimeout(t);
  }, [lead, dispatch]);

  if (!lead) return null;

  const close = () => dispatch(closeDial());
  const digits = String(lead.phone || '').replace(/[^\d+]/g, '');

  const commit = async () => {
    setBusy(true);
    setError('');
    const res = await commitDialOutcome(lead, outcome || 'INTERESTED', note);
    setBusy(false);
    if (res.ok) close();
    else setError(res.error);
  };

  return (
    <div id="dialModal" className="modal-overlay active" role="dialog" aria-modal="true" aria-labelledby="dialModalName"
      onClick={(e) => { if (e.target === e.currentTarget) close(); }}>
      <div className="modal-card dial-card">
        <div style={{ minWidth: 0 }}>
          <div className="modal-eyebrow" style={{ marginBottom: 14 }}>Call session · record lead outcome</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 18 }}>
            <div className="avatar dial-avatar" aria-hidden="true">{initialOf(lead.name)}</div>
            <div style={{ minWidth: 0 }}>
              <div className="modal-title" id="dialModalName">{lead.name}</div>
              <a href={digits ? `tel:${digits}` : '#'} className="mono phone-number fw-700 tel-link" style={{ fontSize: 'var(--ds-fs-base)' }} title="Call this number">
                <Icon name="phone" size="sm" /> {formatPhone(lead.phone)}
              </a>
            </div>
          </div>

          <div style={{ marginBottom: 16 }}>
            <div id="dialOutcomeLabel" className="field-label">Call outcome</div>
            <div className="dial-outcomes" role="group" aria-labelledby="dialOutcomeLabel">
              {DIAL_OUTCOMES.map(o => (
                <Chip key={o.value} active={outcome === o.value} pressed onClick={() => setOutcome(o.value)}>
                  {o.label}
                </Chip>
              ))}
            </div>
          </div>

          <div className="form-group">
            <label htmlFor="dialModalNote" className="form-label">Call notes / feedback</label>
            <Input id="dialModalNote" ref={noteRef} value={note}
              placeholder="E.g. Wants pricing deck, follow up tomorrow..."
              onChange={(e) => setNote(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); commit(); } }} />
          </div>

          {error && <Alert className="form-alert" style={{ margin: '0 0 12px' }} type="error" showIcon role="alert" title={error} />}

          <Button type="primary" size="large" block loading={busy} icon={<Icon name="save" />} onClick={commit}>
            Save outcome &amp; update CRM
          </Button>
        </div>

        <div className="dial-side">
          <div>
            <div className="modal-eyebrow" style={{ marginBottom: 10 }}>Lead details</div>
            <div className="detail-list">
              <div className="detail-row"><span className="detail-label">Assigned agent</span><strong className="detail-value">{leadAgentName(users, lead)}</strong></div>
              <div className="detail-row"><span className="detail-label">Status</span><strong className="detail-value">{leadLabel(lead)}</strong></div>
              <div className="detail-row"><span className="detail-label">Dial attempts</span><strong className="detail-value">{lead.attempts || 0}</strong></div>
            </div>
          </div>
          <Button icon={<Icon name="x" size="sm" />} onClick={close}>Cancel</Button>
        </div>
      </div>
    </div>
  );
}
