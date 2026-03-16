# API Reference

PT Helper uses a Firebase Cloud Function (`claudeProxy`) as a secure proxy between the iOS app and the Anthropic Claude API. The API key, system prompts, and model configuration are all stored server-side.

## Endpoint

```
POST https://us-central1-<project-id>.cloudfunctions.net/claudeProxy
```

## Authentication

All requests require a valid Firebase ID token in the `Authorization` header:

```
Authorization: Bearer <firebase-id-token>
```

The token is obtained via `Auth.auth().currentUser.getIDToken()` on the iOS side.

## Request

### Headers

| Header | Value |
|--------|-------|
| `Content-Type` | `application/json` |
| `Authorization` | `Bearer <firebase-id-token>` |

### Body

```json
{
  "requestType": "analysis" | "rehab_plan",
  "messages": [
    {
      "role": "user",
      "content": "<user message string>"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `requestType` | `string` | Determines which server-side system prompt and model config to use. Must be `"analysis"` or `"rehab_plan"`. |
| `messages` | `array` | Array of message objects. Currently only a single user message is sent. |

### Message Content Limits

- Total message content across all messages: **10,000 characters max**
- Exceeding this returns a `400` error

## Response

On success, the proxy passes through the Anthropic API response directly:

```json
{
  "content": [
    {
      "type": "text",
      "text": "<JSON string>"
    }
  ],
  "stop_reason": "end_turn"
}
```

The `text` field contains a JSON string whose schema depends on the `requestType`.

### Analysis Response Schema

```json
{
  "conditions": [
    {
      "conditionName": "Patellofemoral Pain Syndrome",
      "commonName": "Runner's Knee",
      "confidence": 75,
      "explanation": "...",
      "whatItMeans": "...",
      "howToManage": "...",
      "isRedFlag": false,
      "redFlagMessage": null,
      "nextSteps": ["Step 1", "Step 2"]
    }
  ],
  "overallSummary": "...",
  "disclaimerText": "This is not a medical diagnosis..."
}
```

### Rehab Plan Response Schema

```json
{
  "planName": "Knee Recovery Plan",
  "exercises": [
    {
      "name": "Quad Sets",
      "targetArea": "Quadriceps",
      "description": "...",
      "sets": 3,
      "reps": "10-15",
      "restSeconds": 30,
      "difficulty": "beginner",
      "demonstrationIcon": "figure.strengthtraining.traditional",
      "tips": ["Keep back flat", "..."],
      "contraindications": ["Avoid if..."],
      "startPosition": "...",
      "movement": "...",
      "endPosition": "...",
      "exerciseCategory": "strength",
      "imageFileName": "quad-sets"
    }
  ],
  "totalWeeks": 6,
  "notes": "..."
}
```

## Error Responses

| Status | Error | Description |
|--------|-------|-------------|
| `400` | `Missing required fields: requestType, messages` | Request body missing required fields |
| `400` | `Invalid requestType` | `requestType` not in allowed set |
| `400` | `Message content too long` | Total message content exceeds 10,000 characters |
| `401` | `Missing or invalid Authorization header` | No Bearer token provided |
| `401` | `Invalid Firebase ID token` | Token expired or invalid |
| `405` | `Method not allowed` | Non-POST request |
| `429` | `Rate limit exceeded` | More than 20 requests per minute for this user |
| `500` | `Server configuration error` | `ANTHROPIC_API_KEY` not set in environment |
| `502` | `Failed to reach AI service` | Anthropic API unreachable |

## Rate Limiting

- **20 requests per minute** per authenticated user
- In-memory sliding window per Cloud Function instance
- Returns `429` when exceeded

## Server-Side Configuration

These are NOT configurable by the client:

| Request Type | Model | Max Tokens |
|-------------|-------|------------|
| `analysis` | `claude-haiku-4-5-20251001` | 2048 |
| `rehab_plan` | `claude-haiku-4-5-20251001` | 4096 |

## iOS Client

The iOS app uses `ClaudeAPIService.sendMessage(requestType:userMessage:)` to call this endpoint. It handles:

- Firebase Auth token retrieval
- Request encoding
- Response decoding and JSON cleanup (strips markdown fences)
- Error mapping to `ClaudeAPIError` cases

## Deployment

```bash
cd functions
npm install
firebase deploy --only functions
```

The `ANTHROPIC_API_KEY` must be set as a Firebase secret:

```bash
firebase functions:secrets:set ANTHROPIC_API_KEY
```
