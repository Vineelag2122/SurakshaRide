const express = require('express');
const { all, get, run } = require('../db');
const { auth } = require('../middleware/auth');

const router = express.Router();

router.get('/wallet', auth(), async (req, res) => {
  try {
    const profile = await get(
      `SELECT rp.wallet_balance
       FROM rider_profiles rp
       INNER JOIN users u ON u.id = rp.user_id
       WHERE u.id = ?`,
      [req.auth.userId],
    );

    return res.json({ walletBalance: Number(profile?.wallet_balance || 0) });
  } catch (error) {
    return res.status(500).json({ message: 'Failed to fetch wallet.', error: error.message });
  }
});

router.post('/wallet/credit', auth('admin'), async (req, res) => {
  try {
    const { riderEmail, amount, reason } = req.body;
    const cleanEmail = String(riderEmail || '').trim().toLowerCase();
    const creditAmount = Number(amount || 0);
    const cleanReason = String(reason || 'Manual credit').trim();

    if (!cleanEmail || !Number.isFinite(creditAmount) || creditAmount <= 0) {
      return res.status(400).json({ message: 'riderEmail and positive amount are required.' });
    }

    const rider = await get('SELECT id, role FROM users WHERE email = ?', [cleanEmail]);
    if (!rider || rider.role !== 'rider') {
      return res.status(404).json({ message: 'Rider not found.' });
    }

    await run('UPDATE rider_profiles SET wallet_balance = wallet_balance + ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?', [creditAmount, rider.id]);
    await run('INSERT INTO wallet_ledger(user_id, entry_type, amount, reason) VALUES (?, ?, ?, ?)', [rider.id, 'credit', creditAmount, cleanReason]);

    const profile = await get('SELECT wallet_balance FROM rider_profiles WHERE user_id = ?', [rider.id]);
    return res.json({ walletBalance: Number(profile?.wallet_balance || 0) });
  } catch (error) {
    return res.status(500).json({ message: 'Failed to credit wallet.', error: error.message });
  }
});

router.post('/wallet/debit', auth(), async (req, res) => {
  try {
    const { amount, reason } = req.body;
    const debitAmount = Number(amount || 0);
    const cleanReason = String(reason || 'Policy payment').trim();

    if (!Number.isFinite(debitAmount) || debitAmount <= 0) {
      return res.status(400).json({ message: 'Positive amount is required.' });
    }

    const profile = await get('SELECT wallet_balance FROM rider_profiles WHERE user_id = ?', [req.auth.userId]);
    const currentBalance = Number(profile?.wallet_balance || 0);
    if (currentBalance < debitAmount) {
      return res.status(400).json({ message: 'Insufficient wallet balance.' });
    }

    await run('UPDATE rider_profiles SET wallet_balance = wallet_balance - ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?', [debitAmount, req.auth.userId]);
    await run('INSERT INTO wallet_ledger(user_id, entry_type, amount, reason) VALUES (?, ?, ?, ?)', [req.auth.userId, 'debit', debitAmount, cleanReason]);

    const updated = await get('SELECT wallet_balance FROM rider_profiles WHERE user_id = ?', [req.auth.userId]);
    return res.json({ walletBalance: Number(updated?.wallet_balance || 0) });
  } catch (error) {
    return res.status(500).json({ message: 'Failed to debit wallet.', error: error.message });
  }
});

router.get('/wallet/ledger', auth(), async (req, res) => {
  try {
    const rows = await all(
      `SELECT id, entry_type AS entryType, amount, reason, created_at AS createdAt
       FROM wallet_ledger
       WHERE user_id = ?
       ORDER BY id DESC
       LIMIT 100`,
      [req.auth.userId],
    );

    return res.json({ entries: rows });
  } catch (error) {
    return res.status(500).json({ message: 'Failed to fetch wallet ledger.', error: error.message });
  }
});

module.exports = router;
