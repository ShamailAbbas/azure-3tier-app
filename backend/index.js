require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const { DefaultAzureCredential } = require("@azure/identity");
const { SecretClient } = require("@azure/keyvault-secrets");

const app = express();
app.use(cors());
app.use(express.json());

const keyVaultName = process.env.KEY_VAULT_NAME;
const secretName = process.env.SECRET_NAME;
const kvUri = `https://${keyVaultName}.vault.azure.net`;

let appConfig = {};
let pool;

// --- Fetch DB credentials from Azure Key Vault ---
async function getSecret() {
  try {
    console.log("Fetching secrets from Azure Key Vault...");
    const credential = new DefaultAzureCredential();
    const client = new SecretClient(kvUri, credential);

    const secret = await client.getSecret(secretName);
    appConfig = JSON.parse(secret.value);

    console.log("✅ Secrets successfully loaded from Key Vault");
  } catch (error) {
    console.error("❌ Failed to load secrets from Key Vault:", error.message);
    throw error;
  }
}

// --- Initialize Database ---
async function initDB() {
  try {
    await getSecret();

    console.log("Connecting to MySQL with config:", {
      host: appConfig.DB_HOST,
      user: appConfig.DB_USER,
      database: appConfig.DB_NAME
    });

    pool = mysql.createPool({
      host: appConfig.DB_HOST,
      user: appConfig.DB_USER,
      password: appConfig.DB_PASSWORD,
      database: appConfig.DB_NAME,
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
      ssl: {
        rejectUnauthorized: true, // Set false if using self-signed certs
      },
    });

    const connection = await pool.getConnection();
    await connection.query(`
      CREATE TABLE IF NOT EXISTS items (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    connection.release();

    console.log("✅ Database initialized successfully");
  } catch (err) {
    console.error("❌ Database initialization failed:", err);
    process.exit(1); // Stop app if DB init fails
  }
}

// --- Health Check ---
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// --- Get all items ---
app.get('/api/items', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM items ORDER BY created_at DESC');
    res.json(rows);
  } catch (err) {
    console.error('❌ Error fetching items:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// --- Create item ---
app.post('/api/items', async (req, res) => {
  try {
    const { name, description } = req.body;
    const [result] = await pool.query(
      'INSERT INTO items (name, description) VALUES (?, ?)',
      [name, description]
    );
    res.status(201).json({ id: result.insertId, name, description });
  } catch (err) {
    console.error('❌ Error creating item:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// --- Delete item ---
app.delete('/api/items/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM items WHERE id = ?', [req.params.id]);
    res.json({ message: 'Deleted' });
  } catch (err) {
    console.error('❌ Error deleting item:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// --- Seed sample items ---
app.post('/seed', async (req, res) => {
  try {
    const seedItems = [
      { name: 'Post A', description: 'This is the first Post.' },
      { name: 'Post B', description: 'This is the second Post.' },
      { name: 'Post C', description: 'This is the third Post.' },
    ];

    const insertPromises = seedItems.map(item =>
      pool.query('INSERT INTO items (name, description) VALUES (?, ?)', [
        item.name,
        item.description,
      ])
    );

    await Promise.all(insertPromises);

    res.json({ message: '✅ Database seeded with sample items' });
  } catch (err) {
    console.error('❌ Seed error:', err);
    res.status(500).json({ error: 'Database seed error' });
  }
});

// --- Start server after DB init ---
const PORT = process.env.PORT || 3000;

(async () => {
  await initDB();
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
  });
})();
