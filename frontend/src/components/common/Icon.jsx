// One Ant Design icon by name (assets/antd.js ICONS): <Icon name="phone" size="sm" />
import { ICON_ROTATE, ICONS } from '../../assets/antd';

export default function Icon({ name, size, className = '' }) {
  const AntIcon = ICONS[name] || ICONS.alert;
  const cls = ['ant-ico', size ? `ant-ico-${size}` : '', className].filter(Boolean).join(' ');
  return <AntIcon className={cls} rotate={ICON_ROTATE[name]} aria-hidden="true" />;
}
