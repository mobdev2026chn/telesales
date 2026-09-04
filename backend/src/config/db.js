const mongoose = require('mongoose');
const dns = require('dns');

try {
  dns.setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);
} catch (_) {}

const connectDB = async () => {
  const uri = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/telesales_db';
  try {
    const conn = await mongoose.connect(uri, {
      serverSelectionTimeoutMS: 6000,
    });
    console.log(`✅ MongoDB Connected: ${conn.connection.host}/${conn.connection.name}`);
    return true;
  } catch (error) {
    console.warn(`⚠️ Primary MongoDB Connection Notice: ${error.message}`);
    if (!uri.includes('127.0.0.1') && !uri.includes('localhost')) {
      try {
        const localConn = await mongoose.connect('mongodb://127.0.0.1:27017/telesales_db', {
          serverSelectionTimeoutMS: 3000,
        });
        console.log(`✅ Local MongoDB Connected: ${localConn.connection.host}/${localConn.connection.name}`);
        return true;
      } catch (localErr) {
        console.warn(`⚠️ Local MongoDB fallback notice: ${localErr.message}`);
      }
    }
    console.log(`ℹ️ Server will continue operating with in-memory seed fallback.`);
    return false;
  }
};

module.exports = connectDB;
