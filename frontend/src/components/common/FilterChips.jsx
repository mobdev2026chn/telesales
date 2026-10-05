// A row of filter chips: options = [{ value, label }]; the active one is highlighted
import { Button } from '../../assets/antd';

// One rounded Ant Design chip button (also used on its own for chip-style toggles)
export function Chip({ active, pressed, className = '', children, ...rest }) {
  return (
    <Button
      shape="round"
      className={`ant-chip${active ? ' is-active' : ''} ${className}`.trim()}
      aria-pressed={pressed ? String(!!active) : undefined}
      {...rest}
    >
      {children}
    </Button>
  );
}

export default function FilterChips({ options, value, onChange, className = 'pill-group', id, children, pressed }) {
  return (
    <div className={className} id={id}>
      {options.map(o => (
        <Chip key={o.value} active={value === o.value} pressed={pressed} title={o.title} onClick={() => onChange(o.value)}>
          {o.label}
        </Chip>
      ))}
      {children}
    </div>
  );
}
