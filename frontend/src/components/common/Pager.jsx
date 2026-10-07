// Table footer: "PAGE 1 / 3 · …" with Prev / page numbers / Next (and any extra buttons)
import { Chip } from './FilterChips';
import Icon from './Icon';

// 1 … 4 5 6 … 12: the first, the last and the pages around the current one
function pageList(page, totalPages) {
  const keep = new Set([1, totalPages, page - 1, page, page + 1]);
  const out = [];
  for (let p = 1; p <= totalPages; p += 1) {
    if (keep.has(p)) out.push(p);
    else if (out[out.length - 1] !== '…') out.push('…');
  }
  return out;
}

export default function Pager({ label, page, totalPages, onPage, children, className = 'table-pager', live }) {
  return (
    <div className={className}>
      <span className="pager-label" aria-live={live ? 'polite' : undefined}>{label}</span>
      <div className="pager-actions">
        {onPage && (
          <>
            <Chip disabled={page <= 1} onClick={() => onPage(page - 1)}><Icon name="left" size="sm" />Prev</Chip>
            {totalPages > 1 && pageList(page, totalPages).map((p, i) => (p === '…'
              ? <span className="pager-gap" key={`gap-${i}`} aria-hidden="true">…</span>
              : <Chip key={p} className="pager-num" active={p === page} aria-current={p === page ? 'page' : undefined}
                  aria-label={`Page ${p}`} onClick={() => p !== page && onPage(p)}>{p}</Chip>))}
            <Chip disabled={page >= totalPages} onClick={() => onPage(page + 1)}>Next<Icon name="right" size="sm" /></Chip>
          </>
        )}
        {children}
      </div>
    </div>
  );
}
