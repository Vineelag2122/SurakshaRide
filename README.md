# DEVTrails 2026
# SurakshaRide – AI-Powered Parametric Income Protection for Delivery Partners

## 1. Problem Overview

India’s food and quick-commerce delivery partners working with platforms like Swiggy, Zomato, Blinkit, and Zepto are a critical part of urban life. However, their earnings are highly vulnerable to external disruptions such as extreme weather, pollution, curfews, local strikes, and platform outages.

These events can significantly reduce their working hours or order volume, often causing a 20–30% drop in income, even when the rider is ready to work. Existing insurance products focus on health, life, or vehicle damage, but do not address short-term income loss.

Additionally, gig workers have limited savings buffers and low access to formal financial protection. Traditional insurance models are complex, slow, and not aligned with their weekly cash flow.

This creates a clear need for a simple, fast, and flexible income protection system.

## 2. Target Persona

### Urban Delivery Rider (Tier-1 / Tier-2 cities)

- Works 6–7 days a week, 8–10 hours daily  
- Earnings depend on completed orders, incentives, and tips  
- Uses smartphone-based delivery platforms  
- Paid weekly with high income variability  
- Bears operational risks without guaranteed income  

### Common Income-Loss Scenarios

- Heavy rain or flooding disrupting delivery operations  
- Extreme heat or poor AQI reducing working hours  
- Curfews, strikes, or local restrictions blocking access  
- Platform outages stopping order allocation  

In all cases, riders lose income due to factors beyond their control.

## 3. Proposed Solution: SurakshaRide

SurakshaRide is a weekly, AI-powered parametric income protection platform that automatically compensates delivery partners for income loss due to external disruptions without requiring claims.

It provides weekly income-loss coverage triggered automatically based on real-world conditions, ensuring fast and transparent payouts.

Simulated platform outage signals are used in prototype

### Core Principles

- Focused Coverage: Only income loss due to external disruptions  
- Weekly Model: Affordable plans aligned with rider payout cycles  
- Parametric Triggers: Predefined conditions automatically trigger payouts  
- AI Integration: Used for pricing, prediction, and fraud detection  

## 4. Parametric Triggers

### External Data Sources

- Weather (rainfall, temperature)  
- Air Quality Index (AQI)  
- Curfew/strike notifications (simulated feed)  
- Platform downtime (simulated API)  

### Example Triggers

- Rainfall ≥ 50 mm in 24 hours  
- Temperature ≥ 42°C  
- AQI ≥ 300 for extended duration  
- Platform outage ≥ 30 minutes during peak hours  

## 5. Income Loss & Payout Logic

For each disruption window:

- Expected Earnings (E): Predicted using AI models  
- Actual Earnings (A): Actual earnings are simulated or user-input based in the prototype
- Loss (L) = max(0, E − A)  

Payout is automatically calculated and credited, subject to weekly limits.

### Example

If expected earnings = ₹800 and actual earnings = ₹300  
Income loss = ₹500  
Payout = ₹500 (within weekly cap)

## 6. Weekly Plans & Pricing

| Plan | Coverage (Weekly) |
|------|------------------|
| S    | ₹2,000           |
| M    | ₹3,500           |
| L    | ₹5,000           |

### Premium Formula

Weekly Premium = Base Premium × (1 + 0.5 × Risk Score)

- Risk score (0–1) is generated using AI  
- Ensures fair and dynamic pricing  

## 7. Key Features

- Hyper-local AI-based risk pricing  
- Zero-touch automatic payouts (no claims required)  
- AI-based income prediction  
- Fraud detection using GPS and behavior patterns  
- Predictive risk alerts for upcoming disruptions  
- Protection Wallet for micro-savings and enhanced coverage  
- Real-time rider dashboard (earnings, payouts, coverage)  
- Admin dashboard for monitoring risk and analytics  

## 8. AI/ML Integration

### Risk Model

- Predicts likelihood of disruptions  
- Adjusts weekly premiums dynamically  

### Earnings Prediction

- Estimates expected income per time slot  
- Uses historical data and external factors  

### Fraud Detection

- Detects anomalies using behavior and location data  
- Flags suspicious cases for review
- For prototype:
	•	GPS check
	•	Rule-based anomaly
	•	Simple scoring


## 9. System Architecture

### Tech Stack

- Mobile App: Flutter / React Native  
- Backend: Node.js / FastAPI  
- Database: PostgreSQL + Redis  
- AI Models: Python (scikit-learn / XGBoost)  

### Core Services

- Policy Service  
- Risk & Pricing Service  
- Claims & Payout Service  
- Fraud Detection Service  
- Integration Service  

## 10. Impact

- Reduces income uncertainty for gig workers  
- Provides fast and transparent financial protection  
- Improves worker retention for platforms  
- Bridges the gap in gig economy social security  

## 11. Future Scope

- Expand to ride-hailing drivers (Uber, Ola)  
- Extend to freelancers and other gig workers  
- Integrate directly with platform APIs  

## 12. Risks and Challenges

- Data Dependency: Reliance on accurate external APIs  
- Platform Integration: Limited access to platform data  
- Trigger Calibration: Risk of incorrect thresholds  
- Fraud Risks: Potential misuse despite detection systems  
- User Adoption: Need for awareness and trust building  

## Conclusion

SurakshaRide delivers simple, affordable, and automated weekly income protection for gig workers.

By leveraging AI-driven parametric triggers, it ensures fast, fair, and zero-touch payouts, helping delivery partners stay financially secure even during disruptions.
