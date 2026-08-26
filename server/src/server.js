const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const connectDB = require('./config/db');
const apiRoutes = require('./routes/api');

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Middlewares
app.use(cors());
app.use(express.json());

// Database Connection
connectDB();

// API Routes
app.use('/api', apiRoutes);

// Health Check
app.get('/', (req, res) => {
  res.json({
    status: 'ONLINE',
    service: 'Telesales Monitoring Backend API',
    database: 'MongoDB',
    version: '1.0.0',
    endpoints: [
      'POST /api/calls/sync',
      'GET /api/dashboard/stats',
      'GET /api/employees/leaderboard',
      'GET /api/leads',
      'GET /api/recordings',
    ]
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Telesales Backend API running on http://0.0.0.0:${PORT}`);
});
