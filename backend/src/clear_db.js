const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const uri = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/telesales_db';

async function clearDummyData() {
  await mongoose.connect(uri);
  console.log('Connected to MongoDB for clearing dummy data...');

  const db = mongoose.connection.db;
  const collections = await db.listCollections().toArray();
  for (const col of collections) {
    await db.collection(col.name).deleteMany({});
    console.log(`🧹 Cleared all documents from collection: ${col.name}`);
  }

  console.log('✅ All dummy seed data permanently removed from MongoDB!');
  process.exit(0);
}

clearDummyData().catch(err => {
  console.error('Error clearing data:', err);
  process.exit(1);
});
