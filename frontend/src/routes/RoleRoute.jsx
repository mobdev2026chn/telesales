// Pages only some roles may open: users (admin, manager), demos (everyone but callers) and
// health (admin, manager, junior manager, team leader).
// Uses the active view, so "view as" a caller also hides them — anyone else goes to the dashboard.
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { PATHS } from '../data/navigation';
import { selectScope } from '../redux/selectors';
import { canSeeDemosTab, canSeePhoneHealthTab, canSeeUsersTab } from '../utils/scope';

const GUARDS = { users: canSeeUsersTab, demos: canSeeDemosTab, health: canSeePhoneHealthTab };

export default function RoleRoute({ guard, children }) {
  const { me } = useSelector(selectScope);
  const allowed = GUARDS[guard] ? GUARDS[guard](me) : true;
  return allowed ? children : <Navigate to={PATHS.dash} replace />;
}
