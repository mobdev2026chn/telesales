// Password input with a show / hide eye button
import { Input } from '../../assets/antd';

export default function PasswordField({ id, value, onChange, placeholder, autoComplete, required, size }) {
  return (
    <Input.Password
      id={id}
      size={size}
      placeholder={placeholder}
      autoComplete={autoComplete}
      required={required}
      value={value}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}
