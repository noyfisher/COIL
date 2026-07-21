#!/bin/bash
#
# Upload generated exercise images to Firebase Storage.
#
# Prerequisites:
#   1. Firebase Storage must be ACTIVATED in the Firebase Console:
#      → https://console.firebase.google.com/project/pt-helper-dev/storage
#      → Click "Get Started" → choose "Start in test mode" → pick region → Done
#   2. gcloud CLI authenticated: gcloud auth login
#   3. gsutil available (comes with Google Cloud SDK)
#
# Usage:
#   ./upload_to_firebase.sh
#   ./upload_to_firebase.sh --dry-run
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BUCKET="gs://pt-helper-dev.firebasestorage.app"
STORAGE_PATH="exercise-images"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE — no files will be uploaded"
    echo
fi

# Check for images
PNG_COUNT=$(find "${OUTPUT_DIR}" -name "*.png" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "${PNG_COUNT}" -eq 0 ]]; then
    echo "ERROR: No PNG files found in ${OUTPUT_DIR}"
    echo "Run generate_exercise_images.py first."
    exit 1
fi

echo "Found ${PNG_COUNT} images to upload"
echo "Destination: ${BUCKET}/${STORAGE_PATH}/"
echo

# Check if gsutil is available
if ! command -v gsutil &>/dev/null; then
    echo "ERROR: gsutil not found."
    echo "Install Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    echo "Or use: brew install google-cloud-sdk"
    exit 1
fi

# Check if gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
    echo "ERROR: gcloud is not authenticated."
    echo ""
    echo "Run:  gcloud auth login"
    echo ""
    echo "Then retry this script."
    exit 1
fi

# Check if bucket exists
if ! gsutil ls "${BUCKET}" &>/dev/null; then
    echo "ERROR: Firebase Storage bucket does not exist yet!"
    echo ""
    echo "You need to activate Firebase Storage in the Firebase Console:"
    echo ""
    echo "  1. Open: https://console.firebase.google.com/project/pt-helper-dev/storage"
    echo "  2. Click 'Get Started'"
    echo "  3. Select 'Start in test mode' (we'll secure it later)"
    echo "  4. Choose a Cloud Storage location (e.g., us-central1)"
    echo "  5. Click 'Done'"
    echo ""
    echo "After activation, re-run this script."
    exit 1
fi

if [[ "${DRY_RUN}" == true ]]; then
    echo "Would upload:"
    find "${OUTPUT_DIR}" -name "*.png" -type f | while read -r file; do
        filename=$(basename "${file}")
        echo "  ${filename} → ${BUCKET}/${STORAGE_PATH}/${filename}"
    done
    echo
    echo "Also would upload mapping file:"
    echo "  exercise_image_mapping.json → ${BUCKET}/${STORAGE_PATH}/exercise_image_mapping.json"
else
    echo "Uploading images..."
    gsutil -m cp "${OUTPUT_DIR}"/*.png "${BUCKET}/${STORAGE_PATH}/"

    echo
    echo "Uploading mapping file..."
    gsutil cp "${OUTPUT_DIR}/exercise_image_mapping.json" "${BUCKET}/${STORAGE_PATH}/exercise_image_mapping.json"

    echo
    echo "Upload complete!"
    echo
    echo "Uploaded ${PNG_COUNT} images to ${BUCKET}/${STORAGE_PATH}/"
fi

echo
echo "Next steps:"
echo "  1. Ensure exercise_image_mapping.json is in ios/PT-Helper/COIL/Resources/"
echo "  2. Build and test the app"
