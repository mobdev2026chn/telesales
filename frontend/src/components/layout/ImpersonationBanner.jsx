// "View as" banner: shown while an admin looks at the portal scoped to someone else's team
import { useSelector } from 'react-redux';
import { Button } from '../../assets/antd';
import { selectScope } from '../../redux/selectors';
import { roleLabel } from '../../utils/format';
import { returnToMyView } from '../../utils/actions/syncActions';
import Icon from '../common/Icon';

export default function ImpersonationBanner() {
  const { me, isRealAdmin, viewAsId, authId } = useSelector(selectScope);
  if (!(isRealAdmin && viewAsId && viewAsId !== authId)) return null;

  return (
    <div className="impersonation-banner" style={{ display: 'flex' }}>
      <span><Icon name="eye" size="sm" /> VIEWING AS {me.name.toUpperCase()} · {roleLabel(me.role)} VIEW — DATA SCOPED TO THEIR TEAM</span>
      <Button size="small" className="btn-ink" icon={<Icon name="back" size="sm" />} onClick={() => returnToMyView()}>Return to my view</Button>
    </div>
  );
}
