import { useState, useMemo } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Badge, Button, Drawer, Empty, Popconfirm, Segmented, Space, Spin, Tag, Tooltip } from '../../assets/antd';
import Icon from './Icon';
import { fmtTs, roleLabel } from '../../utils/format';
import { setNotificationsDrawer } from '../../redux/slices/notificationsSlice';
import {
  fetchNotifications,
  markNotificationAsRead,
  markAllNotificationsAsRead,
  clearAllNotifications,
  deleteNotification,
} from '../../utils/actions/notificationActions';

export default function NotificationCenter() {
  const dispatch = useDispatch();
  const { list = [], unreadCount = 0, pending = false, drawerOpen = false } = useSelector(
    (s) => s.notifications || {}
  );
  const [filter, setFilter] = useState('all');

  const isRecordOffNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('turned off') || text.includes('disabled') || text.includes('record turned off') || text.includes('recording off');
  };

  const isRecordOnNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    if (text.includes('turned off') || text.includes('disabled') || text.includes('record turned off') || text.includes('recording off')) {
      return false;
    }
    return text.includes('turned on') || text.includes('re-enabled') || text.includes('enabled') || text.includes('record turned on') || text.includes('recording on');
  };

  const isInactivityNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('inactivity') || text.includes('inactive');
  };

  const isLeadNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('lead') || text.includes('follow') || text.includes('interest');
  };

  const getCallerDisplayName = (item) => {
    // If senderName is set and not a generic system/admin label or generic 'caller'
    if (
      item.senderName &&
      typeof item.senderName === 'string' &&
      !['system', 'admin', 'caller', 'system alert'].includes(item.senderName.trim().toLowerCase())
    ) {
      return item.senderName.trim();
    }

    // Try extracting actual caller name from message: "Caller Dineshram (89255...)"
    const msg = String(item.message || '');
    const callerMatch = msg.match(/^Caller\s+([A-Za-z0-9_.\s]+?)\s*\(/i);
    if (callerMatch && callerMatch[1] && callerMatch[1].trim().toLowerCase() !== 'caller') {
      return callerMatch[1].trim();
    }

    // Try format "<Name> (987654...)"
    const nameMatch = msg.match(/^([A-Za-z0-9_.\s]+?)\s*\(\d{7,15}\)/);
    if (nameMatch && nameMatch[1] && !['caller', 'admin', 'system'].includes(nameMatch[1].trim().toLowerCase())) {
      return nameMatch[1].trim();
    }

    // Fallback to recipientName if it's an employee
    if (
      item.recipientName &&
      typeof item.recipientName === 'string' &&
      !['system', 'admin', 'caller'].includes(item.recipientName.trim().toLowerCase())
    ) {
      return item.recipientName.trim();
    }

    if (item.senderName && item.senderName.trim() && item.senderName.trim().toLowerCase() !== 'caller') {
      return item.senderName.trim();
    }

    return null;
  };

  const getNotificationTitle = (item, isInactive, isRecordOff, isRecordOn, isLead) => {
    const callerName = getCallerDisplayName(item);
    const rawTitle = (item.title || '').trim();

    // If title is missing OR if title was mistakenly set to just the caller's name
    if (!rawTitle || (callerName && rawTitle.toLowerCase() === callerName.toLowerCase())) {
      if (isInactive) return 'Caller Inactivity Alert';
      if (isRecordOff) return 'Auto-Record Turned OFF';
      if (isRecordOn) return 'Auto-Record Turned ON';
      if (isLead) return 'Lead Status Updated';
      return 'System Notification';
    }

    return rawTitle;
  };

  const recordOffCount = useMemo(() => {
    return list.filter((n) => isRecordOffNotification(n)).length;
  }, [list]);

  const recordOnCount = useMemo(() => {
    return list.filter((n) => isRecordOnNotification(n)).length;
  }, [list]);

  const filteredList = useMemo(() => {
    if (filter === 'recordOff') {
      return list.filter((n) => isRecordOffNotification(n));
    }
    if (filter === 'recordOn') {
      return list.filter((n) => isRecordOnNotification(n));
    }
    if (filter === 'unread') {
      return list.filter((n) => !n.isRead);
    }
    return list;
  }, [list, filter]);

  return (
    <>
      <Tooltip title={unreadCount > 0 ? `${unreadCount} unread notifications` : 'Notifications'}>
        <button
          type="button"
          className="notification-bell-btn"
          onClick={() => dispatch(setNotificationsDrawer(true))}
          aria-label="Open notifications"
        >
          <Badge count={unreadCount} overflowCount={99} size="small" offset={[-2, 2]}>
            <Icon name="bell" size="md" className="bell-icon" />
          </Badge>
        </button>
      </Tooltip>

      <Drawer
        title={
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%', paddingRight: 4 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <Icon name="bell" size="sm" />
              <span style={{ fontWeight: 700, fontSize: 14, color: '#1a202c' }}>Notifications</span>
              {unreadCount > 0 && (
                <span style={{
                  background: '#ef4444',
                  color: '#fff',
                  fontSize: 10,
                  fontWeight: 700,
                  padding: '1px 6px',
                  borderRadius: 10,
                  lineHeight: 1.2
                }}>
                  {unreadCount} NEW
                </span>
              )}
            </div>
            <Space size="small">
              <Button
                type="text"
                size="small"
                onClick={() => fetchNotifications()}
                icon={<Icon name="history" />}
                loading={pending}
                title="Refresh notifications"
                style={{ color: '#4b5563' }}
              />
              {unreadCount > 0 && (
                <Button
                  type="link"
                  size="small"
                  style={{ padding: '0 4px', fontSize: 11, fontWeight: 600, color: '#16a34a' }}
                  onClick={() => markAllNotificationsAsRead()}
                >
                  Mark all read
                </Button>
              )}
              {list.length > 0 && (
                <Popconfirm
                  title="Clear all notifications?"
                  description="This permanently deletes all notifications in your inbox."
                  okText="Clear all"
                  okButtonProps={{ danger: true }}
                  onConfirm={clearAllNotifications}
                >
                  <Button
                    type="link"
                    danger
                    size="small"
                    style={{ padding: '0 4px', fontSize: 11, fontWeight: 600 }}
                  >
                    Clear all
                  </Button>
                </Popconfirm>
              )}
            </Space>
          </div>
        }
        placement="right"
        width={470}
        open={drawerOpen}
        onClose={() => dispatch(setNotificationsDrawer(false))}
        bodyStyle={{ padding: '10px 14px', background: '#f8fafc' }}
      >
        <div style={{
          display: 'flex',
          alignItems: 'center',
          background: '#f2f0ea',
          padding: '3px',
          borderRadius: 9,
          border: '1px solid #e5e3dc',
          marginBottom: 10,
          gap: 2,
          boxSizing: 'border-box',
          width: '100%'
        }}>
          {[
            { key: 'all', label: `All Alerts (${list.length})` },
            { key: 'recordOff', label: `Recording OFF (${recordOffCount})`, isOff: true },
            { key: 'recordOn', label: `Recording ON (${recordOnCount})`, isOn: true },
            { key: 'unread', label: `Unread (${unreadCount})` },
          ].map((tab) => {
            const isActive = filter === tab.key;
            return (
              <button
                key={tab.key}
                type="button"
                onClick={() => setFilter(tab.key)}
                style={{
                  flex: 1,
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 3,
                  padding: '5px 2px',
                  fontSize: 10.5,
                  fontWeight: isActive ? 700 : 500,
                  color: tab.isOff ? '#dc2626' : tab.isOn ? '#16a34a' : isActive ? '#0f172a' : '#52525b',
                  background: isActive ? '#ffffff' : 'transparent',
                  border: 'none',
                  borderRadius: 7,
                  boxShadow: isActive ? '0 1px 3px rgba(0,0,0,0.08)' : 'none',
                  cursor: 'pointer',
                  whiteSpace: 'nowrap',
                  transition: 'all 0.15s ease',
                  outline: 'none',
                }}
              >
                {tab.isOff && <span style={{ fontSize: 7, color: '#dc2626' }}>●</span>}
                {tab.isOn && <span style={{ fontSize: 7, color: '#16a34a' }}>●</span>}
                <span>{tab.label}</span>
              </button>
            );
          })}
        </div>

        {pending && list.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '30px 0' }}>
            <Spin tip="Loading notifications..." />
          </div>
        ) : filteredList.length === 0 ? (
          <div style={{ padding: '30px 0', textAlign: 'center' }}>
            <Empty
              image={Empty.PRESENTED_IMAGE_SIMPLE}
              description={
                filter === 'recordOff'
                  ? 'No Auto-Recording OFF alerts recorded'
                  : filter === 'recordOn'
                  ? 'No Auto-Recording ON alerts recorded'
                  : filter === 'unread'
                  ? 'No unread notifications'
                  : 'No notifications yet'
              }
            />
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {filteredList.map((item) => {
              const itemId = item.id || item._id;
              const isRecordOff = isRecordOffNotification(item);
              const isRecordOn = isRecordOnNotification(item);
              const isInactive = isInactivityNotification(item);
              const isLead = isLeadNotification(item);

              const callerDisplayName = getCallerDisplayName(item);
              const notifTitle = getNotificationTitle(item, isInactive, isRecordOff, isRecordOn, isLead);

              const cardBg = item.isRead
                ? '#ffffff'
                : isRecordOff
                ? '#fffbfa'
                : isRecordOn
                ? '#f8fdf8'
                : isInactive
                ? '#fffdf7'
                : isLead
                ? '#faf5ff'
                : '#f0f7ff';

              const cardBorder = item.isRead
                ? '1px solid #e2e8f0'
                : isRecordOff
                ? '1px solid #fecaca'
                : isRecordOn
                ? '1px solid #bbf7d0'
                : isInactive
                ? '1px solid #fed7aa'
                : isLead
                ? '1px solid #e9d5ff'
                : '1px solid #bfdbfe';

              const borderLeftColor = item.isRead
                ? '#cbd5e1'
                : isRecordOff
                ? '#ef4444'
                : isRecordOn
                ? '#22c55e'
                : isInactive
                ? '#f59e0b'
                : isLead
                ? '#8b5cf6'
                : '#3b82f6';

              return (
                <div
                  key={itemId || Math.random()}
                  onClick={() => {
                    if (!item.isRead && itemId) markNotificationAsRead(itemId);
                  }}
                  style={{
                    backgroundColor: cardBg,
                    border: cardBorder,
                    borderLeft: `3.5px solid ${borderLeftColor}`,
                    borderRadius: 8,
                    padding: '9px 12px',
                    boxShadow: item.isRead ? 'none' : '0 1px 3px rgba(0,0,0,0.03)',
                    cursor: 'pointer',
                    transition: 'all 0.15s ease',
                  }}
                >
                  {/* Top Row: Badge + Full Title & Date + Mark read */}
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap', flex: 1, minWidth: 0 }}>
                      {isRecordOff ? (
                        <span style={{
                          fontSize: 9.5,
                          fontWeight: 800,
                          color: '#dc2626',
                          background: '#fee2e2',
                          borderRadius: 3,
                          padding: '1.5px 5.5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          REC OFF
                        </span>
                      ) : isRecordOn ? (
                        <span style={{
                          fontSize: 9.5,
                          fontWeight: 800,
                          color: '#15803d',
                          background: '#dcfce7',
                          borderRadius: 3,
                          padding: '1.5px 5.5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          REC ON
                        </span>
                      ) : isInactive ? (
                        <span style={{
                          fontSize: 9.5,
                          fontWeight: 800,
                          color: '#b45309',
                          background: '#fef3c7',
                          borderRadius: 3,
                          padding: '1.5px 5.5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          INACTIVE
                        </span>
                      ) : isLead ? (
                        <span style={{
                          fontSize: 9.5,
                          fontWeight: 800,
                          color: '#6d28d9',
                          background: '#ede9fe',
                          borderRadius: 3,
                          padding: '1.5px 5.5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          LEAD
                        </span>
                      ) : (
                        <span style={{
                          fontSize: 9.5,
                          fontWeight: 700,
                          color: '#2563eb',
                          background: '#dbeafe',
                          borderRadius: 3,
                          padding: '1.5px 5.5px',
                          flexShrink: 0
                        }}>
                          ALERT
                        </span>
                      )}
                      <strong style={{ fontSize: 12.5, fontWeight: 700, color: '#0f172a', lineHeight: 1.3 }}>
                        {notifTitle}
                      </strong>
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
                      <span style={{ fontSize: 10.5, color: '#94a3b8', whiteSpace: 'nowrap' }}>
                        {fmtTs(item.createdAt)}
                      </span>
                      {!item.isRead ? (
                        <span
                          style={{ fontSize: 10.5, color: '#2563eb', fontWeight: 600, cursor: 'pointer', whiteSpace: 'nowrap' }}
                          onClick={(e) => {
                            e.stopPropagation();
                            if (itemId) markNotificationAsRead(itemId);
                          }}
                        >
                          Mark read
                        </span>
                      ) : (
                        <span style={{ fontSize: 10, color: '#94a3b8', whiteSpace: 'nowrap' }}>✓</span>
                      )}
                      <span onClick={(event) => event.stopPropagation()}>
                        <Popconfirm
                          title="Delete this notification?"
                          okText="Delete"
                          okButtonProps={{ danger: true }}
                          onConfirm={() => itemId && deleteNotification(itemId)}
                        >
                          <Button
                            type="text"
                            danger
                            size="small"
                            icon={<Icon name="delete" />}
                            title="Delete notification"
                            aria-label="Delete notification"
                          />
                        </Popconfirm>
                      </span>
                    </div>
                  </div>

                  {/* Row 2: Message with compact inline caller chip */}
                  <div style={{ fontSize: 11.5, color: '#334155', lineHeight: 1.4, marginTop: 4, wordBreak: 'break-word' }}>
                    {callerDisplayName && (
                      <span style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 3,
                        fontSize: 10.5,
                        fontWeight: 600,
                        color: '#1e293b',
                        background: '#f1f5f9',
                        border: '1px solid #e2e8f0',
                        borderRadius: 4,
                        padding: '1px 5px',
                        marginRight: 6,
                        verticalAlign: 'baseline',
                      }}>
                        <span style={{ fontSize: 10 }}>👤</span>
                        <span style={{ textTransform: 'capitalize' }}>
                          {roleLabel(item.senderRole || 'caller')}: <strong>{callerDisplayName}</strong>
                        </span>
                      </span>
                    )}
                    <span>{item.message}</span>
                  </div>

                  {/* Row 3: Comment / activity details */}
                  {item.comment && item.comment !== item.message && (
                    <div style={{ fontSize: 10.5, color: '#64748b', fontStyle: 'italic', marginTop: 3 }}>
                      ⏱️ {item.comment}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </Drawer>
    </>
  );
}

