// Search box with the magnifier icon (and a clear button when onClear is given)
import { Input } from '../../assets/antd';
import Icon from './Icon';

export default function SearchField({ id, label, placeholder, value, defaultValue, onChange, onEnter, onClear, style }) {
  return (
    <Input
      id={id}
      className="search-input"
      style={style}
      aria-label={label}
      placeholder={placeholder}
      value={value}
      defaultValue={defaultValue}
      prefix={<Icon name="search" size="sm" />}
      allowClear={!!onClear}
      // The clear (×) button fires onChange with a click event
      onChange={(e) => { if (e.type === 'click' && onClear) onClear(); else onChange(e.target.value); }}
      onPressEnter={onEnter ? () => onEnter() : undefined}
    />
  );
}
