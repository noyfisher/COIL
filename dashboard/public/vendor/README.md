# Vendored third-party assets

## echarts.min.js

- **Package:** [`echarts`](https://www.npmjs.com/package/echarts)
- **Version:** **5.6.0** (pinned — latest 5.x at the time of vendoring)
- **File:** `dist/echarts.min.js` from the published npm tarball, copied verbatim
- **License:** Apache License 2.0 — © The Apache Software Foundation / Apache ECharts contributors
  (<https://github.com/apache/echarts/blob/master/LICENSE>)
- **SHA-384:** `pPi0zxBAoDu6+JXW/C68UZLvBUUtU+7zonhif43rqj7pxsGyqyqzcian2Rj37Rss`

### Verifying integrity

```bash
./dashboard/verify-vendor.sh
```

Run this before deploying the dashboard. It recomputes each hash above and
exits non-zero on a mismatch, so an unfinished version bump or an edited
vendored file can't ship unnoticed.

Note this is a **pre-deploy check, not browser Subresource Integrity**. SRI
guards against a compromised third-party CDN, and there is no CDN here — the
file is same-origin from our own Hosting, and anyone able to alter it could
also strip the `integrity` attribute from the HTML. The downside would be real
though: ECharts renders every chart on both pages, so a hash off by one byte
would blank them with only a console error.

### Why vendored instead of a CDN

The dashboard must be self-contained apart from the Firebase JS SDK (which
Firebase Auth requires to be loaded from `gstatic.com`). A pinned local copy
means no third-party CDN in the request path, no version drift, and the page
still renders if a CDN is blocked or down.

### How to refresh it

```bash
cd /tmp
npm pack echarts@<version>
tar -xzf echarts-<version>.tgz package/dist/echarts.min.js
cp package/dist/echarts.min.js <repo>/dashboard/public/vendor/echarts.min.js
```

Then regenerate the hash:

```bash
openssl dgst -sha384 -binary dashboard/public/vendor/echarts.min.js | openssl base64 -A
```

and update **three** places: the version and **SHA-384** above, the matching
entry in `dashboard/verify-vendor.sh`, and the two
`<script src="vendor/echarts.min.js">` comments in `index.html` / `graphs.html`.
Finish by running `./dashboard/verify-vendor.sh` — it must print OK.

### Hosting note

`firebase.json` lists `**/vendor/README.md` in `hosting.ignore`, so this file is
never uploaded — only `echarts.min.js` ships.
