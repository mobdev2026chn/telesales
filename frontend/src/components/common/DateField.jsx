// Calendar date picker limited to 2020–2030 (the page validates the value). Value in and out: 'YYYY-MM-DD' or ''.
import dayjs from 'dayjs';
import { DatePicker, Tooltip } from '../../assets/antd';
import Icon from './Icon';

const MIN_DATE = dayjs('2020-01-01');
const MAX_DATE = dayjs('2030-12-31');

export default function DateField({ value, onChange, label, title, id, allowClear = true }) {
  const picker = (
    <DatePicker
      id={id}
      className="date-picker"
      aria-label={label}
      value={value ? dayjs(value) : null}
      minDate={MIN_DATE}
      maxDate={MAX_DATE}
      allowClear={allowClear}
      format="DD MMM YYYY"
      placeholder="Pick a date"
      suffixIcon={<Icon name="calendar" size="sm" />}
      onChange={(d) => onChange(d ? d.format('YYYY-MM-DD') : '')}
    />
  );
  return title ? <Tooltip title={title}>{picker}</Tooltip> : picker;
}
