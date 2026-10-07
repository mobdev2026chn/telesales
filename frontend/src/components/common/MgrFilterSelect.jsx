// "Managed by" filter: every manager-level person in view who has people under them.
// Sits in the toolbar row (like the Call Log's agent filter), not inside the table header.
import { Select } from '../../assets/antd';

export default function MgrFilterSelect({ id, value, options, onChange }) {
  return (
    <>
      <label htmlFor={id} className="visually-hidden">Filter by manager</label>
      <Select
        id={id}
        className={`toolbar-ant-select mgr-filter-ant${value !== 'ALL' ? ' is-active' : ''}`}
        value={value}
        onChange={onChange}
        showSearch
        optionFilterProp="label"
        popupMatchSelectWidth={false}
        placement="bottomRight"
        classNames={{ popup: { root: 'mgr-filter-popup' } }}
        options={[{ value: 'ALL', label: 'ALL MANAGERS' }, ...options]}
      />
    </>
  );
}
