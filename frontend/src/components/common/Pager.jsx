// Table footer: "PAGE 1 / 3 · …" with Prev / Next (and any extra buttons)
import { Chip } from './FilterChips';
import Icon from './Icon';

export default function Pager({ label, page, totalPages, onPage, children, className = 'table-pager', live }) {
  return (
    <div className={className}>
      <span className="pager-label" aria-live={live ? 'polite' : undefined}>{label}</span>
      <div className="pager-actions">
        {onPage && (
          <>
            <Chip disabled={page <= 1} onClick={() => onPage(page - 1)}><Icon name="left" size="sm" />Prev</Chip>
            <Chip disabled={page >= totalPages} onClick={() => onPage(page + 1)}>Next<Icon name="right" size="sm" /></Chip>
          </>
        )}
        {children}
      </div>
    </div>
  );
}
