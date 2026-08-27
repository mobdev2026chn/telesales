const Employee = require('../models/Employee');

const seedAdminUsers = async () => {
  try {
    const adminCount = await Employee.countDocuments({ role: 'admin' });
    if (adminCount === 0) {
      console.log('🌱 No admin accounts found in DB. Seeding initial pre-configured Admin user...');
      const adminUser = await Employee.create({
        id: 'admin_1',
        name: 'Admin',
        email: 'admin@askeva.com',
        phone: '+91 98250 00000',
        password: 'admin123',
        role: 'admin',
        team: 'Management',
        dailyTarget: 150,
      });
      console.log(`✅ Default Admin user pre-seeded: ${adminUser.email} (${adminUser.name})`);
    }
  } catch (err) {
    console.error('⚠️ Error seeding initial Admin user:', err.message);
  }
};

module.exports = seedAdminUsers;
