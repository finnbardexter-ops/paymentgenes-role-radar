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

# id must match the group ids used in docs/role-radar.html's EXCLUDE_GROUPS
$Companies = @(
    # Cross-Border, FX & Treasury
    @{ name = "Wise";                         ats = "smartrecruiters"; slug = "Wise";        cluster = "fx" }
    @{ name = "Airwallex";                    ats = "ashby";           slug = "airwallex";   cluster = "fx" }
    @{ name = "Convera";                      ats = "greenhouse";      slug = "convera";     cluster = "fx" }
    @{ name = "TransferGo";                   ats = "greenhouse";      slug = "transfergo";  cluster = "fx" }
    @{ name = "Thunes";                       ats = "greenhouse";      slug = "thunes";      cluster = "fx" }
    @{ name = "Nium";                         ats = "lever";           slug = "nium";        cluster = "fx" }

    # Acquiring, Merchant Services & POS
    @{ name = "Adyen";                        ats = "greenhouse";      slug = "adyen";       cluster = "acq" }
    @{ name = "Block";                        ats = "greenhouse";      slug = "block";       cluster = "acq" }
    @{ name = "Toast";                        ats = "greenhouse";      slug = "toast";       cluster = "acq" }
    @{ name = "SumUp";                        ats = "greenhouse";      slug = "sumup";       cluster = "acq" }
    @{ name = "Verifone";                     ats = "greenhouse";      slug = "verifone";    cluster = "acq" }
    @{ name = "Dojo";                         ats = "greenhouse";      slug = "dojo";        cluster = "acq" }

    # Issuing, Cards & Digital Wallets
    @{ name = "Marqeta";                      ats = "greenhouse";      slug = "marqeta";     cluster = "iss" }
    @{ name = "Galileo Financial Technologies"; ats = "greenhouse";    slug = "galileo";     cluster = "iss" }
    @{ name = "Lithic";                       ats = "greenhouse";      slug = "lithic";      cluster = "iss" }
    @{ name = "Highnote";                     ats = "greenhouse";      slug = "highnote";    cluster = "iss" }
    @{ name = "Brex";                         ats = "greenhouse";      slug = "brex";        cluster = "iss" }
    @{ name = "Ramp";                         ats = "ashby";           slug = "ramp";        cluster = "iss" }
    @{ name = "Visa";                         ats = "smartrecruiters"; slug = "Visa";        cluster = "iss" }

    # Fraud, Risk, Identity & Compliance Tech
    @{ name = "Sift";                         ats = "ashby";           slug = "sift";           cluster = "frc" }
    @{ name = "Persona";                       ats = "ashby";           slug = "persona";        cluster = "frc" }
    @{ name = "Socure";                        ats = "ashby";           slug = "socure";         cluster = "frc" }
    @{ name = "Sardine";                       ats = "ashby";           slug = "sardine";        cluster = "frc" }
    @{ name = "Alloy";                         ats = "lever";           slug = "alloy";          cluster = "frc" }
    @{ name = "Feedzai";                       ats = "greenhouse";      slug = "feedzai";        cluster = "frc" }
    @{ name = "ComplyAdvantage";               ats = "greenhouse";      slug = "complyadvantage"; cluster = "frc" }
    @{ name = "Forter";                        ats = "greenhouse";      slug = "forter";         cluster = "frc" }
    @{ name = "Riskified";                     ats = "greenhouse";      slug = "riskified";      cluster = "frc" }
    @{ name = "Seon";                          ats = "ashby";           slug = "seon";           cluster = "frc" }
    @{ name = "Elliptic";                      ats = "ashby";           slug = "elliptic";       cluster = "frc" }

    # Alternative Payments & Open Banking
    @{ name = "GoCardless";                   ats = "greenhouse";      slug = "gocardless"; cluster = "alt" }
    @{ name = "TrueLayer";                     ats = "greenhouse";      slug = "truelayer";  cluster = "alt" }
    @{ name = "Plaid";                         ats = "ashby";           slug = "plaid";      cluster = "alt" }
    @{ name = "Trustly";                       ats = "ashby";           slug = "trustly";    cluster = "alt" }
    @{ name = "Zip";                           ats = "ashby";           slug = "zip";        cluster = "alt" }
    @{ name = "Affirm";                        ats = "greenhouse";      slug = "affirm";     cluster = "alt" }

    # Crypto, Digital Assets & Web3 Payments
    @{ name = "Coinbase";                     ats = "greenhouse";      slug = "coinbase";    cluster = "cry" }
    @{ name = "Ripple";                        ats = "greenhouse";      slug = "ripple";      cluster = "cry" }
    @{ name = "Fireblocks";                    ats = "greenhouse";      slug = "fireblocks";  cluster = "cry" }
    @{ name = "MoonPay";                       ats = "lever";           slug = "moonpay";     cluster = "cry" }
    @{ name = "Gemini";                        ats = "greenhouse";      slug = "gemini";      cluster = "cry" }
    @{ name = "Paxos";                         ats = "ashby";           slug = "paxos";       cluster = "cry" }
    @{ name = "Blockdaemon";                   ats = "ashby";           slug = "blockdaemon"; cluster = "cry" }
    @{ name = "Anchorage Digital";             ats = "lever";           slug = "anchorage";   cluster = "cry" }
    @{ name = "Rain";                          ats = "ashby";           slug = "rain";        cluster = "cry" }

    # Banking Infrastructure & Embedded Finance
    @{ name = "Unit";                          ats = "ashby";           slug = "unit";         cluster = "bnk" }
    @{ name = "Synctera";                       ats = "ashby";           slug = "synctera";     cluster = "bnk" }
    @{ name = "Treasury Prime";                 ats = "greenhouse";      slug = "treasuryprime"; cluster = "bnk" }
    @{ name = "Increase";                       ats = "lever";           slug = "increase";     cluster = "bnk" }
    @{ name = "ClearBank";                      ats = "ashby";           slug = "clearbank";    cluster = "bnk" }
    @{ name = "Griffin";                        ats = "ashby";           slug = "griffin";      cluster = "bnk" }
    @{ name = "Column";                         ats = "ashby";           slug = "column";       cluster = "bnk" }
    @{ name = "Mercury";                        ats = "greenhouse";      slug = "mercury";      cluster = "bnk" }
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
