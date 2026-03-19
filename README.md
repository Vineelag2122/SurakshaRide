# DEVTrails 2026 – AI‑Powered Parametric Income Protection for Delivery Partners
## 1. Problem Overview
India’s food and quick‑commerce delivery partners (Zomato, Swiggy, Blinkit, Zepto, etc.) form a critical backbone of urban life, ensuring timely delivery of meals and essentials. However, their earnings are highly vulnerable to external disruptions such as extreme weather, pollution, curfews, local strikes, and platform outages that they cannot control. These events can reduce their working hours or order volume, causing 20–30% drops in monthly income in bad periods, while existing insurance products focus on health, life, or vehicle damage rather than short‑term income loss.
​

At the same time, research shows gig workers have low insurance penetration, limited savings buffers, and little access to formal social protection, leaving them exposed to income shocks despite high contribution to the digital economy. Traditional indemnity insurance with complex claims processes, annual premiums, and manual documentation does not match their weekly cash‑flow reality or the need for fast, transparent payouts. There is a clear gap for a simple, digital‑first weekly income protection product tailored to their risk profile.
​

## 2. Persona: Urban Delivery Rider
Chosen Persona:
Urban food and quick‑commerce delivery rider working with platforms like Swiggy, Zomato, Blinkit, or Zepto in Tier‑1/Tier‑2 Indian cities.

Key characteristics:

Works 6–7 days a week, often 8–10 hours per day during peak slots (lunch/dinner or evening quick‑commerce rush).

Earnings are tied to number of orders completed, surge incentives, and tips, with high variability across days and seasons.

Typically uses an Android smartphone, depends on navigation apps and platform apps, and receives payouts on a weekly cycle.
​

Bears most operational risk (fuel, vehicle upkeep, demand fluctuation) without employer‑style benefits or guaranteed minimum earnings.

Representative scenarios (income‑loss due to external disruptions):

Heavy rain & flooding: Entire afternoon/evening shifts disrupted as roads become unsafe or restaurants temporarily stop accepting orders in certain zones, reducing completed orders and earnings.

Extreme heat or poor air quality: Riders avoid long outdoor shifts during 42°C+ heat waves or AQI ≥ 300 days for health reasons, leading to lost working hours and lower income.
​

Curfews and local strikes: Sudden Section‑144, market closures, or law‑and‑order issues shut down specific neighborhoods, blocking access to pick‑up/drop locations.
​

Platform/app outages: Prolonged app downtime or payment gateway failures stop new order assignment, leaving riders idle during what would normally be high‑earning slots.
​

In all these cases, riders lose earnings even though they did nothing wrong and often were ready to work.

## 3. Solution Concept
We propose “SurakshaRide” – an AI‑enabled parametric income protection mobile app that offers weekly income‑loss cover to food and quick‑commerce delivery partners. The product automatically monitors external disruption parameters (weather, pollution, curfew, platform outages) and triggers instant, rule‑based payouts when these conditions cause measurable loss of income, without requiring riders to file traditional claims.
​
​

Core principles:

Coverage scope: Only loss of income due to external disruptions; no health, life, accident, or vehicle repairs, strictly following the challenge constraints.
​

Weekly pricing: Premiums and coverage are structured on a weekly basis, matching typical payout cycles and making protection more affordable and flexible.
​
​

Parametric automation: Predefined external indices (rainfall, temperature, AQI, curfew, platform incidents) act as triggers; once conditions are met and income loss is detected, payouts are auto‑initiated.
​
​

AI‑driven intelligence: Machine learning models power weekly risk‑based pricing, expected earnings estimation, and fraud detection, enabling fairer premiums and low‑friction claims.

## 4. Parametric Triggers and Disruption Parameters
We design a set of clear, measurable parametric triggers tailored to delivery partners:

### 4.1 External indices
Weather (Rain & Heat):

Source: Public weather APIs (e.g., IMD, OpenWeather – mocked for prototype).
​
​

Triggers (examples):

Daily rainfall in worker’s primary pin code ≥ 50 mm in the last 24 hours.

