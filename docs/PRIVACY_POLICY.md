# Privacy Policy

**PT Helper**
**Last Updated: March 2025**

## Overview

PT Helper ("the App") is a wellness guidance application that uses artificial intelligence to help users understand their pain and follow personalized exercise plans. This privacy policy explains what data we collect, how we use it, and your rights.

## Data We Collect

### Account Information
- **Authentication data**: Email address and authentication provider (Apple ID or Google) via Firebase Authentication
- **User ID**: A unique identifier assigned by Firebase

### Health Profile (User-Provided)
- Name, date of birth, sex, height, weight
- Medical conditions and medications
- Surgical history (procedure name, year, body area, recovery status, restrictions)
- Injury history (body area, description, timing, doctor visits, PT history, recovery status)
- Activity level and primary sport

### Pain Assessments (User-Provided)
- Body regions experiencing pain
- Pain characteristics (type, intensity, duration, frequency, onset)
- Aggravating and relieving factors
- Treatment history (doctor visits, imaging, diagnosis, current treatment)
- Additional notes

### Generated Data
- AI-generated analysis results (possible conditions, recommendations)
- Rehab exercise plans
- Workout session records (exercises completed, duration)
- Personal notes
- Session logs (for debugging and app improvement)

### Automatically Collected
- Crash reports (via Firebase Crashlytics) — device model, OS version, crash stack traces
- Missing exercise image reports (exercise name only, no personal data)

## How We Use Your Data

| Purpose | Data Used |
|---------|-----------|
| Generate AI analysis | Health profile, pain assessments |
| Create rehab plans | Analysis results, health profile, medications |
| Safety validation | Medical conditions, medications, surgical history |
| Track workout progress | Workout session records |
| App debugging | Session logs, crash reports |

### AI Processing
Your health profile and pain assessment data is sent to Anthropic's Claude API (via our Firebase Cloud Function proxy) to generate analysis results and rehab plans. The data is:
- Transmitted over HTTPS
- Not stored by Anthropic beyond the API request
- Processed with server-side system prompts (not user-controlled)

## Data Storage

- All user data is stored in **Google Cloud Firestore** (Firebase)
- Data is encrypted in transit (TLS) and at rest (Google Cloud encryption)
- Each user can only access their own data (enforced by Firestore security rules)
- No user data is shared between accounts

## Data Retention

- Your data is retained as long as your account is active
- You can delete your account and all associated data at any time through the app settings
- Crash reports are retained per Firebase Crashlytics default retention (90 days)

## Third-Party Services

| Service | Purpose | Data Shared |
|---------|---------|-------------|
| Firebase Authentication | User login | Email, auth provider |
| Google Cloud Firestore | Data storage | All user data (encrypted) |
| Firebase Crashlytics | Crash reporting | Device info, crash data (no health data) |
| Anthropic Claude API | AI analysis | Health profile + pain data per request |

## Your Rights

You have the right to:
- **Access** your data through the app
- **Correct** your health profile at any time
- **Delete** your account and all data
- **Export** your rehab plans as PDF

## Children's Privacy

PT Helper is not intended for use by children under 13. We do not knowingly collect data from children.

## Health Data Disclaimer

PT Helper provides **wellness guidance only, not medical diagnosis**. The AI-generated analysis and exercise recommendations are educational and should not replace professional medical advice. Always consult a healthcare provider for medical concerns.

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be posted within the app and on our website.

## Contact

For privacy questions or data requests, contact: noyfisher2003@gmail.com