const mongoose = require('mongoose');
const dns = require('dns');

try {
  dns.setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);
} catch (_) {}

const LOCAL_URI = 'mongodb://127.0.0.1:27017/telesales_db';
const isProduction = () => String(process.env.NODE_ENV || '').toLowerCase() === 'production';
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// Production: MONGODB_URI is mandatory and there is NO fallback to a local database (writes would
// silently go to the wrong place). Connection is retried with backoff; after the last attempt the
// process exits so the process manager restarts it and the outage is visible.
// Development: falls back to a local MongoDB when MONGODB_URI is not set or unreachable.
const connectDB = async () => {
  const uri = process.env.MONGODB_URI;

  if (isProduction()) {
    if (!uri) {
      console.error('FATAL: MONGODB_URI is not set (NODE_ENV=production). Refusing to start.');
      process.exit(1);
    }
    const attempts = Math.max(1, parseInt(process.env.MONGODB_CONNECT_ATTEMPTS, 10) || 10);
    for (let i = 1; i <= attempts; i++) {
      try {
        const conn = await mongoose.connect(uri, { serverSelectionTimeoutMS: 10000 });
        console.log(`MongoDB connected: ${conn.connection.host}/${conn.connection.name}`);
        return true;
      } catch (error) {
        console.error(`MongoDB connection attempt ${i}/${attempts} failed: ${error.message}`);
        if (i < attempts) await sleep(Math.min(30000, 2000 * i));
      }
    }
    console.error('FATAL: could not connect to MongoDB. Exiting.');
    process.exit(1);
  }

  const target = uri || LOCAL_URI;
  try {
    const conn = await mongoose.connect(target, { serverSelectionTimeoutMS: 6000 });
    console.log(`MongoDB connected: ${conn.connection.host}/${conn.connection.name}`);
    return true;
  } catch (error) {
    console.warn(`MongoDB connection failed: ${error.message}`);
    if (target !== LOCAL_URI) {
      try {
        const localConn = await mongoose.connect(LOCAL_URI, { serverSelectionTimeoutMS: 3000 });
        console.warn(`DEVELOPMENT ONLY: using local MongoDB ${localConn.connection.host}/${localConn.connection.name}`);
        return true;
      } catch (localErr) {
        console.warn(`Local MongoDB fallback failed: ${localErr.message}`);
      }
    }
    return false;
  }
};

module.exports = connectDB;
