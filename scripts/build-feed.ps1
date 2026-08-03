<#
  Role Radar (PaymentGenes) feed builder.

  Pulls live postings directly from each company's public applicant-tracking-system
  API (Greenhouse / Ashby / Lever / SmartRecruiters — all unauthenticated, JSON,
  CORS-open job-board endpoints) and writes them into a single docs/feed.json in
  the shape the front-end (docs/role-radar.html) expects:

    { "generated_at": "<ISO8601>", "jobs": [ {company,title,location,url,posted_at,cluster}, ... ] }

  Each company is pinned to exactly one of the seven Fintech/Payments clusters
  below at scrape time (see $Companies) rather than guessed from the job title —
  a "Software Engineer" posting from Coinbase belongs in Crypto because Coinbase
  does, not because its title happens to contain a crypto keyword.

  Run locally:   pwsh ./scripts/build-feed.ps1
  Run in CI:     see .github/workflows/build-feed.yml (same script, same shell)
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# id must match the group ids used in docs/role-radar.html's EXCLUDE_GROUPS.
# This is the client-provided company list (7 verticals, ~270 names). Only the
# subset below actually exposes a public, unauthenticated ATS job-board API
# (Greenhouse/Ashby/Lever/SmartRecruiters) that this script can query directly —
# most of the rest run on Workday, iCIMS, SuccessFactors, or a bespoke careers
# page, which each need their own scraping approach. See README's "Known gaps"
# section for the full list of what's not yet wired up.
$Companies = @(
    # Cross-Border, FX & Treasury
    @{ name = "Airwallex";           ats = "ashby";           slug = "airwallex";        cluster = "fx" }
    @{ name = "dLocal";              ats = "lever";           slug = "dlocal";           cluster = "fx" }
    @{ name = "EBANX";               ats = "greenhouse";      slug = "ebanx";            cluster = "fx" }
    @{ name = "Payoneer";            ats = "greenhouse";      slug = "payoneer";         cluster = "fx" }
    @{ name = "Ripple";              ats = "greenhouse";      slug = "ripple";           cluster = "fx" }
    @{ name = "Thunes";              ats = "greenhouse";      slug = "thunes";           cluster = "fx" }
    @{ name = "Wise Platform";       ats = "smartrecruiters"; slug = "Wise";             cluster = "fx" }
    @{ name = "Capi Money";          ats = "ashby";           slug = "capimoney";        cluster = "fx" }
    @{ name = "Crown Agents Bank";   ats = "smartrecruiters"; slug = "CrownAgentsBank";  cluster = "fx" }
    @{ name = "Runa";                ats = "ashby";           slug = "runa";             cluster = "fx" }
    @{ name = "TransferGo";          ats = "greenhouse";      slug = "transfergo";       cluster = "fx" }
    @{ name = "Nium";                ats = "lever";           slug = "nium";             cluster = "fx" }

    # Acquiring, Merchant Services & POS
    @{ name = "Adyen";               ats = "greenhouse";      slug = "adyen";           cluster = "acq" }
    @{ name = "Block";               ats = "greenhouse";      slug = "block";           cluster = "acq" }
    @{ name = "Cleverbridge";        ats = "smartrecruiters"; slug = "Cleverbridge";    cluster = "acq" }
    @{ name = "Mollie";              ats = "ashby";           slug = "mollie";          cluster = "acq" }
    @{ name = "Monext";              ats = "smartrecruiters"; slug = "Monext";          cluster = "acq" }
    @{ name = "Toast";               ats = "greenhouse";      slug = "toast";           cluster = "acq" }
    @{ name = "Visa";                ats = "smartrecruiters"; slug = "Visa";            cluster = "acq" }
    @{ name = "Citcon";              ats = "lever";           slug = "citcon";          cluster = "acq" }
    @{ name = "Stone";               ats = "greenhouse";      slug = "stone";           cluster = "acq" }

    # Issuing, Cards & Digital Wallets
    @{ name = "Marqeta";             ats = "greenhouse";      slug = "marqeta";  cluster = "iss" }
    @{ name = "Pliant";              ats = "ashby";           slug = "pliant";   cluster = "iss" }
    @{ name = "Onbe";                ats = "greenhouse";      slug = "onbe";     cluster = "iss" }
    @{ name = "Tillo";               ats = "ashby";           slug = "tillo";    cluster = "iss" }

    # Banking Infrastructure & Embedded Finance
    @{ name = "ClearBank";           ats = "ashby";           slug = "clearbank"; cluster = "bnk" }
    @{ name = "Form3";               ats = "greenhouse";      slug = "form3";     cluster = "bnk" }
    @{ name = "Column";              ats = "ashby";           slug = "column";    cluster = "bnk" }
    @{ name = "ConnectPay";          ats = "smartrecruiters"; slug = "Connectpay"; cluster = "bnk" }
    @{ name = "Fonoa Technologies";  ats = "ashby";           slug = "fonoa";     cluster = "bnk" }
    @{ name = "Griffin";             ats = "ashby";           slug = "griffin";   cluster = "bnk" }
    @{ name = "LHV UK";              ats = "greenhouse";      slug = "lhvuk";     cluster = "bnk" }
    @{ name = "Numeral";             ats = "ashby";           slug = "numeral";   cluster = "bnk" }
    @{ name = "Taktile";             ats = "ashby";           slug = "taktile";   cluster = "bnk" }

    # Alternative Payments & Open Banking
    @{ name = "GoCardless";          ats = "greenhouse";      slug = "gocardless"; cluster = "alt" }
    @{ name = "Plaid";               ats = "ashby";           slug = "plaid";      cluster = "alt" }
    @{ name = "TrueLayer";           ats = "greenhouse";      slug = "truelayer";  cluster = "alt" }
    @{ name = "Trustly";             ats = "ashby";           slug = "trustly";    cluster = "alt" }

    # Fraud, Risk, Identity & Compliance Tech
    @{ name = "ComplyAdvantage";     ats = "greenhouse";      slug = "complyadvantage"; cluster = "frc" }
    @{ name = "Experian";            ats = "smartrecruiters"; slug = "Experian";        cluster = "frc" }
    @{ name = "Seon";                ats = "ashby";           slug = "seon";            cluster = "frc" }
    @{ name = "Trulioo";             ats = "ashby";           slug = "trulioo";         cluster = "frc" }
    @{ name = "Veriff";              ats = "greenhouse";      slug = "veriff";          cluster = "frc" }
    @{ name = "Guardsquare";         ats = "greenhouse";      slug = "guardsquare";     cluster = "frc" }
    @{ name = "Incode Technologies"; ats = "greenhouse";      slug = "incode";          cluster = "frc" }
    @{ name = "Incognia";            ats = "greenhouse";      slug = "incognia";        cluster = "frc" }
    @{ name = "Oscilar";             ats = "ashby";           slug = "oscilar";         cluster = "frc" }
    @{ name = "Persona";             ats = "ashby";           slug = "persona";         cluster = "frc" }
    @{ name = "Quantexa";            ats = "ashby";           slug = "quantexa";        cluster = "frc" }

    # Crypto, Digital Assets & Web3 Payments
    @{ name = "BitGo";               ats = "greenhouse";      slug = "bitgo";      cluster = "cry" }
    @{ name = "BVNK";                ats = "greenhouse";      slug = "bvnk";       cluster = "cry" }
    @{ name = "Coinbase";            ats = "greenhouse";      slug = "coinbase";   cluster = "cry" }
    @{ name = "Fireblocks";          ats = "greenhouse";      slug = "fireblocks"; cluster = "cry" }
    @{ name = "Gemini";              ats = "greenhouse";      slug = "gemini";     cluster = "cry" }
    @{ name = "MoonPay";             ats = "lever";           slug = "moonpay";    cluster = "cry" }
    @{ name = "B2C2";                ats = "greenhouse";      slug = "b2c2";       cluster = "cry" }
    @{ name = "Turnkey";             ats = "ashby";           slug = "turnkey";    cluster = "cry" }
)

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Invoke-RestMethod on Windows PowerShell 5.1 falls back to Latin-1 when a
# response's Content-Type omits a charset (which Greenhouse/SmartRecruiters
# do), corrupting every non-ASCII character ("München" -> "MÃ¼nchen"). A
# WebClient forced to UTF-8 sidesteps that guesswork entirely.
function Get-Json($Url) {
    try {
        $client = New-Object System.Net.WebClient
        $client.Encoding = $Utf8NoBom
        $client.Headers.Add("User-Agent", "role-radar-feed-builder")
        $raw = $client.DownloadString($Url)
        return $raw | ConvertFrom-Json
    } catch {
        Write-Warning "  fetch failed: $Url ($($_.Exception.Message))"
        return $null
    }
}

