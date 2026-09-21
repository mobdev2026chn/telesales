// Repairs call times stored 5 h 30 min too late.
//
// Older app builds sent the phone's India wall-clock time without a time zone; the server (UTC)
// stored e.g. a 12:22 PM call as 5:52 PM. Such a row is recognisable: its call time lies AFTER the
// moment the server received it (createdAt), by at most 5 h 30 min. Each one is moved back by
// 5 h 30 min. If the same call was also stored with the correct time, the late copy is removed.
//
//   node scripts/fix_shifted_call_times.js                 -> dry run: report only, changes nothing
//   node scripts/fix_shifted_call_times.js --apply --yes   -> fix the rows
//
// The database comes ONLY from MONGODB_URI (backend/.env or the environment); nothing is hard-coded.
// Take a backup first.
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
require('dns').setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);
const mongoose = require('mongoose');
const CallLog = require('../src/models/CallLog');
const { buildDedupKey, buildDedupKeyById } = require('../src/services/matching');

const APPLY = process.argv.includes('--apply');
const CONFIRMED = process.argv.includes('--yes');
const SHIFT_MS = 330 * 60 * 1000;
const SLACK_MS = 60 * 1000; // device and server clocks differ slightly

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
  console.log(`Database: ${redacted}${APPLY ? '  (APPLY MODE)' : '  (dry run)'}`);
  await mongoose.connect(uri);

  const rows = await CallLog.find({ createdAt: { $type: 'date' } })
    .select('callerId callerPhone phoneNumber timestamp createdAt recordingId recordingUrl dedupKey').lean();
  const shifted = rows.filter(r => {
    if (!r.timestamp || !r.createdAt) return false;
    const ahead = new Date(r.timestamp).getTime() - new Date(r.createdAt).getTime();
    return ahead > SLACK_MS && ahead <= SHIFT_MS + SLACK_MS;
  });
  console.log(`Rows checked: ${rows.length}. Stored 5h30m late: ${shifted.length}.`);

  let moved = 0;
  let removed = 0;
  for (const r of shifted) {
    const fixedTs = new Date(new Date(r.timestamp).getTime() - SHIFT_MS);
    const key = r.callerId ? buildDedupKeyById(r.callerId, r.phoneNumber, fixedTs) : buildDedupKey(r.callerPhone, r.phoneNumber, fixedTs);
    const twin = await CallLog.findOne({
      _id: { $ne: r._id },
      $or: [
        { dedupKey: key },
        { phoneNumber: r.phoneNumber, timestamp: fixedTs, $or: [{ callerId: r.callerId || '__none__' }, { callerPhone: r.callerPhone || '__none__' }] },
      ],
    }).select('_id recordingId').lean();
    console.log(`  ${r._id}  ${new Date(r.timestamp).toISOString()} -> ${fixedTs.toISOString()}${twin ? '  (correct copy exists: remove this one)' : ''}`);
    if (!APPLY) continue;
    if (twin) {
      if (!twin.recordingId && r.recordingId) {
        await CallLog.updateOne({ _id: twin._id }, { $set: { recordingId: r.recordingId, recordingUrl: r.recordingUrl || '' } });
      }
      await CallLog.deleteOne({ _id: r._id });
      removed++;
    } else {
      await CallLog.updateOne({ _id: r._id }, { $set: { timestamp: fixedTs, dedupKey: key } });
      moved++;
    }
  }
  console.log(APPLY ? `Done. Times corrected: ${moved}. Late duplicates removed: ${removed}.` : 'Dry run only: nothing changed. Re-run with --apply --yes to fix.');
  await mongoose.disconnect();
})().catch(err => {
  console.error(err);
  process.exit(1);
});
