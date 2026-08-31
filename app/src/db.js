const { Pool } = require('pg');

// Connection settings are injected as environment variables by the ECS task
// definition, which in turn sources DB_USERNAME/DB_PASSWORD from AWS Secrets
// Manager (see terraform/ecs.tf). No credentials are hard-coded here.
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

async function checkDbConnection() {
  if (!process.env.DB_HOST) {
    // Allows the app / health checks to run in CI without a real database.
    return { ok: true, skipped: true };
  }
  const client = await pool.connect();
  try {
    await client.query('SELECT 1');
    return { ok: true };
  } finally {
    client.release();
  }
}

module.exports = { pool, checkDbConnection };