function Get-Greenhouse($Company) {
    $d = Get-Json "https://boards-api.greenhouse.io/v1/boards/$($Company.slug)/jobs?content=false"
    if (-not $d) { return @() }
    $d.jobs | ForEach-Object {
        [PSCustomObject]@{
            company   = $Company.name
            title     = $_.title
            location  = $_.location.name
            url       = $_.absolute_url
            posted_at = if ($_.first_published) { $_.first_published } else { $_.updated_at }
            cluster   = $Company.cluster
        }
    }
}

function Get-Ashby($Company) {
    $d = Get-Json "https://api.ashbyhq.com/posting-api/job-board/$($Company.slug)"
    if (-not $d) { return @() }
    $d.jobs | ForEach-Object {
        [PSCustomObject]@{
            company   = $Company.name
            title     = $_.title
            location  = $_.location
            url       = $_.jobUrl
            posted_at = $_.publishedAt
            cluster   = $Company.cluster
        }
    }
}

function Get-Lever($Company) {
    $d = Get-Json "https://api.lever.co/v0/postings/$($Company.slug)?mode=json"
    if (-not $d) { return @() }
    $d | ForEach-Object {
        $posted = $null
        if ($_.createdAt) {
            $posted = ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$_.createdAt)).ToString("o")
        }
        [PSCustomObject]@{
            company   = $Company.name
            title     = $_.text
            location  = $_.categories.location
            url       = $_.hostedUrl
            posted_at = $posted
            cluster   = $Company.cluster
        }
    }
}

