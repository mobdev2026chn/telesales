// "Managed by" column header with its filter: every manager-level person in view who has people under them
import { Select } from '../../assets/antd';

export default function MgrFilterSelect({ id, value, options, onChange }) {
  return (
    <span className="mgr-filter-cell">
      Managed by
      <label htmlFor={id} className="visually-hidden">Filter by manager</label>
      <Select
        id={id}
        size="small"
        className={`mgr-filter-ant${value !== 'ALL' ? ' is-active' : ''}`}
        value={value}
        onChange={onChange}
        showSearch
        optionFilterProp="label"
        popupMatchSelectWidth={false}
        options={[{ value: 'ALL', label: 'ALL MANAGERS' }, ...options]}
      />
    </span>
  );
}
