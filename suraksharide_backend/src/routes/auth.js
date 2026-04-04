const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { get, run } = require('../db');
const { jwtSecret } = require('../config');

const router = express.Router();

router.post('/register', async (req, res) => {
  try {
    const { email, password, role } = req.body;
    const cleanEmail = String(email || '').trim().toLowerCase();
    const cleanRole = String(role || '').trim().toLowerCase();

    if (!cleanEmail || !cleanEmail.includes('@')) {
      return res.status(400).json({ message: 'Valid email is required.' });
    }

    if (!password || String(password).length < 6) {
      return res.status(400).json({ message: 'Password must be at least 6 characters.' });
    }

    if (cleanRole !== 'rider') {
      return res.status(400).json({ message: 'Only rider self-registration is allowed.' });
    }

    const existing = await get('SELECT id FROM users WHERE email = ?', [cleanEmail]);
    if (existing) {
      return res.status(409).json({ message: 'Email already registered.' });
    }

    const hash = await bcrypt.hash(String(password), 10);
    const inserted = await run(
      'INSERT INTO users(email, password_hash, role) VALUES (?, ?, ?)',
      [cleanEmail, hash, cleanRole],
    );

    await run(
      'INSERT INTO rider_profiles(user_id, wallet_balance, operating_location, is_verified) VALUES (?, ?, ?, ?)',
      [inserted.id, 0, '', 0],
    );

    return res.status(201).json({ message: 'Registration successful.' });
  } catch (error) {
    return res.status(500).json({ message: 'Registration failed.', error: error.message });
  }
});

router.post('/login', async (req, res) => {
  try {
    const { email, password, role } = req.body;
    const cleanEmail = String(email || '').trim().toLowerCase();
    const cleanRole = String(role || '').trim().toLowerCase();

    const user = await get('SELECT id, email, password_hash, role FROM users WHERE email = ?', [cleanEmail]);
    if (!user) {
      return res.status(401).json({ message: 'Account not found.' });
    }

    if (user.role !== cleanRole) {
      return res.status(401).json({ message: `This account is ${user.role}.` });
    }

    const ok = await bcrypt.compare(String(password || ''), user.password_hash);
    if (!ok) {
      return res.status(401).json({ message: 'Incorrect password.' });
    }

    const token = jwt.sign(
      { userId: user.id, email: user.email, role: user.role },
      jwtSecret,
      { expiresIn: '12h' },
    );

    return res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
      },
    });
  } catch (error) {
    return res.status(500).json({ message: 'Login failed.', error: error.message });
  }
});

module.exports = router;
