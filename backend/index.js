require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');

const { DefaultAzureCredential } = require("@azure/identity");
const { SecretClient } = require("@azure/keyvault-secrets");

const keyVaultName = process.env.KEY_VAULT_NAME;
const secretName = process.env.SECRET_NAME;
const kvUri = `https://${keyVaultName}.vault.azure.net`;

let appConfig = {}

async function getSecret() {
  const credential = new DefaultAzureCredential();
  const client = new SecretClient(kvUri, credential);

  const secret = await client.getSecret(secretName);
  appConfig = JSON.parse(secret.value);

  console.log("appConfig:", appConfig);

}

let pool




const app = express();
app.use(cors());
app.use(express.json());



// Initialize database table
async function initDB() {
  try {

    await getSecret().then(() => {
  pool = mysql.createPool({
    host: appConfig.DB_HOST,
    user: appConfig.DB_USER,
    password: appConfig.DB_PASSWORD,
    database: appConfig.DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
    ssl: {
      // For production: validate certificate
      // If you face cert issues, set rejectUnauthorized: false temporarily
      rejectUnauthorized: true
    }
  });
}).catch(console.error);
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
    console.log('Database initialized');
  } catch (err) {
    console.error('Database init error:', err);
  }
}

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Get all items
app.get('/api/items', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM items ORDER BY created_at DESC');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Create item
app.post('/api/items', async (req, res) => {
  try {
    const { name, description } = req.body;
    const [result] = await pool.query(
      'INSERT INTO items (name, description) VALUES (?, ?)',
      [name, description]
    );
    res.status(201).json({ id: result.insertId, name, description });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Delete item
app.delete('/api/items/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM items WHERE id = ?', [req.params.id]);
    res.json({ message: 'Deleted' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Seed DB with some sample items
app.post('/seed', async (req, res) => {
  try {
    const seedItems = [
      { name: 'Item A', description: 'This is the first seeded item.' },
      { name: 'Item B', description: 'This is the second seeded item.' },
      { name: 'Item C', description: 'This is the third seeded item.' },
    ];

    const insertPromises = seedItems.map(item =>
      pool.query('INSERT INTO items (name, description) VALUES (?, ?)', [
        item.name,
        item.description,
      ])
    );

    await Promise.all(insertPromises);

    res.json({ message: 'Database seeded with sample items' });
  } catch (err) {
    console.error('Seed error:', err);
    res.status(500).json({ error: 'Database seed error' });
  }
});

const PORT = 3000;
initDB().then(() => {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on port `, PORT);
  });
});
