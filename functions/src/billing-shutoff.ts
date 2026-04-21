/**
 * Hard billing shutoff.
 *
 * Triggered by Pub/Sub messages from a GCP Cloud Billing budget alert.
 * When spend crosses SHUTOFF_THRESHOLD (default 1.2 = 120% of budget),
 * this disables billing on the project, which stops all billed services
 * (Cloud Functions, Firestore writes beyond free tier, Storage egress,
 * etc.) and prevents runaway cost.
 *
 * SAFETY:
 *  - Default is DRY_RUN=true → logs what it *would* do without actually
 *    disabling billing. Flip BILLING_SHUTOFF_ENABLED=true (env var) after
 *    you've verified the wiring works and you're ready to arm the trigger.
 *  - Idempotent: if billing is already disabled, it no-ops.
 *
 * SETUP:
 *  1. `gcloud pubsub topics create budget-alerts --project=pt-helper-dev`
 *  2. Link the existing budget to publish to that topic (see PR description).
 *  3. Deploy this function: `firebase deploy --only functions:onBudgetAlert`
 *  4. Grant the function's service account billing.projectManager role:
 *     `gcloud projects add-iam-policy-binding pt-helper-dev \
 *        --member=serviceAccount:pt-helper-dev@appspot.gserviceaccount.com \
 *        --role=roles/billing.projectManager`
 *  5. Verify in dry-run mode first. Then set
 *     `firebase functions:config:set billing.enabled=true` (or env var).
 */

import * as functions from "firebase-functions/v1";
import { CloudBillingClient } from "@google-cloud/billing";

interface BudgetNotification {
  budgetDisplayName?: string;
  costAmount?: number;
  costIntervalStart?: string;
  budgetAmount?: number;
  budgetAmountType?: string;
  currencyCode?: string;
  alertThresholdExceeded?: number;
}

const SHUTOFF_THRESHOLD = 1.2; // 120% of budget

function isArmed(): boolean {
  // Opt-in: real shutoff only happens when BILLING_SHUTOFF_ENABLED=true.
  // Anything else (unset, "false", "0") runs in dry-run mode.
  return process.env.BILLING_SHUTOFF_ENABLED === "true";
}

export const onBudgetAlert = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .pubsub.topic("budget-alerts")
  .onPublish(async (message) => {
    const payload = (message.json || {}) as BudgetNotification;
    const dryRun = !isArmed();

    functions.logger.info("budget_alert_received", {
      budgetDisplayName: payload.budgetDisplayName,
      costAmount: payload.costAmount,
      budgetAmount: payload.budgetAmount,
      currencyCode: payload.currencyCode,
      alertThresholdExceeded: payload.alertThresholdExceeded,
      dryRun,
    });

    // Use explicit type checks — costAmount can legitimately be 0 at the
    // start of a billing period, and `!0 === true` would wrongly trip the
    // missing-fields guard.
    if (typeof payload.costAmount !== "number" || typeof payload.budgetAmount !== "number") {
      functions.logger.warn("budget_alert_missing_fields", { payload });
      return;
    }

    if (payload.budgetAmount <= 0) {
      functions.logger.warn("budget_alert_invalid_budget", { payload });
      return;
    }

    const ratio = payload.costAmount / payload.budgetAmount;
    if (ratio < SHUTOFF_THRESHOLD) {
      functions.logger.info("budget_under_shutoff_threshold", {
        ratio,
        threshold: SHUTOFF_THRESHOLD,
      });
      return;
    }

    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
    if (!projectId) {
      functions.logger.error("budget_shutoff_no_project_env");
      return;
    }
    const projectName = `projects/${projectId}`;

    const client = new CloudBillingClient();
    const [current] = await client.getProjectBillingInfo({ name: projectName });

    if (!current.billingEnabled) {
      functions.logger.warn("billing_already_disabled", { projectName });
      return;
    }

    if (dryRun) {
      functions.logger.error("budget_shutoff_DRY_RUN_would_disable_billing", {
        projectName,
        costAmount: payload.costAmount,
        budgetAmount: payload.budgetAmount,
        ratio,
        note: "Set BILLING_SHUTOFF_ENABLED=true env var to arm real shutoff.",
      });
      return;
    }

    functions.logger.error("budget_shutoff_triggered", {
      projectName,
      costAmount: payload.costAmount,
      budgetAmount: payload.budgetAmount,
      ratio,
    });

    await client.updateProjectBillingInfo({
      name: projectName,
      projectBillingInfo: { billingAccountName: "" },
    });

    functions.logger.error("billing_disabled", { projectName });
  });
