const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { port } = require('./config');
const authRoutes = require('./routes/auth');
const riderRoutes = require('./routes/rider');

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'suraksharide-backend' });
});

app.use('/api/auth', authRoutes);
app.use('/api/rider', riderRoutes);

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ message: 'Unexpected server error.' });
});

app.listen(port, () => {
  console.log(`SurakshaRide backend listening on http://localhost:${port}`);
});
