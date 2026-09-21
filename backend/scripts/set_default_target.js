// Moves every non-admin user still on the old default daily target (40) to the new default (250).
// Users an admin gave a different target (e.g. 300, 400) are not touched.
//
//   node scripts/set_default_target.js                 -> dry run: lists who would change
//   node scripts/set_default_target.js --apply --yes   -> updates them
//
// The database comes ONLY from MONGODB_URI (backend/.env or the environment).
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
require('dns').setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);
const mongoose = require('mongoose');
const Employee = require('../src/models/Employee');

const OLD_DEFAULT = 40;
const APPLY = process.argv.includes('--apply');
const CONFIRMED = process.argv.includes('--yes');

(async () => {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    console.error('MONGODB_URI is not set. Aborting.');
    process.exit(1);
  }
  if (APPLY && !CONFIRMED) {
    console.error('Refusing to modify the database without --yes. Run the dry run first, then pass --apply --yes.');
    process.exit(1);
  }
  const target = Employee.DEFAULT_DAILY_TARGET;
  await mongoose.connect(uri);
  const query = { role: { $ne: 'admin' }, $or: [{ dailyTarget: OLD_DEFAULT }, { dailyTarget: { $exists: false } }, { dailyTarget: null }] };
  const users = await Employee.find(query).select('id name role dailyTarget').lean();
  console.log(`Users on the old default target (${OLD_DEFAULT}): ${users.length}`);
  users.forEach(u => console.log(`  ${u.name} (${u.role}) ${u.dailyTarget ?? 'none'} -> ${target}`));
  if (APPLY && users.length) {
    const res = await Employee.updateMany(query, { $set: { dailyTarget: target } });
    console.log(`Updated ${res.modifiedCount} user(s) to ${target}.`);
  } else if (!APPLY) {
    console.log('Dry run only: nothing changed. Re-run with --apply --yes to update.');
  }
  await mongoose.disconnect();
})().catch(err => {
  console.error(err);
  process.exit(1);
});
