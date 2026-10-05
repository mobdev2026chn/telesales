// Copies the recordings still missing locally (by _id), then their indexes.
const fs = require('fs');
const { MongoClient } = require('mongodb');
const ATLAS = fs.readFileSync('.env', 'utf8').match(/^#\s*MONGODB_URI=(mongodb\+srv:\S+)/m)[1];
(async () => {
  const src = await MongoClient.connect(ATLAS), dst = await MongoClient.connect('mongodb://127.0.0.1:27017');
  const s = src.db('telesales_db').collection('recordings'), d = dst.db('telesales_db').collection('recordings');
  const have = (await d.find({}, { projection: { _id: 1 } }).toArray()).map(x => x._id);
  let n = 0;
  for await (const doc of s.find({ _id: { $nin: have } }, { batchSize: 10 })) {
    await d.insertOne(doc).catch(e => { if (e.code !== 11000) throw e; });
    if (++n % 50 === 0) console.log(`recordings copied: ${have.length + n}`);
  }
  for (const ix of await s.indexes()) {
    if (ix.name === '_id_') continue;
    const { key, v, ns, ...opts } = ix;
    await d.createIndex(key, opts).catch(e => console.warn(`index ${ix.name}: ${e.message}`));
  }
  console.log(`RECORDINGS DONE: ${await d.countDocuments()} total`);
  await src.close(); await dst.close();
})().catch(e => { console.error('FAILED', e.message); process.exit(1); });
