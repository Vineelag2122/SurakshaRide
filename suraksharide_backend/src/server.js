const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const PORT = process.env.PORT || port;

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
const authRoutes = require('./routes/auth');
const riderRoutes = require('./routes/rider');

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

app.get('/', (req, res) => {
  res.send('Server is running successfully 🚀');
});

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'suraksharide-backend' });
});

app.use('/api/auth', authRoutes);
app.use('/api/rider', riderRoutes);


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

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ message: 'Unexpected server error.' });
});

app.listen(port, () => {
  console.log(`SurakshaRide backend listening on http://localhost:${port}`);
});