function Get-SmartRecruiters($Company) {
    $all = New-Object System.Collections.Generic.List[object]
    $offset = 0
    $limit = 100
    do {
        $d = Get-Json "https://api.smartrecruiters.com/v1/companies/$($Company.slug)/postings?offset=$offset&limit=$limit"
        if (-not $d -or -not $d.content) { break }
        foreach ($p in $d.content) {
            $loc = $p.location.city
            if ($p.location.country) { $loc = "$loc, $($p.location.country.ToUpper())" }
            $all.Add([PSCustomObject]@{
                company   = $Company.name
                title     = $p.name
                location  = $loc
                url       = "https://jobs.smartrecruiters.com/$($Company.slug)/$($p.id)"
                posted_at = $p.releasedDate
                cluster   = $Company.cluster
            })
        }
        $offset += $limit
    } while ($offset -lt $d.totalFound)
    return $all
}

$jobs = New-Object System.Collections.Generic.List[object]
foreach ($c in $Companies) {
    Write-Host "Fetching $($c.name) ($($c.ats))..."
    $found = switch ($c.ats) {
        "greenhouse"      { Get-Greenhouse $c }
        "ashby"           { Get-Ashby $c }
        "lever"           { Get-Lever $c }
        "smartrecruiters" { Get-SmartRecruiters $c }
    }
    $n = 0
    foreach ($j in $found) { $jobs.Add($j); $n++ }
    Write-Host "  -> $n roles"
}

$feed = [PSCustomObject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    jobs         = $jobs
}

$outDir = Join-Path $PSScriptRoot "..\docs"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outFile = Join-Path $outDir "feed.json"
$json = $feed | ConvertTo-Json -Depth 6 -Compress
[System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`nWrote $($jobs.Count) roles from $($Companies.Count) companies to $outFile"
