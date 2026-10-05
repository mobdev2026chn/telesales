// Icon-only row action: a soft tinted square with a tooltip naming the action.
// tone: view | edit | delete | call | add | play
import { Button, Tooltip } from '../../assets/antd';
import Icon from './Icon';

export default function ActionIcon({ icon, label, tone = 'edit', onClick, disabled }) {
  return (
    <Tooltip title={label}>
      <Button
        className={`action-icon action-icon--${tone}`}
        icon={<Icon name={icon} />}
        aria-label={label}
        disabled={disabled}
        onClick={onClick}
      />
    </Tooltip>
  );
}
