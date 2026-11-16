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

  const recordOffCount = useMemo(() => {
    return list.filter((n) => {
      const text = `${n.title || ''} ${n.message || ''}`.toLowerCase();
      return text.includes('auto-record') || text.includes('recording') || text.includes('record turned off');
    }).length;
  }, [list]);

  const filteredList = useMemo(() => {
    if (filter === 'recordOff') {
      return list.filter((n) => {
        const text = `${n.title || ''} ${n.message || ''}`.toLowerCase();
        return text.includes('auto-record') || text.includes('recording') || text.includes('record turned off');
      });
    }
    if (filter === 'unread') {
      return list.filter((n) => !n.isRead);
    }
    return list;
  }, [list, filter]);

  const isRecordOffNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('auto-record') || text.includes('recording') || text.includes('record turned off');
  };

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
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%', paddingRight: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="bell" />
              <span style={{ fontWeight: 700, fontSize: 16 }}>Notifications</span>
              {unreadCount > 0 && (
                <Tag color="red" style={{ borderRadius: 12, fontWeight: 700 }}>
                  {unreadCount} NEW
                </Tag>
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
              />
              {unreadCount > 0 && (
                <Button
                  type="link"
                  size="small"
                  style={{ padding: '0 4px', fontSize: 12, fontWeight: 600 }}
                  onClick={() => markAllNotificationsAsRead()}
                >
                  Mark all read
                </Button>
              )}
            </Space>
          </div>
        }
        placement="right"
        width={420}
        open={drawerOpen}
        onClose={() => dispatch(setNotificationsDrawer(false))}
        bodyStyle={{ padding: '12px 16px', background: '#f9fbf8' }}
      >
        <div style={{ marginBottom: 12 }}>
          <Segmented
            block
            value={filter}
            onChange={setFilter}
            options={[
              { label: `All (${list.length})`, value: 'all' },
              {
                label: (
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                    <span style={{ color: '#cf1322' }}>●</span> Recording Off ({recordOffCount})
                  </span>
                ),
                value: 'recordOff',
              },
              { label: `Unread (${unreadCount})`, value: 'unread' },
            ]}
          />
        </div>

        {pending && list.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '40px 0' }}>
            <Spin tip="Loading notifications..." />
          </div>
        ) : filteredList.length === 0 ? (
          <div style={{ padding: '40px 0', textAlign: 'center' }}>
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
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {filteredList.map((item) => {
              const itemId = item.id || item._id;
              const isRecordOff = isRecordOffNotification(item);

              return (
                <div
                  key={itemId || Math.random()}
                  onClick={() => {
                    if (!item.isRead && itemId) markNotificationAsRead(itemId);
                  }}
                  style={{
                    backgroundColor: item.isRead ? '#ffffff' : isRecordOff ? '#fff1f0' : '#f6ffed',
                    border: item.isRead ? '1px solid #e8e8e8' : isRecordOff ? '1px solid #ffa39e' : '1px solid #b7eb8f',
                    borderLeft: isRecordOff
                      ? '4px solid #ff4d4f'
                      : item.isRead
                      ? '4px solid #d9d9d9'
                      : '4px solid #52c41a',
                    borderRadius: 8,
                    padding: '12px 14px',
                    boxShadow: item.isRead ? 'none' : '0 2px 6px rgba(0,0,0,0.04)',
                    cursor: 'pointer',
                    transition: 'all 0.2s ease',
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 8, marginBottom: 4 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                      {isRecordOff ? (
                        <Tag color="error" style={{ fontWeight: 700, margin: 0, fontSize: 11, padding: '0 6px' }}>
                          ⚠️ RECORDING OFF
                        </Tag>
                      ) : (
                        <Tag color="green" style={{ fontWeight: 600, margin: 0, fontSize: 11, padding: '0 6px' }}>
                          NOTIFICATION
                        </Tag>
                      )}
                      <strong style={{ fontSize: 13, color: '#162410' }}>
                        {item.title || (isRecordOff ? 'Auto-Record Turned OFF' : 'System Alert')}
                      </strong>
                    </div>

                    <span style={{ fontSize: 11, color: '#8c8c8c', whiteSpace: 'nowrap' }}>
                      {fmtTs(item.createdAt)}
                    </span>
                  </div>

                  <div style={{ fontSize: 13, color: '#262626', lineHeight: 1.45, marginTop: 4 }}>
                    {item.message}
                  </div>

                  {item.comment && (
                    <div style={{ fontSize: 11, color: '#8c8c8c', marginTop: 4, fontStyle: 'italic' }}>
                      {item.comment}
                    </div>
                  )}

                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 8, paddingTop: 6, borderTop: '1px dashed #f0f0f0' }}>
                    <span style={{ fontSize: 11, color: '#595959' }}>
                      {item.senderName ? `Caller: ${item.senderName}` : 'System Alert'}
                    </span>
                    {!item.isRead ? (
                      <Button
                        type="link"
                        size="small"
                        style={{ padding: 0, height: 'auto', fontSize: 11, color: '#1890ff' }}
                        onClick={(e) => {
                          e.stopPropagation();
                          if (itemId) markNotificationAsRead(itemId);
                        }}
                      >
                        Mark as read
                      </Button>
                    ) : (
                      <span style={{ fontSize: 11, color: '#bfbfbf' }}>Read</span>
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