Maximum temperature ≥ 42°C for ≥ 3 continuous hours.

Air Quality:

Source: AQI APIs (or mocks).

Trigger: AQI ≥ 300 (“Very Poor/Severe”) in worker’s zone for ≥ 4 hours.
​

Social/Regulatory Events:

Source: Simulated feeds of official curfew notifications / market closures (text feed or admin inputs in prototype).
​

Triggers:

Government/authority‑declared curfew in ward/zone overlapping rider’s working area.

Registered city‑wide strike or protest causing closure of markets/zones.

Platform / Infra Disruptions:

Source: Simulated platform status API or internal service that flags downtime.

Triggers:

Food delivery app unavailability in city for ≥ 30 minutes during peak slot.

Payment gateway outage blocking order completion for ≥ X minutes.
​

### 4.2 Earnings impact logic
Once a trigger occurs, the system checks:

Was the rider on‑duty (status “online” with the platform or within geofenced working zone) during the disruption window?

What is the expected earnings for that rider in that time window vs actual earnings?

If expected earnings significantly exceed actual earnings and the difference is attributable to a disruption trigger, the system calculates income loss and initiates a payout within the weekly coverage cap.
​

## 5. Weekly Premium and Financial Model
### 5.1 Product structure
We offer simple weekly plans, each with a maximum weekly income‑loss coverage amount:

Plan S: Cover up to ₹2,000/week of income loss.

Plan M: Cover up to ₹3,500/week.

Plan L: Cover up to ₹5,000/week.

Premiums are paid weekly, deducted via UPI/autopay or as simulated deductions from platform payouts in the prototype.
​
​

### 5.2 High‑level premium formula
For each rider, a base premium is set by city and plan:

Example (illustrative):

Tier‑1 city – Plan M base premium = ₹70/week.

Tier‑2/3 city – Plan M base premium = ₹55/week.

We then apply a risk score 
R
∈
[
0
,
1
]
R∈[0,1] generated by our AI risk model (see Section 6.1):

Weekly Premium = Base Premium × (1 + 0.5 × R)

Examples:

Low‑risk rider (R = 0.2): multiplier = 1.1 → premium ≈ ₹77/week (Tier‑1, Plan M).

High‑risk rider (R = 0.8): multiplier = 1.4 → premium ≈ ₹98/week (Tier‑1, Plan M).

This makes pricing sensitive to local disruption risk and seasonality while remaining interpretable.

### 5.3 Payout calculation
For each disruption window *W*:

- **Expected earnings E_W**: Predicted by an ML model using historical data for that rider: weekday, time band, weather season, festival flags, and zone-level demand patterns.
- **Actual earnings A_W**: Fetched from platform or simulated order logs for that window.
- **Income loss L_W**: `L_W = max(0, E_W - A_W)` capped at per-event and per-week limits.

Total weekly payout = sum of all *L_W* during the week, capped at the rider’s chosen plan limit (e.g., ₹3,500 for Plan M).

### 5.4 Funding enhancements (optional idea)
We can optionally allow:

Micro‑top‑ups from tips or per order (e.g., ₹1 per order goes into a “Protection Wallet”), inspired by tip‑funded micro‑insurance models.
​

Platform co‑contributions during high‑risk seasons (e.g., monsoon), where platforms add a small amount per order to encourage adoption.
​

## 6. AI/ML Integration Plan
### 6.1 Dynamic risk & pricing model
Objective: Predict weekly disruption risk and adjust premiums fairly.

Inputs:

City, micro‑zone, and geohash of primary working area.

Historical weather and AQI data for that zone.

Rider’s historical active hours distribution and typical order density.

Season and month (monsoon, winter pollution peaks, festive rush).

Model:

Gradient boosting or similar model trained on historical (or simulated) data to output a risk score for likely income‑loss events in the upcoming week.

Risk score drives the multiplier in the premium formula (Section 5.2).

### 6.2 Expected earnings model (for loss estimation)
Objective: Estimate “what the rider would have earned” absent disruptions.

