// ==========================================
// 7. LEADS PIPELINE (server-backed kanban)
// ==========================================
import { useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button, Select } from '../assets/antd';
import { LeadBadge } from '../components/common/Badge';
import FilterChips from '../components/common/FilterChips';
import Icon from '../components/common/Icon';
import PageHeader from '../components/common/PageHeader';
import SearchField from '../components/common/SearchField';
import UserLink from '../components/common/UserLink';
import { PIPELINE_PAGE_SIZE, PIPELINE_STAGE_FILTERS, PIPELINE_STAGES, STAGE_CLASS, STATUS_LABEL } from '../data/constants';
import { loadMorePipelineStage, setPipelineAgent, setPipelineSearch, setPipelineStage } from '../redux/slices/leadsSlice';
import { openLeadForm } from '../redux/slices/uiSlice';
import { selectScope, selectScopedLeads } from '../redux/selectors';
import { domKey, formatPhone, roleLabel } from '../utils/format';
import { leadAgentName, leadMatches } from '../utils/leads';
import { moveLeadStage } from '../utils/actions/leadActions';

const colId = (st) => st.replace(/[- ]/g, '_');

// Two letters for the card avatar; leads saved under a number get a phone icon instead
function leadInitials(name) {
  const words = String(name || '').replace(/[^A-Za-z\s]/g, ' ').trim().split(/\s+/).filter(Boolean);
  return words.slice(0, 2).map(w => w[0].toUpperCase()).join('');
}

export default function LeadsPipelinePage() {
  const dispatch = useDispatch();
  const leadsState = useSelector(s => s.leads);
  const scopedAll = useSelector(selectScopedLeads);
  const { users, scoped } = useSelector(selectScope);
  const { pipelineStage, pipelineAgent, pipelineSearch, pipelinePages } = leadsState;

  const agentValid = pipelineAgent === 'ALL' || scoped.some(u => u.id === pipelineAgent);
  useEffect(() => {
    if (!agentValid) dispatch(setPipelineAgent('ALL'));
  }, [agentValid, dispatch]);
  const agent = agentValid ? pipelineAgent : 'ALL';

  let leads = scopedAll;
  if (agent !== 'ALL') {
    const au = users.find(u => u.id === agent);
    leads = leads.filter(l => (l.agentId ? l.agentId === agent : (au && l.agent === au.name)));
  }
  if (pipelineSearch) leads = leads.filter(l => leadMatches(users, l, pipelineSearch));

  const subtitle = leadsState.error && !leadsState.list.length
    ? 'Could not load leads'
    : `${leads.length} lead${leads.length === 1 ? '' : 's'} in the pipeline`;

  return (
    <>
      <PageHeader title="Leads Pipeline" subtitle={subtitle}>
        <SearchField id="pipelineSearchInput" label="Search pipeline" placeholder="Search lead, phone, agent…"
          defaultValue={pipelineSearch} onChange={(v) => dispatch(setPipelineSearch(v))} />
        <label htmlFor="pipelineAgentFilter" className="visually-hidden">Agent</label>
        <Select id="pipelineAgentFilter" className="toolbar-ant-select" value={agent} onChange={(v) => dispatch(setPipelineAgent(v))}
          showSearch optionFilterProp="label" popupMatchSelectWidth={false}
          options={[{ value: 'ALL', label: 'ALL AGENTS' }, ...scoped.map(u => ({ value: u.id, label: `${u.name.toUpperCase()} (${roleLabel(u.role)})` }))]} />
        <Button type="primary" icon={<Icon name="plus" size="sm" />} onClick={() => dispatch(openLeadForm({}))}>Add CRM lead</Button>
      </PageHeader>

      {/* STAGE FILTER CHIPS (NEW, INTERESTED, FOLLOW-UP, CONVERTED, NOT INTERESTED) */}
      <div className="toolbar">
        <FilterChips id="pipelineStageChips" options={PIPELINE_STAGE_FILTERS} value={pipelineStage} onChange={(v) => dispatch(setPipelineStage(v))} />
      </div>

      <div className={`kanban-grid${pipelineStage !== 'ALL' ? ' single-stage' : ''}`}>
        {PIPELINE_STAGES.map(st => {
          const cid = colId(st);
          if (pipelineStage !== 'ALL' && pipelineStage !== cid) return null;
          const colLeads = leads.filter(l => l.stage === st);
          const totalPages = Math.max(1, Math.ceil(colLeads.length / PIPELINE_PAGE_SIZE));
          const page = Math.min(Math.max(1, pipelinePages[cid] || 1), totalPages);
          const visible = colLeads.slice(0, page * PIPELINE_PAGE_SIZE);
          return (
            <div className={`kanban-col ${STAGE_CLASS[st]}`} key={st}>
              <div className="kanban-col-head">
                <span className={`badge ${STAGE_CLASS[st]}`}>{st}</span>
                <span className="kanban-col-count" title={`${colLeads.length} lead${colLeads.length === 1 ? '' : 's'} · showing ${visible.length}`}>{colLeads.length}</span>
              </div>
              <div className="kanban-col-body">
                {colLeads.length === 0 ? <div className="empty-box">Empty stage</div> : (
                  <>
                    {visible.map(l => {
                      const selId = `leadStage_${domKey(l.id)}`;
                      const rawLabel = STATUS_LABEL[l.status] || String(l.status).toUpperCase();
                      const agentName = leadAgentName(users, l);
                      return (
                        <div className="kanban-card" key={l.id}>
                          <div className="kanban-card-top">
                            <span className="kanban-card-avatar" aria-hidden="true">{leadInitials(l.name) || <Icon name="phone" size="sm" />}</span>
                            <div style={{ minWidth: 0, flex: 1 }}>
                              <div className="kanban-card-name" title={l.name}>{l.name}</div>
                              <div className="kanban-card-phone phone-number">{formatPhone(l.phone)}</div>
                            </div>
                            {rawLabel !== st && <LeadBadge lead={l} />}
                          </div>
                          <div className="kanban-card-meta"><Icon name="user" size="sm" /><UserLink user={{ id: l.agentId, name: agentName }} label={agentName} /></div>
                          <div className="kanban-card-notes" title={l.notes || ''}>{l.notes || '—'}</div>
                          <div className="kanban-card-foot">
                            <span className="kanban-card-foot-label" aria-hidden="true">Stage</span>
                            <label htmlFor={selId} className="visually-hidden">Stage for {l.name}</label>
                            <Select id={selId} size="small" className="stage-ant-select" value={l.stage} onChange={(v) => moveLeadStage(l.id, v)}
                              options={PIPELINE_STAGES.map(s => ({ value: s, label: s }))} />
                          </div>
                        </div>
                      );
                    })}
                    {visible.length < colLeads.length && (
                      <Button size="small" block className="kanban-more" icon={<Icon name="ellipsis" size="sm" />} onClick={() => dispatch(loadMorePipelineStage(cid))}>
                        View more · {colLeads.length - visible.length} more
                      </Button>
                    )}
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </>
  );
}
