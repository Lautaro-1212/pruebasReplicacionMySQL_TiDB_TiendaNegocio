// db.js
import { createPool } from 'mysql2/promise'

export const pool = createPool({
  host: 'localhost',
  port: 4000,
  user: 'root',
  password: '',
  database: 'test',
});