const express = require("express");
require("dotenv").config();

const { pool, initializeDatabase } = require("./db");

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "16kb" }));
app.use((req, res, next) => {
  const start = performance.now();
  res.on("finish", () => console.log(JSON.stringify({
    event: "request", method: req.method, path: req.path,
    status: res.statusCode, duration_ms: Math.round(performance.now() - start)
  })));
  next();
});

const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.json({
    service: "CloudLift API",
    status: "running"
  });
});

app.get("/health", async (req, res) => {
  try {
    await pool.query("SELECT 1");

    res.status(200).json({
      status: "healthy",
      database: "connected"
    });
  } catch (error) {
    res.status(503).json({
      status: "unhealthy",
      database: "disconnected"
    });
  }
});

app.get("/api/customers", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM customers ORDER BY id LIMIT 100"
    );

    res.json(result.rows);
  } catch (error) {
    console.error(JSON.stringify({ event: "query_failed", code: error.code }));
    res.status(500).json({
      error: "Unable to retrieve customers"
    });
  }
});

app.post("/api/customers", async (req, res) => {
  const { name, email } = req.body;

  if (typeof name !== "string" || typeof email !== "string" ||
      !name.trim() || name.length > 120 || email.length > 255 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({
      error: "name and email are required"
    });
  }

  try {
    const result = await pool.query(
      "INSERT INTO customers (name, email) VALUES ($1, $2) RETURNING *",
      [name, email]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    if (error.code === "23505") {
      return res.status(409).json({
        error: "Customer email already exists"
      });
    }

    console.error(JSON.stringify({ event: "query_failed", code: error.code }));

    res.status(500).json({
      error: "Unable to create customer"
    });
  }
});

app.get("/api/stats", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT COUNT(*)::int AS customer_count FROM customers"
    );

    res.json(result.rows[0]);
  } catch (error) {
    console.error(JSON.stringify({ event: "query_failed", code: error.code }));

    res.status(500).json({
      error: "Unable to retrieve statistics"
    });
  }
});

async function startServer() {
  for (let attempt = 1; attempt <= 12; attempt++) {
    try { await initializeDatabase(); break; }
    catch (error) {
      if (attempt === 12) throw error;
      console.log(JSON.stringify({ event: "db_retry", attempt }));
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
  const server = app.listen(PORT, () => console.log(JSON.stringify({ event: "listening", port: PORT })));
  process.on("SIGTERM", () => {
    server.close(async () => { await pool.end(); process.exit(0); });
    setTimeout(() => process.exit(1), 25000).unref();
  });
}
startServer().catch(error => {
  console.error(JSON.stringify({ event: "startup_failed", code: error.code }));
  process.exit(1);
});
