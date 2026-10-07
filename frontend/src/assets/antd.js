// Every Ant Design piece the portal uses, imported once here so pages and components import from one place
// (same idea as assets/image.js). Also holds the theme and the icon-name → antd icon map behind <Icon name="…" />.
import {
  ApartmentOutlined, AimOutlined, ArrowDownOutlined, ArrowLeftOutlined, ArrowUpOutlined, BarChartOutlined, CalendarOutlined,
  CaretRightOutlined, CheckCircleOutlined, CheckOutlined, ClockCircleOutlined, CloseCircleOutlined, CloseOutlined,
  CloudUploadOutlined, CrownFilled, CustomerServiceOutlined, DashboardOutlined, DeleteOutlined, DownloadOutlined, DownOutlined,
  EditOutlined, EllipsisOutlined, ExclamationCircleOutlined, EyeOutlined, FileExcelOutlined, FileOutlined, FlagOutlined,
  FunnelPlotOutlined, HistoryOutlined, InboxOutlined, LeftOutlined, LineChartOutlined, LoginOutlined, LogoutOutlined,
  MenuOutlined, PauseOutlined, PhoneOutlined, PlayCircleOutlined, PlusOutlined, PushpinFilled, PushpinOutlined,
  RightOutlined, RiseOutlined, SaveOutlined, SearchOutlined, SendOutlined, SolutionOutlined, StarOutlined,
  StepBackwardOutlined, StepForwardOutlined, StopOutlined, SwapOutlined, TeamOutlined, TrophyOutlined, UnorderedListOutlined,
  UploadOutlined, UserOutlined,
} from '@ant-design/icons';

export {
  Alert, App as AntApp, Button, Col, ConfigProvider, DatePicker, Flex, Input, Rate, Row, Segmented, Select, Space, Tooltip,
} from 'antd';

// <Icon name="…" /> names (the old sprite names first, then the extra action icons)
export const ICONS = {
  activity: LineChartOutlined,
  alert: ExclamationCircleOutlined,
  award: TrophyOutlined,
  calendar: CalendarOutlined,
  chart: BarChartOutlined,
  check: CheckCircleOutlined,
  clock: ClockCircleOutlined,
  dashboard: DashboardOutlined,
  download: DownloadOutlined,
  file: FileOutlined,
  funnel: FunnelPlotOutlined,
  headphones: CustomerServiceOutlined,
  history: HistoryOutlined,
  in: ArrowDownOutlined,
  inbox: InboxOutlined,
  layers: ApartmentOutlined,
  list: UnorderedListOutlined,
  logout: LogoutOutlined,
  menu: MenuOutlined,
  missed: CloseCircleOutlined,
  out: ArrowUpOutlined,
  phone: PhoneOutlined,
  play: PlayCircleOutlined,
  plus: PlusOutlined,
  search: SearchOutlined,
  slash: StopOutlined,
  star: StarOutlined,
  target: AimOutlined,
  trend: RiseOutlined,
  upload: CloudUploadOutlined,
  'user-check': SolutionOutlined,
  users: TeamOutlined,
  x: CloseOutlined,
  // action icons
  back: ArrowLeftOutlined,
  'caret-right': CaretRightOutlined,
  'check-plain': CheckOutlined,
  crown: CrownFilled,
  delete: DeleteOutlined,
  down: DownOutlined,
  edit: EditOutlined,
  ellipsis: EllipsisOutlined,
  excel: FileExcelOutlined,
  eye: EyeOutlined,
  flag: FlagOutlined,
  left: LeftOutlined,
  login: LoginOutlined,
  pause: PauseOutlined,
  pin: PushpinOutlined,
  'pin-filled': PushpinFilled,
  right: RightOutlined,
  save: SaveOutlined,
  send: SendOutlined,
  'step-back': StepBackwardOutlined,
  'step-forward': StepForwardOutlined,
  swap: SwapOutlined,
  'upload-plain': UploadOutlined,
  user: UserOutlined,
};

// Inbound / outbound arrows point diagonally (↙ / ↗), like the old sprite; antd's handset is drawn
// mirrored, so it turns 90° to the usual call-icon pose (earpiece top-left)
export const ICON_ROTATE = { in: 45, out: 45, phone: 90 };

// Sidebar icon for each page (navigation.js `tab` keys)
export const NAV_ICONS = {
  dash: 'dashboard', calls: 'history', dial: 'phone', users: 'users', lb: 'award', recs: 'headphones', leads: 'funnel', demos: 'calendar',
};

// Theme: the same colours, type and radii as the :root tokens in styles/global.css
export const ANT_THEME = {
  token: {
    colorPrimary: '#3DC838',
    colorSuccess: '#3DC838',
    colorInfo: '#2E9E2B',
    colorWarning: '#D6972F',
    colorError: '#D0453A',
    colorLink: '#2E9E2B',
    colorText: '#10180C',
    colorTextSecondary: '#4A5243',
    colorTextTertiary: '#767D6E',
    colorTextPlaceholder: '#9A9F92',
    colorBorder: '#CDC9BB',
    colorBorderSecondary: '#E4E1D6',
    colorBgContainer: '#FFFFFF',
    colorBgLayout: '#F4F3EE',
    controlOutline: 'rgba(61, 200, 56, 0.22)',
    controlItemBgActive: '#F2FBD6',
    fontFamily: "'Archivo', system-ui, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif",
    fontSize: 13,
    borderRadius: 8,
    borderRadiusSM: 6,
    borderRadiusLG: 12,
    controlHeight: 36,
    controlHeightSM: 30,
    controlHeightLG: 42,
    // Pop-ups (select lists, date pickers, tooltips) open above the portal's own dialogs (z-index 9999)
    zIndexPopupBase: 10050,
  },
  components: {
    Button: { primaryColor: '#10180C', fontWeight: 600, primaryShadow: 'none', dangerShadow: 'none', defaultShadow: '0 1px 2px rgba(16, 24, 12, 0.05)' },
    Rate: { starColor: '#3DC838', starSize: 17 },
    Select: {
      optionSelectedBg: '#F2FBD6', optionSelectedFontWeight: 700, optionActiveBg: '#F7F6F1',
      optionPadding: '8px 12px', optionHeight: 36, selectorBg: '#FFFFFF', activeOutlineColor: 'rgba(61, 200, 56, 0.18)',
      hoverBorderColor: '#9FD98F', activeBorderColor: '#3DC838',
    },
    Segmented: { itemSelectedBg: '#FFFFFF', trackBg: '#F0EEE7' },
    DatePicker: {
      activeBorderColor: '#2E9E2B', hoverBorderColor: '#9FD98F', cellHeight: 30, cellWidth: 34, cellActiveWithRangeBg: '#F2FBD6',
      cellHoverBg: '#F2FBD6', textHeight: 36, withoutTimeCellHeight: 40,
    },
  },
};
