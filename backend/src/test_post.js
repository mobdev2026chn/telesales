const http = require('http');

const data = JSON.stringify({
  callerName: 'Mukhil',
  contactName: 'Direct Test Client',
  phoneNumber: '+91 82483 99615',
  durationSeconds: 32,
  dateStr: 'Today',
  timeStr: '5:18 PM',
  fileName: 'DIRECT_TEST_RECORDING.m4a',
  transcript: 'Direct verified recording saved to MongoDB'
});

const req = http.request('http://localhost:5000/api/recordings', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': data.length
  }
}, (res) => {
  let body = '';
  res.on('data', chunk => body += chunk);
  res.on('end', () => {
    console.log('Server response:', res.statusCode, body);
    process.exit(0);
  });
});

req.on('error', (e) => {
  console.error('Request error:', e.message);
  process.exit(1);
});

req.write(data);
req.end();
