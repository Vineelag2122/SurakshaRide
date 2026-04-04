const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const authRoutes = require('./routes/auth');
const riderRoutes = require('./routes/rider');

const app = express();   // ✅ FIRST create app

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// Routes
app.get('/', (req, res) => {
  res.send('Server is running successfully 🚀');
});

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'suraksharide-backend' });
});

app.get('/api', (req, res) => {
  res.json({
    message: "SurakshaRide API is running 🚀",
    endpoints: [
      "/api/auth",
      "/api/rider",
      "/health"
    ]
  });
});

app.use('/api/auth', authRoutes);
app.use('/api/rider', riderRoutes);

// Error handler
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ message: 'Unexpected server error.' });
});

// ✅ ONLY ONE listen (at END)
const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});