import { useState, useMemo } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Badge, Button, Drawer, Empty, Segmented, Space, Spin, Tag, Tooltip } from '../../assets/antd';
import Icon from './Icon';
import { fmtTs } from '../../utils/format';
import { setNotificationsDrawer } from '../../redux/slices/notificationsSlice';
import {
  fetchNotifications,
  markNotificationAsRead,
  markAllNotificationsAsRead,
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
    return text.includes('turned on') || text.includes('re-enabled') || text.includes('enabled') || text.includes('record turned on');
  };

  const isInactivityNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('inactivity') || text.includes('inactive');
  };

  const isLeadNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('lead') || text.includes('follow') || text.includes('interest');
  };

  const recordOffCount = useMemo(() => {
    return list.filter((n) => isRecordOffNotification(n)).length;
  }, [list]);

  const filteredList = useMemo(() => {
    if (filter === 'recordOff') {
      return list.filter((n) => isRecordOffNotification(n));
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
            </Space>
          </div>
        }
        placement="right"
        width={360}
        open={drawerOpen}
        onClose={() => dispatch(setNotificationsDrawer(false))}
        bodyStyle={{ padding: '8px 12px', background: '#f8fafc' }}
      >
        <div style={{ marginBottom: 8 }}>
          <Segmented
            block
            size="small"
            value={filter}
            onChange={setFilter}
            options={[
              { label: `All (${list.length})`, value: 'all' },
              {
                label: (
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                    <span style={{ color: '#ef4444', fontSize: 10 }}>●</span> Recording Off ({recordOffCount})
                  </span>
                ),
                value: 'recordOff',
              },
              { label: `Unread (${unreadCount})`, value: 'unread' },
            ]}
          />
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
                  : filter === 'unread'
                  ? 'No unread notifications'
                  : 'No notifications yet'
              }
            />
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {filteredList.map((item) => {
              const itemId = item.id || item._id;
              const isRecordOff = isRecordOffNotification(item);
              const isRecordOn = isRecordOnNotification(item);
              const isInactive = isInactivityNotification(item);
              const isLead = isLeadNotification(item);

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
                ? '1px solid #f1f5f9'
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
                ? '#e2e8f0'
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
                    borderRadius: 6,
                    padding: '6px 10px',
                    cursor: 'pointer',
                    transition: 'all 0.15s ease',
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 6 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 5, minWidth: 0, overflow: 'hidden' }}>
                      {isRecordOff ? (
                        <span style={{
                          fontSize: 9,
                          fontWeight: 800,
                          color: '#dc2626',
                          background: '#fee2e2',
                          borderRadius: 3,
                          padding: '1px 5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          REC OFF
                        </span>
                      ) : isRecordOn ? (
                        <span style={{
                          fontSize: 9,
                          fontWeight: 800,
                          color: '#15803d',
                          background: '#dcfce7',
                          borderRadius: 3,
                          padding: '1px 5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          REC ON
                        </span>
                      ) : isInactive ? (
                        <span style={{
                          fontSize: 9,
                          fontWeight: 800,
                          color: '#b45309',
                          background: '#fef3c7',
                          borderRadius: 3,
                          padding: '1px 5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          INACTIVE
                        </span>
                      ) : isLead ? (
                        <span style={{
                          fontSize: 9,
                          fontWeight: 800,
                          color: '#6d28d9',
                          background: '#ede9fe',
                          borderRadius: 3,
                          padding: '1px 5px',
                          letterSpacing: '0.02em',
                          flexShrink: 0
                        }}>
                          LEAD
                        </span>
                      ) : (
                        <span style={{
                          fontSize: 9,
                          fontWeight: 700,
                          color: '#2563eb',
                          background: '#dbeafe',
                          borderRadius: 3,
                          padding: '1px 5px',
                          flexShrink: 0
                        }}>
                          ALERT
                        </span>
                      )}
                      <strong style={{ fontSize: 11.5, color: '#0f172a', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        {item.senderName ? `${item.senderName}` : item.title || 'System Alert'}
                      </strong>
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
                      <span style={{ fontSize: 10, color: '#94a3b8' }}>
                        {fmtTs(item.createdAt)}
                      </span>
                      {!item.isRead ? (
                        <span
                          style={{ fontSize: 10, color: '#2563eb', fontWeight: 600, cursor: 'pointer' }}
                          onClick={(e) => {
                            e.stopPropagation();
                            if (itemId) markNotificationAsRead(itemId);
                          }}
                        >
                          Mark read
                        </span>
                      ) : (
                        <span style={{ fontSize: 9.5, color: '#cbd5e1' }}>✓</span>
                      )}
                    </div>
                  </div>

                  <div style={{ fontSize: 11, color: '#475569', lineHeight: 1.35, marginTop: 3, wordBreak: 'break-word' }}>
                    {item.message}
                    {item.comment && item.comment !== item.message && (
                      <span style={{ fontSize: 10, color: '#94a3b8', fontStyle: 'italic', marginLeft: 4 }}>
                        • {item.comment}
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Drawer>
    </>
  );
}

