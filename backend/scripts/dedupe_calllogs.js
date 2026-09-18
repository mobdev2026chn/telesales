// Removes duplicate CallLog rows (same caller + dialled number + exact timestamp) and
// back-fills dedupKey on rows that have none, so the unique index blocks future duplicates.
//
//   node scripts/dedupe_calllogs.js                 -> dry run: report only, changes nothing
//   node scripts/dedupe_calllogs.js --apply --yes   -> delete duplicates and back-fill dedupKey
//
// The database comes ONLY from MONGODB_URI (backend/.env or the environment); nothing is hard-coded.
// Take a backup first: this permanently deletes rows.
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
require('dns').setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);
const mongoose = require('mongoose');
const CallLog = require('../src/models/CallLog');
const { buildDedupKey } = require('../src/services/matching');

const APPLY = process.argv.includes('--apply');
const CONFIRMED = process.argv.includes('--yes');

(async () => {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    console.error('MONGODB_URI is not set. Aborting.');
    process.exit(1);
  }
  if (APPLY && !CONFIRMED) {
    console.error('Refusing to modify the database without --yes. Run the dry run first, take a backup, then pass --apply --yes.');
    process.exit(1);
  }

  const redacted = uri.replace(/\/\/[^@/]*@/, '//***@');
  console.log(`Database: ${redacted}${APPLY ? '  (APPLY MODE — rows will be deleted)' : '  (dry run)'}`);

  await mongoose.connect(uri);
  const all = await CallLog.find({}).select('callerPhone callerName phoneNumber timestamp createdAt recordingUrl recordingId dedupKey').sort({ createdAt: 1 }).lean();

  const groups = new Map();
  for (const c of all) {
    const key = buildDedupKey(c.callerPhone, c.phoneNumber, c.timestamp);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(c);
  }

  const toDelete = [];
  const keepUpdates = [];
  const perCaller = {};
  for (const [key, rows] of groups) {
    // Keep the row that has a recording, otherwise the first one stored.
    const keep = rows.find(r => r.recordingId || r.recordingUrl) || rows[0];
    rows.filter(r => r !== keep).forEach(r => {
      toDelete.push(r._id);
      perCaller[r.callerName] = (perCaller[r.callerName] || 0) + 1;
    });
    // Only rows WITHOUT a key get one; existing (including id-based) keys are left alone
    if (!keep.dedupKey) keepUpdates.push({ _id: keep._id, dedupKey: key });
  }

  console.log(`Total rows:              ${all.length}`);
  console.log(`Real calls (unique):     ${groups.size}`);
  console.log(`Duplicate rows:          ${toDelete.length}`);
  console.log('Duplicates per caller:  ', perCaller);
  console.log(`Rows needing dedupKey:   ${keepUpdates.length}`);

  if (!APPLY) {
    console.log('\nDry run only. Re-run with --apply --yes to delete the duplicate rows and back-fill dedupKey.');
    await mongoose.disconnect();
    return;
  }

  const del = await CallLog.deleteMany({ _id: { $in: toDelete } });
  console.log(`\nDeleted ${del.deletedCount} duplicate rows.`);

  for (let i = 0; i < keepUpdates.length; i += 500) {
    const batch = keepUpdates.slice(i, i + 500);
    await CallLog.bulkWrite(batch.map(u => ({
      updateOne: { filter: { _id: u._id, dedupKey: { $exists: false } }, update: { $set: { dedupKey: u.dedupKey } } }
    })), { ordered: false });
  }
  console.log(`Back-filled dedupKey on ${keepUpdates.length} rows.`);

  await CallLog.createIndexes();
  console.log('Unique dedupKey index is in place.');
  await mongoose.disconnect();
})().catch(err => {
  console.error(err);
  process.exit(1);
});
