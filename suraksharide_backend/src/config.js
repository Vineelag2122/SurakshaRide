const path = require('path');
const dotenv = require('dotenv');

dotenv.config();

module.exports = {
  port: Number(process.env.PORT || 4000),
  jwtSecret: process.env.JWT_SECRET || 'change-me-in-production',
  dbPath: path.resolve(process.cwd(), process.env.DB_PATH || './data/suraksharide.db'),
};
