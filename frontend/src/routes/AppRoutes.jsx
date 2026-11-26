// Every page of the signed-in portal, inside the main layout (sidebar + header)
import { Navigate, Route, Routes } from 'react-router-dom';
import MainLayout from '../components/layout/MainLayout';
import CallLogPage from '../pages/CallLogPage';
import DashboardPage from '../pages/DashboardPage';
import DemoBookingsPage from '../pages/DemoBookingsPage';
import LeadCallingPage from '../pages/LeadCallingPage';
import LeaderboardPage from '../pages/LeaderboardPage';
import LeadsPipelinePage from '../pages/LeadsPipelinePage';
import NotificationsPage from '../pages/NotificationsPage';
import PhoneHealthPage from '../pages/PhoneHealthPage';
import ProfilePage from '../pages/ProfilePage';
import RecordingsPage from '../pages/RecordingsPage';
import UserDetailPage from '../pages/UserDetailPage';
import UserManagementPage from '../pages/UserManagementPage';
import RoleRoute from './RoleRoute';

export default function AppRoutes() {
  return (
    <Routes>
      <Route element={<MainLayout />}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<DashboardPage />} />
        <Route path="calls" element={<CallLogPage />} />
        <Route path="lead-calling" element={<LeadCallingPage />} />
        <Route path="users" element={<RoleRoute guard="users"><UserManagementPage /></RoleRoute>} />
        <Route path="leaderboard" element={<LeaderboardPage />} />
        <Route path="recordings" element={<RecordingsPage />} />
        <Route path="phone-health" element={<RoleRoute guard="health"><PhoneHealthPage /></RoleRoute>} />
        <Route path="leads" element={<LeadsPipelinePage />} />
        <Route path="demos" element={<RoleRoute guard="demos"><DemoBookingsPage /></RoleRoute>} />
        <Route path="notifications" element={<NotificationsPage />} />
        <Route path="profile" element={<ProfilePage />} />
        <Route path="user/:id" element={<UserDetailPage />} />
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Route>
    </Routes>
  );
}
