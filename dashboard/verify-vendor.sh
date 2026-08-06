#!/usr/bin/env bash
#
# Verify vendored third-party assets match the hashes recorded in
# dashboard/public/vendor/README.md.
#
# Run before deploying the dashboard:
#     ./dashboard/verify-vendor.sh
#
# Catches accidental drift (a half-finished version bump, a stray edit) and
# tampering in the committed tree. Exits non-zero on any mismatch.
#
# Deliberately NOT browser Subresource Integrity: SRI defends against a
# compromised third-party CDN, and there is no CDN in this request path — the
# file is same-origin from our own Firebase Hosting, where an attacker able to
# alter it could also strip the attribute from the HTML. Meanwhile a wrong
# `integrity=` hash blanks every chart on both pages with nothing but a console
# error. A pre-deploy check gets the drift detection without that failure mode.

set -euo pipefail

VENDOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/public/vendor"

# filename:expected-sha384-base64
EXPECTED=(
  "echarts.min.js:pPi0zxBAoDu6+JXW/C68UZLvBUUtU+7zonhif43rqj7pxsGyqyqzcian2Rj37Rss"
)

failed=0

for entry in "${EXPECTED[@]}"; do
  name="${entry%%:*}"
  want="${entry#*:}"
  file="$VENDOR_DIR/$name"

  if [[ ! -f "$file" ]]; then
    echo "MISSING  $name — expected at $file"
    failed=1
    continue
  fi

  got="$(openssl dgst -sha384 -binary "$file" | openssl base64 -A)"

  if [[ "$got" == "$want" ]]; then
    echo "OK       $name"
  else
    echo "MISMATCH $name"
    echo "         expected sha384-$want"
    echo "         actual   sha384-$got"
    echo "         If this was an intentional refresh, update the hash in"
    echo "         dashboard/public/vendor/README.md and in this script."
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then
  echo
  echo "Vendor verification FAILED — do not deploy."
  exit 1
fi

echo
echo "All vendored assets verified."
