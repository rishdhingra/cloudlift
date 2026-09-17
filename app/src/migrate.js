const { pool, initializeDatabase } = require("./db");
(async () => {
  await initializeDatabase();
  await pool.query(`DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cloudlift_app') THEN
      CREATE ROLE cloudlift_app LOGIN;
    END IF;
  END $$`);
  await pool.query("GRANT rds_iam TO cloudlift_app");
  await pool.query("REVOKE CREATE ON SCHEMA public FROM PUBLIC");
  await pool.query("GRANT CONNECT ON DATABASE cloudlift TO cloudlift_app");
  await pool.query("GRANT USAGE ON SCHEMA public TO cloudlift_app");
  await pool.query("GRANT SELECT, INSERT ON customers TO cloudlift_app");
  await pool.query("GRANT USAGE, SELECT ON SEQUENCE customers_id_seq TO cloudlift_app");
  console.log(JSON.stringify({ event: "migration_complete" }));
})().catch(error => { console.error({ event: "migration_failed", code: error.code }); process.exitCode = 1; })
  .finally(() => pool.end());
