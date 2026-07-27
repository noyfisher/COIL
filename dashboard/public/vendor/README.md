# Vendored third-party assets

## echarts.min.js

- **Package:** [`echarts`](https://www.npmjs.com/package/echarts)
- **Version:** **5.6.0** (pinned — latest 5.x at the time of vendoring)
- **File:** `dist/echarts.min.js` from the published npm tarball, copied verbatim
- **License:** Apache License 2.0 — © The Apache Software Foundation / Apache ECharts contributors
  (<https://github.com/apache/echarts/blob/master/LICENSE>)

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

Then update the version above, and the two `<script src="vendor/echarts.min.js">`
comments in `index.html` / `graphs.html`.

### Hosting note

`firebase.json` lists `**/vendor/README.md` in `hosting.ignore`, so this file is
never uploaded — only `echarts.min.js` ships.
