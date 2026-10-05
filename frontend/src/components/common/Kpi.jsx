// KPI tiles. tone: '' | dark | brand | success | warning | danger | lime
import { Col, Row } from '../../assets/antd';

export function Kpi({ num, label, value, meta, tone, title }) {
  return (
    <div className={`kpi${tone ? ` kpi--${tone}` : ''}`} title={title}>
      <div className="kpi-head"><span className="kpi-label">{num ? `${num} · ` : ''}{label}</span></div>
      <div className="kpi-value">{value}</div>
      {meta !== undefined && <div className="kpi-meta">{meta}</div>}
    </div>
  );
}

// Tiles numbered 01, 02, … in order: 4 per row on desktop, 2 on tablets and phones
export function KpiGrid({ items, start = 0 }) {
  return (
    <Row gutter={[16, 16]} className="kpi-row">
      {items.map((k, i) => (
        <Col xs={12} lg={6} key={k.label}>
          <Kpi {...k} num={String(start + i + 1).padStart(2, '0')} />
        </Col>
      ))}
    </Row>
  );
}
