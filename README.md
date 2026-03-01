# Subscription Tracker API

A production-ready REST API for managing recurring subscriptions. Track services, get automated renewal reminders via email, and manage users — all secured with JWT auth, rate limiting, and bot protection.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [API Reference](#api-reference)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)
- [Email Reminders](#email-reminders)
- [Testing](#testing)

---

## Features

- **JWT Authentication** — Sign up, sign in, and sign out with secure token-based auth
- **Subscription CRUD** — Create, read, update, cancel, and delete subscriptions
- **Upcoming Renewals** — Query subscriptions renewing within a configurable time window
- **User Management** — View, update, and delete user profiles (with cascading subscription cleanup)
- **Automated Email Reminders** — Scheduled renewal reminders at 7, 5, 2, and 1 day(s) before renewal via Upstash workflows
- **Rate Limiting & Bot Protection** — Arcjet-powered token bucket rate limiting and bot detection
- **Input Validation** — Mongoose schema validation with clear error messages
- **Global Error Handling** — Centralized middleware for Mongoose, JWT, and application errors
- **CORS Support** — Cross-origin requests enabled out of the box
- **Request Logging** — Morgan HTTP logging in development mode
- **Graceful Shutdown** — Clean server shutdown on SIGTERM/SIGINT

---

## Tech Stack

| Layer | Technology |
|---|---|
| Runtime | Node.js |
| Framework | Express.js |
| Database | MongoDB + Mongoose |
| Auth | JSON Web Tokens (jsonwebtoken, bcryptjs) |
| Email | Nodemailer (Gmail SMTP) |
| Workflows | Upstash QStash |
| Security | Arcjet (rate limit, bot detection, shield) |

---

## Project Structure

```
subscription-tracker-api/
├── app.js                          # Express app entry point
├── package.json
├── config/
│   ├── env.js                      # Environment variable loader
│   ├── arcjet.js                   # Arcjet rate limiter config
│   ├── nodemailer.js               # Email transporter config
│   └── upstash.js                  # Upstash workflow client
├── controllers/
│   ├── auth.controller.js          # Sign up, sign in, sign out
│   ├── subscription.controller.js  # Subscription CRUD + filters
│   ├── user.controller.js          # User CRUD
│   └── workflow.controller.js      # Reminder workflow handler
├── database/
│   └── mongodb.js                  # Mongoose connection
├── middlewares/
│   ├── arcjet.middleware.js        # Rate limiting middleware
│   ├── auth.middleware.js          # JWT verification middleware
│   └── error.middleware.js         # Global error handler
├── models/
│   ├── subscription.model.js       # Subscription schema
│   └── user.model.js               # User schema
├── routes/
│   ├── auth.routes.js              # /api/v1/auth
│   ├── subscription.routes.js      # /api/v1/subscriptions
│   ├── user.routes.js              # /api/v1/users
│   └── workflow.routes.js          # /api/v1/workflows
└── utils/
    ├── email-template.js           # HTML email template
    └── send-email.js               # Email sender utility
```

---

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) v18+
- [MongoDB](https://www.mongodb.com/) (local or Atlas)
- [Git](https://git-scm.com/)

### Installation

```bash
git clone <your-repo-url>
cd subscription-tracker-api
npm install
```

### Run in Development

```bash
npm run dev
```

### Run in Production

```bash
npm start
```

The server starts at **http://localhost:5500** by default.

---

## Environment Variables

Create a `.env.development.local` file in the project root:

```env
# SERVER
PORT=5500
NODE_ENV=development
SERVER_URL="http://localhost:5500"

# DATABASE
DB_URI="your-mongodb-connection-string"

# JWT
JWT_SECRET="your-secret-key"
JWT_EXPIRES_IN="1d"

# ARCJET
ARCJET_KEY="your-arcjet-key"
ARCJET_ENV="development"

# UPSTASH
QSTASH_URL="https://qstash.upstash.io"
QSTASH_TOKEN="your-qstash-token"

# EMAIL
EMAIL_USER="your-email@gmail.com"
EMAIL_PASSWORD="your-app-password"
```

> For Gmail, use an [App Password](https://support.google.com/accounts/answer/185833) rather than your account password.

---

## API Reference

All endpoints are prefixed with `/api/v1`. Protected routes require a `Bearer` token in the `Authorization` header.

### Authentication

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/auth/sign-up` | No | Register a new user |
| `POST` | `/auth/sign-in` | No | Login and receive a JWT |
| `POST` | `/auth/sign-out` | No | Confirm sign-out |

**Sign Up — Request Body:**
```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "password": "mypassword123"
}
```

**Sign In — Request Body:**
```json
{
  "email": "john@example.com",
  "password": "mypassword123"
}
```

**Response (sign-up / sign-in):**
```json
{
  "success": true,
  "message": "User created successfully",
  "data": {
    "token": "eyJhbGciOiJIUzI1...",
    "user": {
      "_id": "67a1...",
      "name": "John Doe",
      "email": "john@example.com",
      "createdAt": "2026-01-20T..."
    }
  }
}
```

---

### Users

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/users` | Yes | List all users (no passwords) |
| `GET` | `/users/:id` | Yes | Get a user by ID |
| `PUT` | `/users/:id` | Yes | Update own profile (name, email, password) |
| `DELETE` | `/users/:id` | Yes | Delete own account + all subscriptions |

---

### Subscriptions

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/subscriptions` | Yes | List own subscriptions (filter: `?status=`, `?category=`) |
| `GET` | `/subscriptions/:id` | Yes | Get a single subscription |
| `POST` | `/subscriptions` | Yes | Create a new subscription |
| `PUT` | `/subscriptions/:id` | Yes | Update subscription details |
| `PUT` | `/subscriptions/:id/cancel` | Yes | Cancel a subscription |
| `DELETE` | `/subscriptions/:id` | Yes | Delete a subscription |
| `GET` | `/subscriptions/upcoming-renewals` | Yes | Get renewals in next N days (`?days=7`) |
| `GET` | `/subscriptions/user/:id` | Yes | Get all subscriptions for a user |

**Create Subscription — Request Body:**
```json
{
  "name": "Netflix",
  "price": 15.99,
  "currency": "USD",
  "frequency": "monthly",
  "category": "entertainment",
  "paymentMethod": "Credit Card",
  "startDate": "2026-01-20T00:00:00.000Z"
}
```

**Allowed values:**

| Field | Options |
|---|---|
| `currency` | `USD`, `EUR`, `GBP` |
| `frequency` | `daily`, `weekly`, `monthly`, `yearly` |
| `category` | `sports`, `news`, `entertainment`, `lifestyle`, `technology`, `finance`, `politics`, `other` |
| `status` | `active`, `cancelled`, `expired` (auto-managed) |

> The `renewalDate` is auto-calculated from `startDate` + `frequency` if not provided. Status is automatically set to `expired` when the renewal date passes.

---

### Workflows

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/workflows/subscription/reminder` | Upstash workflow handler (called automatically) |

---

### Health & Root

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/` | Welcome message |
| `GET` | `/health` | Health check (`{ "status": "ok" }`) |

---

## Error Handling

All errors return a consistent JSON format:

```json
{
  "success": false,
  "error": "Error message here"
}
```

| Status | Meaning |
|---|---|
| `400` | Validation error / bad request |
| `401` | Unauthorized (missing/invalid/expired token) |
| `403` | Forbidden (not your resource) |
| `404` | Resource not found |
| `409` | Conflict (e.g. duplicate email) |
| `429` | Rate limit exceeded |
| `500` | Internal server error |

---

## Rate Limiting

Powered by [Arcjet](https://arcjet.com/):

- **Token bucket**: 50 request capacity, refills 20 tokens every 10 seconds
- **Bot detection**: Blocks automated bots (allows search engines)
- **Shield**: Protection against common attacks

Exceeding the rate limit returns:
```json
{ "error": "Rate limit exceeded" }
```

---

## Email Reminders

When a subscription is created, an Upstash workflow is triggered that sends email reminders at:

- **7 days** before renewal
- **5 days** before renewal
- **2 days** before renewal
- **1 day** before renewal

Emails include subscription details (plan name, price, payment method, renewal date) in a branded HTML template.

---

## Testing

A PowerShell test script is included that covers all endpoints:

```bash
# Start the server first
npm run dev

# In another terminal, run the tests
. ./test-api.ps1
```

The test suite covers:
- Basic endpoints (root, health check)
- Auth flow (sign-up, sign-in, duplicate detection, wrong credentials, sign-out)
- Authorization (no token, invalid token)
- User CRUD (list, get, update, not-found)
- Subscription CRUD (create, list, filter, get, update, cancel, double-cancel, delete)
- Validation (missing fields, invalid IDs, unknown routes)
- Cleanup (delete user with cascading subscription removal)

---

## License

This project is private and not licensed for redistribution.