# Role Radar — PaymentGenes

A senior-roles job board for Fintech & Payments, adapted from the original
iGaming-focused Role Radar. Two independent pieces:

- **`docs/role-radar.html`** — the front-end. A static page: search, location
  filter, seniority filter, sort, and "Hide" chips for seven Fintech/Payments
  verticals. Reads `docs/feed.json` at load time; falls back to a small
  hardcoded sample if the feed can't be reached (e.g. opened directly from
  disk, or before the first scrape has run).
- **`scripts/build-feed.ps1`** — the scraper. Pulls live postings directly
  from each company's public applicant-tracking-system API (Greenhouse, Ashby,
  Lever, SmartRecruiters — all unauthenticated JSON endpoints) and writes
  `docs/feed.json`. Every company is pinned to exactly one of the seven
  clusters at scrape time (not guessed from the job title), so a "Software
  Engineer" posting from Coinbase lands in Crypto because Coinbase does.

## Clusters

1. Cross-Border, FX & Treasury
2. Acquiring, Merchant Services & POS
3. Issuing, Cards & Digital Wallets
4. Fraud, Risk, Identity & Compliance Tech
5. Alternative Payments & Open Banking
6. Crypto, Digital Assets & Web3 Payments
7. Banking Infrastructure & Embedded Finance

53 companies are currently configured across these clusters — see the
`$Companies` list at the top of `scripts/build-feed.ps1` to add, remove, or
re-cluster one. Add a company by finding its ATS job-board slug (usually
visible in its careers-page URL) and adding one line with `name`, `ats`
(`greenhouse` | `ashby` | `lever` | `smartrecruiters`), `slug`, and `cluster`.

## Running the scraper

```powershell
pwsh ./scripts/build-feed.ps1
```

Rewrites `docs/feed.json` in place. Takes about a minute for all 53
companies. Safe to re-run any time — it's a full rebuild, not an incremental
update.

## Local preview

`fetch()` needs `http://`, not `file://`, so open the page through a server,
not by double-clicking it:

```powershell
pwsh ./scripts/serve.ps1 -Port 8090
```

Then visit `http://localhost:8090/role-radar.html`.

## Automation

`.github/workflows/build-feed.yml` re-runs the scraper daily via GitHub
Actions and commits the refreshed `docs/feed.json`. If this repo is pushed to
GitHub with Pages enabled on `/docs`, the live site updates automatically —
same pattern the original project used (`cram-co/role-radar`).

## Known gaps / next steps

- **Branding chrome is a placeholder.** The nav/footer link to `index.html`,
  `services.html`, `pricing.html`, `enquire.html` — pages that don't exist
  yet. Swap in your real site or point Role Radar's nav at wherever those
  live.
- **Location bucketing** groups postings by country using a large lookup
  table (reused from the original project). Some smaller cities won't be
  recognized and will show up under their own name rather than their
  country — same long-tail limitation the original had.
- **No agency listings.** Every source here is a direct-employer career
  page. The `AGENCIES` badge mechanism in the front-end is still there but
  unused — wire it up if you add a recruiter-posted feed later.
- **Company list is a starting set, not exhaustive.** Companies were
  selected because they run a public ATS job board Greenhouse/Ashby/Lever/
  SmartRecruiters could be queried directly; some well-known Fintech/Payments
  names (e.g. companies on Workday) were left out because their listings
  require a different, per-tenant scraping approach.
