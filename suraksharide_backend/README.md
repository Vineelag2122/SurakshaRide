# SurakshaRide Backend

This backend adds a real server + database for authentication and wallet updates.

## Tech Stack
- Node.js + Express
- SQLite database (`data/suraksharide.db`)
- JWT auth

## Setup
1. Copy `.env.example` to `.env`
2. Install packages:
   - `npm install`
3. Run migrations:
   - `npm run migrate`
4. Seed demo users:
   - `npm run seed`
5. Start server:
   - `npm run dev`

## API Endpoints
- `GET /health`
- `POST /api/auth/register` (rider only)
- `POST /api/auth/login`
- `GET /api/rider/wallet` (auth token)
- `POST /api/rider/wallet/credit` (admin token)
- `POST /api/rider/wallet/debit` (auth token)
- `GET /api/rider/wallet/ledger` (auth token)

## Demo Credentials
- Admin: `admin@demo.com` / `demo123`
- Rider: `rider@demo.com` / `demo123`

## Example Login Request
```bash
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"rider@demo.com","password":"demo123","role":"rider"}'
```
