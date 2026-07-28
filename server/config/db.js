const mysql = require('mysql');

const requiredVars = ['DB_HOST', 'DB_USER', 'DB_PASSWORD', 'DB_NAME'];

if (process.env.NODE_ENV === 'production') {
  for (const key of requiredVars) {
    if (!process.env[key]) {
      throw new Error(`Missing required environment variable: ${key}`);
    }
  }
}

const db = mysql.createPool({
  connectionLimit: Number(process.env.DB_CONNECTION_LIMIT || 10),
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'appuser',
  password: process.env.DB_PASSWORD || 'password123',
  database: process.env.DB_NAME || 'test_db',
});

module.exports = db;