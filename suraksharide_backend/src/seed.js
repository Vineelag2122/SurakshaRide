const bcrypt = require('bcryptjs');
const { get, run } = require('./db');

async function seed() {
  const adminEmail = 'admin@demo.com';
  const riderEmail = 'rider@demo.com';
  const passwordHash = await bcrypt.hash('demo123', 10);

  const admin = await get('SELECT id FROM users WHERE email = ?', [adminEmail]);
  if (!admin) {
    await run(
      'INSERT INTO users(email, password_hash, role) VALUES (?, ?, ?)',
      [adminEmail, passwordHash, 'admin'],
    );
  }

  let rider = await get('SELECT id FROM users WHERE email = ?', [riderEmail]);
  if (!rider) {
    const inserted = await run(
      'INSERT INTO users(email, password_hash, role) VALUES (?, ?, ?)',
      [riderEmail, passwordHash, 'rider'],
    );
    rider = { id: inserted.id };
  }

  const riderProfile = await get('SELECT user_id FROM rider_profiles WHERE user_id = ?', [rider.id]);
  if (!riderProfile) {
    await run(
      'INSERT INTO rider_profiles(user_id, wallet_balance, operating_location, is_verified) VALUES (?, ?, ?, ?)',
      [rider.id, 0, 'Bengaluru', 1],
    );
  }

  const policies = [
    {
      id: 'policy_basic',
      name: 'Income Shield - Basic',
      description: 'Weekly income-loss protection for local disruptions',
      weeklyPremium: 299,
      weeklyCoverageLimit: 2000,
      type: 'basic',
    },
    {
      id: 'policy_plus',
      name: 'Income Shield - Plus',
      description: 'Higher weekly protection for moderate-risk zones',
      weeklyPremium: 599,
      weeklyCoverageLimit: 3500,
      type: 'premium',
    },
    {
      id: 'policy_max',
      name: 'Income Shield - Max',
      description: 'Maximum weekly income protection for full-time partners',
      weeklyPremium: 999,
      weeklyCoverageLimit: 5000,
      type: 'comprehensive',
    },
  ];

  for (const policy of policies) {
    await run(
      `INSERT OR IGNORE INTO policies(id, name, description, weekly_premium, weekly_coverage_limit, type)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [policy.id, policy.name, policy.description, policy.weeklyPremium, policy.weeklyCoverageLimit, policy.type],
    );
  }

  console.log('Seed completed.');
}

seed().catch((error) => {
  console.error('Seed failed:', error.message);
  process.exit(1);
});
