const Employee = require('../models/Employee');

const seedAdminUsers = async () => {
  try {
    const defaultUsers = [
      {
        id: 'u0',
        name: 'Admin',
        email: 'admin@askeva.com',
        phone: '+91 98250 00000',
        password: 'admin123',
        role: 'admin',
        team: 'Management',
        dailyTarget: 150,
      },
      {
        id: 'm1',
        name: 'Arjun Rao',
        email: 'arjun@askeva.com',
        phone: '+91 98430 11224',
        password: 'admin123',
        role: 'manager',
        team: 'Management',
        dailyTarget: 0,
      },
      {
        id: 'm2',
        name: 'Divya Menon',
        email: 'divya@askeva.com',
        phone: '+91 95660 44771',
        password: 'admin123',
        role: 'manager',
        team: 'Management',
        dailyTarget: 0,
      },
      {
        id: 'm3',
        name: 'Karthik Iyer',
        email: 'karthik@askeva.com',
        phone: '+91 89396 55210',
        password: 'admin123',
        role: 'manager',
        team: 'Management',
        managerId: 'm1',
        managerName: 'Arjun Rao',
        dailyTarget: 0,
      },
      {
        id: 'u1',
        name: 'Mukhil',
        email: 'mukhil@askeva.com',
        phone: '+91 82483 99615',
        password: '123456',
        role: 'caller',
        team: 'Telesales Team',
        managerId: 'm1',
        managerName: 'Arjun Rao',
        dailyTarget: 40,
      },
      {
        id: 'u2',
        name: 'Nisha',
        email: 'hairunnisha0513@gmail.com',
        phone: '+91 77084 95812',
        password: '123456',
        role: 'caller',
        team: 'Telesales Team',
        managerId: 'm1',
        managerName: 'Arjun Rao',
        dailyTarget: 40,
      },
      {
        id: 'u3',
        name: 'Priyanka Panchal',
        email: 'priyanka@askeva.com',
        phone: '+91 90031 22876',
        password: '123456',
        role: 'caller',
        team: 'Telesales Team',
        managerId: 'm2',
        managerName: 'Divya Menon',
        dailyTarget: 35,
      },
      {
        id: 'u4',
        name: 'Sanjay Kumar',
        email: 'sanjay@askeva.com',
        phone: '+91 93810 44662',
        password: '123456',
        role: 'caller',
        team: 'Telesales Team',
        managerId: 'm3',
        managerName: 'Karthik Iyer',
        dailyTarget: 30,
      },
    ];

    for (const u of defaultUsers) {
      await Employee.findOneAndUpdate(
        { $or: [{ id: u.id }, { email: u.email }, { phone: u.phone }, { name: u.name }] },
        { $set: u },
        { upsert: true, new: true }
      );
    }
    console.log(`✅ Default Users synced to DB (${defaultUsers.length} accounts): Admin, Managers & Callers`);
  } catch (err) {
    console.error('⚠️ Error seeding initial users:', err.message);
  }
};

module.exports = seedAdminUsers;
