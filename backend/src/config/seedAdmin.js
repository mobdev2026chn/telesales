const Employee = require('../models/Employee');

const seedAdminUsers = async () => {
  try {
    const adminUser = {
      id: 'admin_1',
      name: 'Admin',
      email: 'admin@askeva.com',
      phone: '+91 98250 00000',
      password: 'admin123',
      role: 'admin',
      team: 'Management',
      totalCalls: 0,
      connectedCalls: 0,
      talkTimeSeconds: 0,
      dailyTarget: 150,
      managerId: '',
      managerName: '',
    };

    // Upsert Admin user and ensure only admin exists if fresh
    await Employee.findOneAndUpdate(
      { $or: [{ id: adminUser.id }, { email: adminUser.email }, { role: 'admin' }] },
      { $set: adminUser },
      { upsert: true, new: true }
    );
    console.log(`✅ Default Admin user synced to DB: ${adminUser.name} (${adminUser.email})`);
  } catch (err) {
    console.error('⚠️ Error seeding admin user:', err.message);
  }
};

module.exports = seedAdminUsers;
