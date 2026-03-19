# SurakshaRide

SurakshaRide is an AI-enabled parametric income protection mobile app that offers weekly income-loss cover to food and quick-commerce delivery partners.

## 1. Problem Overview

India’s food and quick-commerce delivery partners are vulnerable to income loss from external disruptions like extreme weather, pollution, curfews, and platform outages. These events can cause a 20–30% drop in monthly income. Existing insurance products do not cover short-term income loss, and traditional insurance is not suitable for gig workers' needs.

## 2. Persona: Urban Delivery Rider

Our chosen persona is an urban food and quick-commerce delivery rider in India.

### Key Characteristics

*   Works 6–7 days a week, 8–10 hours daily.
*   Earnings are variable and tied to order volume.
*   Uses an Android smartphone for work.
*   Bears most operational risks (fuel, vehicle upkeep).

### Income-Loss Scenarios

*   **Heavy Rain & Flooding:** Disrupts shifts and reduces orders.
*   **Extreme Heat or Poor Air Quality:** Riders avoid long shifts, leading to lost income.
*   **Curfews and Local Strikes:** Block access to delivery zones.
*   **Platform/App Outages:** Leave riders idle during peak hours.

## 3. Solution Concept

We propose **SurakshaRide**, an AI-enabled mobile app for weekly income protection. It monitors external disruptions and triggers instant, rule-based payouts without requiring manual claims.

### Core Principles

*   **Coverage Scope:** Only income loss due to external disruptions.
*   **Weekly Pricing:** Affordable and flexible weekly premiums and coverage.
*   **Parametric Automation:** Payouts are auto-initiated based on predefined triggers.
*   **AI-Driven Intelligence:** ML models for risk-based pricing, earnings estimation, and fraud detection.

## 4. Parametric Triggers and Disruption Parameters

### 4.1. External Indices

*   **Weather (Rain & Heat):**
    *   Source: Public weather APIs (e.g., IMD, OpenWeather).
    *   Triggers: Daily rainfall ≥ 50 mm, or temperature ≥ 42°C for ≥ 3 hours.
*   **Air Quality:**
    *   Source: AQI APIs.
    *   Trigger: AQI ≥ 300 for ≥ 4 hours.
*   **Social/Regulatory Events:**
    *   Source: Simulated official notifications.
    *   Triggers: Government-declared curfews or registered strikes.
*   **Platform/Infra Disruptions:**
    *   Source: Simulated platform status API.
    *   Triggers: App unavailability or payment gateway outages.

### 4.2. Earnings Impact Logic

When a trigger occurs, the system checks if the rider was on-duty and if their expected earnings significantly exceed actual earnings. If so, it calculates the income loss and initiates a payout.

## 5. Weekly Premium and Financial Model

### 5.1. Product Structure

We offer simple weekly plans with different coverage amounts:

*   **Plan S:** Cover up to ₹2,000/week.
*   **Plan M:** Cover up to ₹3,500/week.
*   **Plan L:** Cover up to ₹5,000/week.

### 5.2. High-Level Premium Formula

A base premium is set by city and plan, then adjusted by a risk score `R` from our AI model:

`Weekly Premium = Base Premium × (1 + 0.5 × R)`

### 5.3. Payout Calculation

For each disruption window `W`:

*   **Expected Earnings (E_W):** Predicted by an ML model.
*   **Actual Earnings (A_W):** Fetched from platform logs.
*   **Income Loss (L_W):** `max(0, E_W - A_W)`, capped at plan limits.

### 5.4. Funding Enhancements (Optional)

*   Micro-top-ups from tips.
*   Platform co-contributions during high-risk seasons.

## 6. AI/ML Integration Plan

### 6.1. Dynamic Risk & Pricing Model

*   **Objective:** Predict weekly disruption risk to adjust premiums.
*   **Model:** Gradient boosting model to output a risk score.

### 6.2. Expected Earnings Model

*   **Objective:** Estimate what a rider would have earned without disruptions.
*   **Model:** Regression model (e.g., XGBoost, Random Forest) to predict earnings.

### 6.3. Fraud Detection

*   **Objective:** Detect suspicious claims to reduce leakage.
*   **Techniques:** Anomaly detection and rule-based gating.

### 6.4. Personalization and UX Intelligence

*   Use clustering to recommend suitable plans.
*   Notify riders of high-risk weeks.

## 7. Mobile App – User Workflow

### 7.1. Rider Journey

1.  **Onboarding & KYC:** Sign up, basic KYC, and link delivery platform account.
2.  **Choose Weekly Plan:** Select a plan (S/M/L) and set up payment.
3.  **Background Monitoring:** The system continuously monitors for disruptions.
4.  **Auto Claim & Payout:** The app notifies the rider of automatic payouts.
5.  **History & Insights:** A dashboard shows earnings, payouts, and risk alerts.

### 7.2. Admin/Insurer View

*   Monitor portfolio, risk, and loss ratios.
*   Configure triggers and adjust underwriting strategies.

## 8. Tech Stack and Architecture

### 8.1. Proposed Tech Stack

*   **Mobile App:** Flutter / React Native or native Android (Kotlin).
*   **Backend:** Node.js / Java Spring Boot / Python FastAPI.
*   **Database:** PostgreSQL and Redis.
*   **AI/ML:** Python (scikit-learn, XGBoost, PyTorch).
*   **Integrations (mocked):** Weather APIs, platform APIs, payment gateway sandbox.

### 8.2. High-Level Architecture

A microservices architecture with:

*   Policy Service
*   Risk & Pricing Service
*   Claims & Payout Service
*   Fraud Detection Service
*   Integration Service
*   Admin Dashboard