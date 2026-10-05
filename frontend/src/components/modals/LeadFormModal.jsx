// ADD LEAD MODAL (pipeline "+ Add CRM lead" and call-log "+ Lead")
import { useEffect, useRef, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Alert, Button, Input, Select } from '../../assets/antd';
import { closeLeadForm } from '../../redux/slices/uiSlice';
import { selectScope } from '../../redux/selectors';
import { last10 } from '../../utils/format';
import Icon from '../common/Icon';
import { createLead } from '../../utils/actions/leadActions';

export default function LeadFormModal() {
  const dispatch = useDispatch();
  const prefill = useSelector(s => s.ui.leadForm) || {};
  const { dialable } = useSelector(selectScope);
  const [name, setName] = useState(prefill.name || '');
  const [phone, setPhone] = useState(prefill.phone || '');
  const [agentId, setAgentId] = useState(prefill.agentId && dialable.some(u => u.id === prefill.agentId) ? prefill.agentId : '');
  const [notes, setNotes] = useState(prefill.notes || '');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const nameRef = useRef(null);

  useEffect(() => {
    const t = setTimeout(() => { try { nameRef.current.focus(); } catch { /* ignore */ } }, 50);
    return () => clearTimeout(t);
  }, []);

  const close = () => dispatch(closeLeadForm());

  const save = async (e) => {
    e.preventDefault();
    const n = name.trim();
    const p = phone.trim();
    if (!n) { setError('Lead name is required.'); return; }
    if (!last10(p)) { setError('Enter a valid 10-digit phone number.'); return; }
    setBusy(true);
    const res = await createLead({ name: n, phone: p, assignedCallerId: agentId, notes: notes.trim() });
    setBusy(false);
    if (res.ok) close();
    else setError(res.error);
  };

  return (
    <div id="leadFormModal" className="modal-overlay active" role="dialog" aria-modal="true" aria-labelledby="leadFormTitle"
      onClick={(e) => { if (e.target === e.currentTarget) close(); }}>
      <form className="modal-card" style={{ width: 460 }} onSubmit={save} noValidate>
        <div className="modal-header" style={{ marginBottom: 18 }}>
          <div><div className="modal-eyebrow">CRM</div><div id="leadFormTitle" className="modal-title">Add lead</div></div>
          <Button type="text" shape="circle" icon={<Icon name="x" size="sm" />} onClick={close} aria-label="Close" />
        </div>
        <div className="form-group">
          <label className="form-label" htmlFor="leadFormName">Lead / company name *</label>
          <Input id="leadFormName" ref={nameRef} prefix={<Icon name="user" size="sm" />} autoComplete="off" value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="form-group">
          <label className="form-label" htmlFor="leadFormPhone">Phone *</label>
          <Input type="tel" id="leadFormPhone" prefix={<Icon name="phone" size="sm" />} placeholder="10-digit mobile" autoComplete="off" value={phone} onChange={(e) => setPhone(e.target.value)} />
        </div>
        <div className="form-group">
          <label className="form-label" htmlFor="leadFormAgent">Assign to agent</label>
          <Select id="leadFormAgent" className="form-ant-select" value={agentId} onChange={setAgentId}
            showSearch optionFilterProp="label"
            options={[{ value: '', label: 'UNASSIGNED' }, ...dialable.map(u => ({ value: u.id, label: u.name }))]} />
        </div>
        <div className="form-group">
          <label className="form-label" htmlFor="leadFormNotes">Notes</label>
          <Input id="leadFormNotes" autoComplete="off" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </div>
        {error && <Alert className="form-alert" style={{ margin: '0 0 12px' }} type="error" showIcon role="alert" title={error} />}
        <div className="modal-footer">
          <Button onClick={close}>Cancel</Button>
          <Button type="primary" htmlType="submit" loading={busy} icon={<Icon name="save" size="sm" />}>Save lead</Button>
        </div>
      </form>
    </div>
  );
}
