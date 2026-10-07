const { verifySocketToken, MANAGERS } = require('../middleware/auth');
const Employee = require('../models/Employee');
const presence = require('./presence');
const { exactNameRegex, isObjectId } = require('../utils/common');

const activeSockets = new Map();

function employeeRoom(id) {
  return `employee:${id}`;
}

function scopeRoom(id) {
  return `scope:${id}`;
}

async function managerRooms(employee) {
  const rooms = new Set();
  let managerId = employee.managerId || '';
  let managerName = employee.managerName || '';
  const visited = new Set([employee.id]);

  for (let depth = 0; depth < 10 && (managerId || managerName); depth += 1) {
    const refs = [];
    if (managerId) {
      refs.push({ id: managerId });
      if (isObjectId(managerId)) refs.push({ _id: managerId });
    }
    if (managerName) refs.push({ name: exactNameRegex(managerName) });
    const manager = await Employee.findOne({ $or: refs })
      .select('id managerId managerName')
      .lean();
    if (!manager || !manager.id || visited.has(manager.id)) break;
    visited.add(manager.id);
    rooms.add(scopeRoom(manager.id));
    managerId = manager.managerId || '';
    managerName = manager.managerName || '';
  }
  return rooms;
}

function initializeRealtime(io) {
  io.use(async (socket, next) => {
    let user;
    try {
      user = await verifySocketToken(socket.handshake.auth && socket.handshake.auth.token);
    } catch (err) {
      next(new Error(err.message === 'Authentication required' ? err.message : 'Invalid or expired authentication token'));
      return;
    }

    const rooms = new Set([employeeRoom(user.id)]);
    if (user.role === 'admin') rooms.add('admin:global');
    if (MANAGERS.includes(user.role)) rooms.add(scopeRoom(user.id));
    try {
      for (const room of rooms) {
        await socket.join(room);
        console.info(`[socket] joined room=${room} userId=${user.id}`);
      }
      socket.data.user = user;
      next();
    } catch (err) {
      console.error(`[socket] room initialization failed userId=${user.id}: ${err.message}`);
      next(new Error('Could not initialize authorized socket rooms'));
    }
  });

  io.on('connection', async (socket) => {
    const user = socket.data.user;
    let tracked = false;
    socket.on('disconnect', async () => {
      if (!tracked) return;
      const userSockets = activeSockets.get(user.id);
      if (!userSockets) return;
      userSockets.delete(socket.id);
      console.info(`[socket] disconnected userId=${user.id} socketId=${socket.id}`);
      if (userSockets.size > 0) return;
      activeSockets.delete(user.id);
      try {
        await presence.socketDisconnected(user.id);
        await emitToEmployee(io, user, 'employeeOffline', {
          userId: user.id,
          status: 'offline',
          lastSeenAt: new Date().toISOString(),
        });
      } catch (err) {
        console.error(`[socket] disconnect presence update failed userId=${user.id}: ${err.message}`);
      }
    });
    try {
      if (!socket.connected) return;

      let userSockets = activeSockets.get(user.id);
      const wasOffline = !userSockets || userSockets.size === 0;
      if (!userSockets) {
        userSockets = new Set();
        activeSockets.set(user.id, userSockets);
      }
      userSockets.add(socket.id);
      tracked = true;
      await presence.socketConnected(user.id);

      console.info(`[socket] connected userId=${user.id} role=${user.role} socketId=${socket.id}`);
      console.info(`[socket] authenticated userId=${user.id} role=${user.role}`);
      if (wasOffline && socket.connected) {
        const payload = { userId: user.id, status: 'online', lastSeenAt: new Date().toISOString() };
        await emitToEmployee(io, user, 'employeeOnline', payload);
      }
    } catch (err) {
      console.error(`[socket] connection setup failed userId=${user.id}: ${err.message}`);
      socket.disconnect(true);
      return;
    }
  });
}

async function recipientRooms(employee, additionalEmployeeIds = []) {
  const rooms = new Set(['admin:global', employeeRoom(employee.id), scopeRoom(employee.id)]);
  for (const room of await managerRooms(employee)) rooms.add(room);
  for (const id of additionalEmployeeIds.filter(Boolean)) {
    const additional = await Employee.findOne({ id: String(id) })
      .select('id managerId managerName')
      .lean();
    if (!additional) continue;
    rooms.add(employeeRoom(additional.id));
    for (const room of await managerRooms(additional)) rooms.add(room);
  }
  return rooms;
}

async function emitEvents(io, employee, events, additionalEmployeeIds = []) {
  if (!io) throw new Error('Socket.IO server is not available');
  if (events.length === 0) return;
  const rooms = await recipientRooms(employee, additionalEmployeeIds);
  const targets = [...rooms];
  for (const { event, payload } of events) io.to(targets).emit(event, payload);
  if (events.length === 1) {
    const { event, payload } = events[0];
    console.info(`[socket] emitted event=${event} rooms=${targets.join(',')} id=${payload.id || payload.leadId || payload.demo?.id || payload.userId || ''}`);
  } else {
    console.info(`[socket] emitted events=${[...new Set(events.map(item => item.event))].join(',')} count=${events.length} rooms=${targets.join(',')}`);
  }
}

async function emitToEmployee(io, employee, event, payload, additionalEmployeeIds = []) {
  return emitEvents(io, employee, [{ event, payload }], additionalEmployeeIds);
}

function publishForEmployee(req, employee, event, payload, additionalEmployeeIds = []) {
  return emitToEmployee(req.app.get('io'), employee, event, payload, additionalEmployeeIds);
}

function publishEventsForEmployee(req, employee, events, additionalEmployeeIds = []) {
  return emitEvents(req.app.get('io'), employee, events, additionalEmployeeIds);
}

function refreshEmployeeSocket(io, employeeId) {
  if (!io) throw new Error('Socket.IO server is not available');
  io.in(employeeRoom(String(employeeId))).disconnectSockets(true);
}

module.exports = {
  initializeRealtime,
  publishForEmployee,
  publishEventsForEmployee,
  refreshEmployeeSocket,
};
