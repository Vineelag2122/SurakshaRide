const express = require('express');
const { auth } = require('../middleware/auth');
const { run } = require('../db');

const router = express.Router();

const cityGeo = {
  bengaluru: { lat: 12.9716, lon: 77.5946 },
  mumbai: { lat: 19.076, lon: 72.8777 },
  delhi: { lat: 28.6139, lon: 77.209 },
  pune: { lat: 18.5204, lon: 73.8567 },
};

function normalizeCity(raw) {
  const city = String(raw || 'Bengaluru').trim();
  if (!city) return 'Bengaluru';
  return city;
}

function deriveTrafficSignal(city) {
  // Deterministic signal for demo repeatability: no random values in payouts.
  const hour = new Date().getUTCHours();
  const seed = city.length * 7 + hour * 3;
  return 30 + (seed % 61); // 30..90
}

async function getWeatherSignals(city) {
  const key = city.toLowerCase();
  const fallback = { rainfallMm: 0, temperatureC: 32, source: 'Open-Meteo (fallback)' };
  if (!cityGeo[key]) return fallback;

  const { lat, lon } = cityGeo[key];
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,rain`;

  try {
    const response = await fetch(url);
    if (!response.ok) return fallback;

    const payload = await response.json();
    const current = payload.current || {};
    return {
      rainfallMm: Number(current.rain || 0),
      temperatureC: Number(current.temperature_2m || 0),
      source: 'Open-Meteo',
    };
  } catch (_error) {
    return fallback;
  }
}

router.get('/traffic', auth(), async (req, res) => {
  const city = normalizeCity(req.query.city);
  const congestionIndex = deriveTrafficSignal(city);
  const isDisrupted = congestionIndex >= 75;

  if (isDisrupted) {
    await run(
      'INSERT INTO disruption_events(city, category, signal_value, severity, source) VALUES (?, ?, ?, ?, ?)',
      [city, 'traffic', congestionIndex, 'medium', 'Mock Traffic API'],
    );
  }

  return res.json({ city, source: 'Mock Traffic API', congestionIndex, isDisrupted });
});

router.get('/platform-status', auth(), async (req, res) => {
  const city = normalizeCity(req.query.city);
  const platform = String(req.query.platform || 'generic').trim().toLowerCase();
  const minute = new Date().getUTCMinutes();
  const degraded = minute % 7 === 0;

  if (degraded) {
    await run(
      'INSERT INTO disruption_events(city, category, signal_value, severity, source) VALUES (?, ?, ?, ?, ?)',
      [city, 'platform_outage', 1, 'high', `Mock Platform API (${platform})`],
    );
  }

  return res.json({
    city,
    platform,
    source: 'Mock Platform API',
    status: degraded ? 'degraded' : 'operational',
    triggerEligible: degraded,
  });
});

router.get('/evaluate', auth(), async (req, res) => {
  const city = normalizeCity(req.query.city);
  const weather = await getWeatherSignals(city);
  const trafficIndex = deriveTrafficSignal(city);

  const triggers = [];

  if (weather.rainfallMm >= 8) {
    triggers.push({
      category: 'rainfall',
      severity: 'high',
      signal: weather.rainfallMm,
      source: weather.source,
      reason: 'Rainfall threshold crossed for income-loss trigger',
    });
  }

  if (weather.temperatureC >= 40) {
    triggers.push({
      category: 'extreme_heat',
      severity: 'medium',
      signal: weather.temperatureC,
      source: weather.source,
      reason: 'Extreme heat threshold crossed for outdoor delivery risk',
    });
  }

  if (trafficIndex >= 75) {
    triggers.push({
      category: 'traffic',
      severity: 'medium',
      signal: trafficIndex,
      source: 'Mock Traffic API',
      reason: 'Traffic congestion threshold crossed',
    });
  }

  for (const trigger of triggers) {
    await run(
      'INSERT INTO disruption_events(city, category, signal_value, severity, source) VALUES (?, ?, ?, ?, ?)',
      [city, trigger.category, trigger.signal, trigger.severity, trigger.source],
    );
  }

  return res.json({
    city,
    weeklyModel: true,
    triggerCount: triggers.length,
    triggers,
    weatherSignals: weather,
    trafficIndex,
  });
});

module.exports = router;
