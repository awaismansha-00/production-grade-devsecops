require('./tracing');

const express = require('express');
const bodyParser = require('body-parser');
const db = require('./config/db');
const cors = require('cors');
const path = require('path');
const promClient = require('prom-client');
const { context, trace } = require('@opentelemetry/api');

const app = express();
const port = process.env.PORT || 5000; // Use an environment variable for the port
const metricsRegister = new promClient.Registry();

promClient.collectDefaultMetrics({
  register: metricsRegister,
});

const httpRequestCounter = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [metricsRegister],
});

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [metricsRegister],
});

const getRouteLabel = (req) => {
  if (req.route && req.route.path) {
    return req.baseUrl ? `${req.baseUrl}${req.route.path}` : req.route.path;
  }
  if (req.path.startsWith('/api/users/')) {
    return '/api/users/:id';
  }
  return req.path;
};

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use((req, res, next) => {
  const start = process.hrtime.bigint();

  res.on('finish', () => {
    const durationSeconds = Number(process.hrtime.bigint() - start) / 1e9;
    const route = getRouteLabel(req);
    const statusCode = String(res.statusCode);
    const activeSpan = trace.getSpan(context.active());
    const spanContext = activeSpan && activeSpan.spanContext();
    const traceId = spanContext && spanContext.traceId;

    httpRequestCounter.inc({
      method: req.method,
      route,
      status_code: statusCode,
    });
    httpRequestDuration.observe({
      method: req.method,
      route,
      status_code: statusCode,
    }, durationSeconds);

    console.log(JSON.stringify({
      level: res.statusCode >= 500 ? 'error' : 'info',
      message: 'http_request',
      method: req.method,
      path: req.originalUrl,
      route,
      status_code: res.statusCode,
      duration_ms: Math.round(durationSeconds * 1000),
      trace_id: traceId,
    }));
  });

  next();
});

const createUsersTable = `
  CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    role ENUM('Admin', 'User') NOT NULL
  )
`;

db.query(createUsersTable, (err) => {
  if (err) {
    console.error('Failed to initialize users table:', err.stack);
    process.exit(1);
  }
  console.log('Database connected and users table initialized or already exists.');
});

// API Routes
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', metricsRegister.contentType);
  res.end(await metricsRegister.metrics());
});

app.get('/api/users', (req, res) => {
  db.query('SELECT * FROM users', (err, results) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(results);
  });
});

app.post('/api/users', (req, res) => {
  const { name, email, role } = req.body;
  db.query('INSERT INTO users (name, email, role) VALUES (?, ?, ?)', [name, email, role], (err, results) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(201).json({ id: results.insertId, name, email, role });
  });
});

app.put('/api/users/:id', (req, res) => {
  const { id } = req.params;
  const { name, email, role } = req.body;
  db.query('UPDATE users SET name = ?, email = ?, role = ? WHERE id = ?', [name, email, role, id], (err) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(200).json({ id, name, email, role });
  });
});

app.delete('/api/users/:id', (req, res) => {
  const { id } = req.params;
  db.query('DELETE FROM users WHERE id = ?', [id], (err) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(200).json({ message: 'User deleted successfully' });
  });
});

// Serve static files from the client/public directory
app.use(express.static(path.join(__dirname, '../client/public')));

// Serve index.html for all other routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../client/public', 'index.html'));
});

// Start server
app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});
