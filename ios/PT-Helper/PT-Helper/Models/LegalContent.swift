import Foundation

/// Embedded legal document content for in-app display.
/// Content sourced from docs/PRIVACY_POLICY.md and docs/TERMS_OF_SERVICE.md.
/// Markdown tables are converted to bullet lists for SwiftUI rendering compatibility.
enum LegalContent {

    // MARK: - Privacy Policy

    static let privacyPolicy: String = #"""
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

    - **Generate AI analysis**: Uses health profile and pain assessments
    - **Create rehab plans**: Uses analysis results, health profile, and medications
    - **Safety validation**: Uses medical conditions, medications, and surgical history
    - **Track workout progress**: Uses workout session records
    - **App debugging**: Uses session logs and crash reports

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

    - **Firebase Authentication**: User login — shares email and auth provider
    - **Google Cloud Firestore**: Data storage — stores all user data (encrypted)
    - **Firebase Crashlytics**: Crash reporting — shares device info and crash data (no health data)
    - **Anthropic Claude API**: AI analysis — shares health profile and pain data per request

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
    """#

    // MARK: - Terms of Service

    static let termsOfService: String = #"""
    # Terms of Service

    **PT Helper**
    **Last Updated: March 2025**

    ## 1. Acceptance of Terms

    By downloading, installing, or using PT Helper ("the App"), you agree to these Terms of Service. If you do not agree, do not use the App.

    ## 2. Description of Service

    PT Helper is a wellness guidance application that uses artificial intelligence to:
    - Help users understand potential causes of musculoskeletal pain
    - Generate personalized exercise and rehabilitation plans
    - Guide users through workout sessions
    - Track rehabilitation progress

    ## 3. Medical Disclaimer

    **PT Helper is NOT a medical device and does NOT provide medical diagnosis, treatment, or advice.**

    - All analysis results are educational and informational only
    - AI-generated conditions and recommendations are possible explanations, not diagnoses
    - Confidence scores reflect pattern matching, not clinical certainty
    - Exercise plans are general wellness guidance, not prescribed treatment

    **You should:**
    - Consult a qualified healthcare provider before starting any exercise program
    - Seek immediate medical attention for severe, worsening, or emergency symptoms
    - Not delay seeking professional medical advice based on App content
    - Follow your doctor's or physical therapist's guidance over App recommendations

    **The App will alert you to potential emergency symptoms (red flags), but this detection is not comprehensive and should not replace medical judgment.**

    ## 4. User Responsibilities

    You agree to:
    - Provide accurate health information in your profile
    - Not rely solely on the App for medical decisions
    - Stop any exercise that causes pain beyond normal discomfort
    - Consult a healthcare provider for serious or persistent conditions
    - Keep your account credentials secure

    ## 5. Account and Data

    - You must be at least 13 years old to use the App
    - You are responsible for all activity under your account
    - You may delete your account and data at any time
    - We may suspend accounts that violate these terms

    ## 6. Intellectual Property

    - The App, including its design, code, AI prompts, and exercise content, is protected by copyright
    - AI-generated analysis results and rehab plans are provided for your personal use
    - Exercise illustrations are generated using licensed AI models and are for in-app use only

    ## 7. Limitations of AI

    The AI system has inherent limitations:
    - It cannot perform physical examinations
    - It may not identify all possible conditions
    - It cannot account for all individual factors
    - Exercise recommendations may not be appropriate for everyone
    - The safety validation pipeline reduces but does not eliminate risk of inappropriate recommendations

    ## 8. Limitation of Liability

    To the maximum extent permitted by law:
    - The App is provided "as is" without warranty of any kind
    - We are not liable for any injury, harm, or damages arising from use of the App
    - We are not responsible for the accuracy of AI-generated content
    - Our total liability shall not exceed the amount you paid for the App

    ## 9. Indemnification

    You agree to indemnify and hold harmless PT Helper, its developers, and affiliates from any claims, damages, or expenses arising from your use of the App or violation of these terms.

    ## 10. Changes to Terms

    We may modify these terms at any time. Continued use of the App after changes constitutes acceptance of the new terms.

    ## 11. Governing Law

    These terms are governed by the laws of the State of California, United States.

    ## 12. Contact

    For questions about these terms, contact: noyfisher2003@gmail.com
    """#
}
