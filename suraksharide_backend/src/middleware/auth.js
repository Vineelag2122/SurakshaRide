const jwt = require('jsonwebtoken');
const { jwtSecret } = require('../config');

function auth(requiredRole) {
  return (req, res, next) => {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!token) {
      return res.status(401).json({ message: 'Missing bearer token.' });
    }

    try {
      const payload = jwt.verify(token, jwtSecret);
      req.auth = payload;
      if (requiredRole && payload.role !== requiredRole) {
        return res.status(403).json({ message: 'Forbidden for this role.' });
      }
      return next();
    } catch (_error) {
      return res.status(401).json({ message: 'Invalid token.' });
    }
  };
}

module.exports = { auth };
