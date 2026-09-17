const fs = require("node:fs");
const { Pool } = require("pg");
const { Signer } = require("@aws-sdk/rds-signer");
const iam = process.env.DB_AUTH === "iam";
const signer = iam ? new Signer({ region: process.env.AWS_REGION, hostname: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432), username: process.env.DB_USER }) : null;
const pool = new Pool({
  host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME, user: process.env.DB_USER,
  password: iam ? () => signer.getAuthToken() : process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === "true" ? {
    rejectUnauthorized: true, ca: fs.readFileSync(process.env.DB_CA_FILE, "utf8")
  } : undefined,
  max: 5, connectionTimeoutMillis: 5000, idleTimeoutMillis: 30000,
  statement_timeout: 5000
});
pool.on("error", error => console.error(JSON.stringify({ event: "db_pool_error", code: error.code })));
async function initializeDatabase() {
  if (iam) { await pool.query("SELECT 1 FROM customers LIMIT 1"); return; }
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(842091)");
    await client.query(`CREATE TABLE IF NOT EXISTS customers (
      id SERIAL PRIMARY KEY, name VARCHAR(120) NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL, created_at TIMESTAMPTZ DEFAULT NOW())`);
    await client.query("COMMIT");
  } catch (error) { await client.query("ROLLBACK"); throw error; }
  finally { client.release(); }
}
module.exports = { pool, initializeDatabase };
