# SurakshaRide Frontend

Flutter app for an AI-powered, parametric weekly income-protection platform for India’s gig delivery workers.

## What This Prototype Demonstrates

- Rider and admin onboarding with role-specific access.
- Weekly income-loss policy selection and weekly premium payment flow.
- Trigger intake from multiple uncontrollable event sources:
	- News RSS scraping
	- Weather API signals (rainfall, extreme heat)
	- AQI API signals (severe pollution)
	- Simulated platform outage feed
	- Simulated civic/curfew feed
- Admin review and approval pipeline before rider visibility.
- Location-aware trigger targeting (not every rider gets every trigger).
- Zero-touch payout automation for eligible, verified riders.
- Fraud scoring before payout with hold-for-review threshold.
- Rider and admin dashboards with payout/fraud/trigger analytics.

## Compliance Notes

- Coverage scope is income loss only for uncontrollable disruptions.
- No health, life, accident, or vehicle-repair coverage is included.
- Financial model is weekly aligned.

## Tech Stack (Frontend)

- Flutter (Material 3)
- Local persistence using sqflite / sqflite_common_ffi (desktop + mobile)
- In-memory fallback behavior on web
- HTTP + XML parsing for feed and API integrations

## Run Locally

1. Install Flutter SDK (stable channel).
2. From this folder, run:

```bash
flutter pub get
flutter run
```

Optional checks:

```bash
flutter analyze lib/suraksharide_app.dart
```

## Demo Credentials

- Rider: rider@demo.com / demo123
- Admin: admin@demo.com / demo123

Admin registration is disabled by design.

## Suggested Demo Flow (2 to 5 min)

1. Login as Admin.
2. Fetch uncontrollable triggers.
3. Approve one trigger with affected location.
4. Login as Rider and save KYC + operating location.
5. Show location-matched alert visibility and auto payout behavior.
6. Show fraud hold case and admin fraud analytics.

## Current Scope vs Future Scope

Implemented in this prototype:

- End-to-end trigger-to-payout automation with fraud gating.
- Multi-source trigger ingestion and admin approval.
- Weekly policy and payment UX.

Planned next:

- Deeper ML models for risk/premium/fraud scoring.
- Real payment gateway sandbox integration.
- Historical trend charts and forecast panels.
