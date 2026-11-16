import { useState, useMemo, useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { Button, Empty, Input, Segmented, Space, Spin, Tag, Tooltip } from '../assets/antd';
import PageHeader from '../components/common/PageHeader';
import Icon from '../components/common/Icon';
import { fmtTs, formatPhone } from '../utils/format';
import {
  fetchNotifications,
  markNotificationAsRead,
  markAllNotificationsAsRead,
} from '../utils/actions/notificationActions';

export default function NotificationsPage() {
  const dispatch = useDispatch();
  const { list = [], unreadCount = 0, pending = false } = useSelector(
    (s) => s.notifications || {}
  );

  const [filter, setFilter] = useState('all');
  const [search, setSearch] = useState('');

  useEffect(() => {
    fetchNotifications();
  }, []);

  // Compute counts
  const stats = useMemo(() => {
    let offCount = 0;
    let onCount = 0;
    list.forEach((n) => {
      const text = `${n.title || ''} ${n.message || ''}`.toLowerCase();
      if (text.includes('turned off') || text.includes('disabled')) {
        offCount += 1;
      } else if (text.includes('turned on') || text.includes('re-enabled') || text.includes('enabled')) {
        onCount += 1;
      }
    });
    return {
      total: list.length,
      offCount,
      onCount,
      unread: unreadCount,
    };
  }, [list, unreadCount]);

  const isOffNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('turned off') || text.includes('disabled');
  };

  const isOnNotification = (item) => {
    const text = `${item.title || ''} ${item.message || ''}`.toLowerCase();
    return text.includes('turned on') || text.includes('re-enabled') || text.includes('enabled');
  };

  const filteredList = useMemo(() => {
    return list.filter((item) => {
      // 1. Tab / filter
      if (filter === 'off' && !isOffNotification(item)) return false;
      if (filter === 'on' && !isOnNotification(item)) return false;
      if (filter === 'unread' && item.isRead) return false;

      // 2. Search keyword
      if (search.trim()) {
        const query = search.trim().toLowerCase();
        const combined = `${item.title || ''} ${item.message || ''} ${item.senderName || ''} ${item.comment || ''}`.toLowerCase();
        if (!combined.includes(query)) return false;
      }

      return true;
    });
  }, [list, filter, search]);

  return (
    <div className="tab-view active" id="tabNotifications">
      <PageHeader
        title="Notifications"
        subtitle="Real-time alerts, auto-recording toggles (turned OFF & turned ON), and caller activity log"
      >
        <Space size="middle">
          {unreadCount > 0 && (
            <Button
              onClick={() => markAllNotificationsAsRead()}
              icon={<Icon name="check" size="sm" />}
              style={{ fontWeight: 600, background: '#ffffff', color: '#10180C', borderColor: '#CDC9BB' }}
            >
              Mark all as read
            </Button>
          )}
          <Button
            onClick={() => fetchNotifications()}
            loading={pending}
            icon={<Icon name="history" size="sm" />}
            style={{ fontWeight: 600, background: '#ffffff', color: '#10180C', borderColor: '#CDC9BB' }}
          >
            Refresh
          </Button>
        </Space>
      </PageHeader>

      {/* KPI / Summary Cards */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
          gap: 16,
          marginBottom: 20,
        }}
      >
        <div
          className="card"
          style={{
            padding: '16px 20px',
            borderRadius: 10,
            background: '#ffffff',
            border: '1px solid #e4e1d6',
            boxShadow: '0 2px 6px rgba(0,0,0,0.03)',
          }}
        >
          <div style={{ fontSize: 12, fontWeight: 700, color: '#767D6E', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
            TOTAL ALERTS
          </div>
          <div style={{ fontSize: 28, fontWeight: 800, color: '#10180C', marginTop: 4 }}>
            {stats.total}
          </div>
          <div style={{ fontSize: 11, color: '#9A9F92', marginTop: 2 }}>
            All recorded notifications
          </div>
        </div>

        <div
          className="card"
          style={{
            padding: '16px 20px',
            borderRadius: 10,
            background: '#FFF1F0',
            border: '1px solid #FFA39E',
            boxShadow: '0 2px 6px rgba(207,19,34,0.06)',
          }}
        >
          <div style={{ fontSize: 12, fontWeight: 700, color: '#CF1322', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
            ⚠️ AUTO-RECORD TURNED OFF
          </div>
          <div style={{ fontSize: 28, fontWeight: 800, color: '#CF1322', marginTop: 4 }}>
            {stats.offCount}
          </div>
          <div style={{ fontSize: 11, color: '#A8071A', marginTop: 2 }}>
            Times callers disabled recording
          </div>
        </div>

        <div
          className="card"
          style={{
            padding: '16px 20px',
            borderRadius: 10,
            background: '#F6FFED',
            border: '1px solid #B7EB8F',
            boxShadow: '0 2px 6px rgba(56,158,13,0.06)',
          }}
        >
          <div style={{ fontSize: 12, fontWeight: 700, color: '#389E0D', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
            ✓ AUTO-RECORD TURNED ON
          </div>
          <div style={{ fontSize: 28, fontWeight: 800, color: '#389E0D', marginTop: 4 }}>
            {stats.onCount}
          </div>
          <div style={{ fontSize: 11, color: '#237804', marginTop: 2 }}>
            Times callers re-enabled recording
          </div>
        </div>

        <div
          className="card"
          style={{
            padding: '16px 20px',
            borderRadius: 10,
            background: '#ffffff',
            border: unreadCount > 0 ? '1px solid #FAAD14' : '1px solid #e4e1d6',
            boxShadow: '0 2px 6px rgba(0,0,0,0.03)',
          }}
        >
          <div style={{ fontSize: 12, fontWeight: 700, color: unreadCount > 0 ? '#D48806' : '#767D6E', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
            UNREAD ALERTS
          </div>
          <div style={{ fontSize: 28, fontWeight: 800, color: unreadCount > 0 ? '#D48806' : '#10180C', marginTop: 4 }}>
            {stats.unread}
          </div>
          <div style={{ fontSize: 11, color: '#9A9F92', marginTop: 2 }}>
            Awaiting acknowledgement
          </div>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 12,
          marginBottom: 16,
          background: '#ffffff',
          padding: '12px 16px',
          borderRadius: 8,
          border: '1px solid #e4e1d6',
        }}
      >
        <Segmented
          value={filter}
          onChange={setFilter}
          options={[
            { label: `All Alerts (${stats.total})`, value: 'all' },
            {
              label: (
                <span style={{ color: '#CF1322', fontWeight: 600 }}>
                  ● Recording OFF ({stats.offCount})
                </span>
              ),
              value: 'off',
            },
            {
              label: (
                <span style={{ color: '#389E0D', fontWeight: 600 }}>
                  ● Recording ON ({stats.onCount})
                </span>
              ),
              value: 'on',
            },
            { label: `Unread (${stats.unread})`, value: 'unread' },
          ]}
        />

        <div style={{ width: 280, maxWidth: '100%' }}>
          <Input
            placeholder="Search by caller, phone, or keyword..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            allowClear
            prefix={<Icon name="search" size="sm" />}
          />
        </div>
      </div>

      {/* Notifications List */}
      {pending && list.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '60px 0', background: '#ffffff', borderRadius: 8 }}>
          <Spin size="large" tip="Loading notifications..." />
        </div>
      ) : filteredList.length === 0 ? (
        <div style={{ padding: '60px 0', textAlign: 'center', background: '#ffffff', borderRadius: 8, border: '1px solid #e4e1d6' }}>
          <Empty
            image={Empty.PRESENTED_IMAGE_SIMPLE}
            description={
              filter === 'off'
                ? 'No Recording OFF alerts recorded yet'
                : filter === 'on'
                ? 'No Recording ON alerts recorded yet'
                : filter === 'unread'
                ? 'No unread alerts'
                : 'No notifications found'
            }
          />
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {filteredList.map((item) => {
            const itemId = item.id || item._id;
            const isOff = isOffNotification(item);
            const isOn = isOnNotification(item);

            return (
              <div
                key={itemId || Math.random()}
                style={{
                  background: item.isRead ? '#ffffff' : isOff ? '#FFF9F9' : isOn ? '#F9FFF5' : '#FCFCFA',
                  border: item.isRead ? '1px solid #E4E1D6' : isOff ? '1px solid #FFA39E' : isOn ? '1px solid #B7EB8F' : '1px solid #D9D9D9',
                  borderLeft: isOff
                    ? '5px solid #FF4D4F'
                    : isOn
                    ? '5px solid #52C41A'
                    : item.isRead
                    ? '5px solid #D9D9D9'
                    : '5px solid #1890FF',
                  borderRadius: 8,
                  padding: '16px 20px',
                  boxShadow: item.isRead ? 'none' : '0 2px 8px rgba(0,0,0,0.04)',
                  transition: 'all 0.2s ease',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    {isOff ? (
                      <Tag color="error" style={{ fontWeight: 800, fontSize: 12, padding: '2px 8px' }}>
                        🔴 AUTO-RECORD TURNED OFF
                      </Tag>
                    ) : isOn ? (
                      <Tag color="success" style={{ fontWeight: 800, fontSize: 12, padding: '2px 8px' }}>
                        🟢 AUTO-RECORD TURNED ON
                      </Tag>
                    ) : (
                      <Tag color="blue" style={{ fontWeight: 700, fontSize: 12, padding: '2px 8px' }}>
                        SYSTEM ALERT
                      </Tag>
                    )}

                    <strong style={{ fontSize: 14, color: '#10180C' }}>
                      {item.title || (isOff ? 'Auto-Record Turned OFF' : isOn ? 'Auto-Record Turned ON' : 'Notification')}
                    </strong>
                  </div>

                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ fontSize: 12, color: '#767D6E', fontWeight: 500 }}>
                      <Icon name="clock" size="sm" style={{ marginRight: 4 }} />
                      {fmtTs(item.createdAt)}
                    </span>
                    {!item.isRead ? (
                      <Button
                        type="link"
                        size="small"
                        onClick={() => itemId && markNotificationAsRead(itemId)}
                        style={{ padding: '0 4px', fontSize: 12, fontWeight: 600, color: '#1890FF' }}
                      >
                        Mark as read
                      </Button>
                    ) : (
                      <span style={{ fontSize: 11, color: '#9A9F92', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                        <Icon name="check" size="xs" /> Read
                      </span>
                    )}
                  </div>
                </div>

                <div style={{ fontSize: 13, color: '#262626', lineHeight: 1.5, marginTop: 8 }}>
                  {item.message}
                </div>

                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    flexWrap: 'wrap',
                    gap: 8,
                    marginTop: 12,
                    paddingTop: 8,
                    borderTop: '1px solid #F0EFE9',
                    fontSize: 12,
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <span style={{ color: '#587548', fontWeight: 600 }}>
                      Caller: <strong>{item.senderName || 'Unknown Caller'}</strong>
                    </span>
                    {item.senderPhone && (
                      <span style={{ color: '#767D6E' }}>
                        Phone: {formatPhone(item.senderPhone)}
                      </span>
                    )}
                  </div>

                  {item.comment && (
                    <div
                      style={{
                        color: isOff ? '#CF1322' : isOn ? '#389E0D' : '#595959',
                        fontWeight: 700,
                        fontSize: 12,
                        background: isOff ? '#FFF1F0' : isOn ? '#F6FFED' : '#F5F5F5',
                        padding: '2px 8px',
                        borderRadius: 4,
                      }}
                    >
                      {item.comment}
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