Inputs:

Historical earnings per time slot per rider.

Features: weekday, time of day, weather forecasts, holiday/festival flags, surge indicators, and platform demand signals (past orders per slot).

Model:

Regression model (e.g., XGBoost/Random Forest/Neural Net) predicting expected earnings per slot.

During actual week, we compare predicted vs realised earnings to quantify income loss due to disruption.

### 6.3 Fraud detection
Objective: Detect suspicious claims and reduce leakage while keeping UX simple.

Signals:

Claims frequency vs peer riders in the same zone and plan.

Discrepancies between app GPS and platform location logs.

Claims in time/location windows where no triggers fired.

Unusual patterns (e.g., rider always “on‑duty” only during high payout windows).
​

Techniques:

Unsupervised anomaly detection (Isolation Forest, clustering‑based anomaly scores) on claim and behaviour data.
​

Simple supervised classifier for “high‑risk vs low‑risk claim” once we have labelled/simulated examples.

Rule‑based gating for extreme cases (e.g., claims from locations thousands of km away from registered city).

Low‑risk claims remain fully automated; high‑risk ones are flagged in the admin dashboard for manual review.

### 6.4 Personalisation and UX intelligence
We can also use clustering/segmentation to:

Identify full‑time vs part‑time riders and recommend suitable plan sizes.

Notify riders before high‑risk weeks (“Monsoon peak ahead – disruption probability high; your current cover is ₹2,000/week, consider upgrading.”).

## 7. Mobile App – User Workflow
Platform: Android mobile app (primary) with backend services and admin dashboard.
​

### 7.1 Rider journey
Onboarding & KYC

Sign up with mobile number + OTP.

Basic KYC (name, ID type, city) and link to delivery platform account (simulated integration in prototype).

Collect consent for using location and earnings data for risk scoring and payouts.

Choose weekly plan

App shows recommended plan based on typical earnings (S/M/L).

Display weekly premium and maximum weekly protection clearly.

Payment setup (UPI/Wallet/autodebit – sandbox).

Background monitoring

System continuously monitors:

Weather and AQI in rider’s working zone.

Platform status/outage events (simulated).

Curfew/strike feeds (simulated).

No user action needed during normal operations.

Auto claim & payout

When a trigger fires and income loss is detected, the app:

Notifies the rider: “Heavy rain caused loss of ₹X today. You will receive a payout of ₹Y under SurakshaRide.”

Shows payout details and updated weekly balance (remaining coverage).

History & insights

Rider dashboard:

Weekly earnings vs protected earnings.

Past disruption events and payouts.

Coverage status and upcoming risk alerts.

### 7.2 Admin/Insurer view (Phase 2–3)
Monitor policy portfolio, risk and loss ratios by city/zone, high‑risk upcoming weeks, and fraud alerts.
​

Configure parametric thresholds, simulate impact of new triggers, and adjust underwriting strategies.

## 8. Tech Stack and Architecture
### 8.1 Proposed tech stack
Mobile App:

Flutter / React Native (cross‑platform) or native Android (Kotlin).

Backend:

Node.js / Java Spring Boot / Python FastAPI for REST APIs and business logic.

Database:

PostgreSQL for transactional data (policies, payouts), Redis for caching.

AI/ML:

Python (scikit‑learn, XGBoost, or simple PyTorch) – models served via REST microservice.

External Integrations (mocked for prototype):

Weather & AQI APIs (free tier/mock).

Platform APIs (simulated for online/offline status, earnings, orders).
​

Payment gateway sandbox (Razorpay test mode / Stripe sandbox / UPI simulator).
​

### 8.2 High‑level architecture
Mobile app ↔ API Gateway ↔ Microservices:

Policy Service (onboarding, plan selection, weekly renewals).

Risk & Pricing Service (uses ML risk model).

Claims & Payout Service (trigger processing, earnings comparison, payout computation).

Fraud Detection Service (anomaly scoring).

Integration Service (weather, AQI, platform, payments).

Admin dashboard (web) connected to same backend for analytics and configurations.
