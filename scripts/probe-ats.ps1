<#
  One-off probe: for each (cluster, company name) pair, guess ATS slugs and
  test them against Greenhouse/Ashby/Lever/SmartRecruiters concurrently using
  a single HttpClient (async Tasks), not subprocesses. Spawning a curl
  process per request was the bottleneck on this host, not network latency.
#>
param(
    [string]$InputTsv,
    [string]$OutputTsv
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

$handler = New-Object System.Net.Http.HttpClientHandler
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromSeconds(10)
$client.DefaultRequestHeaders.Add("User-Agent", "role-radar-probe")

function Slugify([string]$s) {
    return ($s.ToLower() -replace '[^a-z0-9]', '')
}

function PascalWords([string]$s) {
    $words = ($s -replace '[^a-zA-Z0-9\s]', ' ') -split '\s+' | Where-Object { $_ }
    return ($words | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }) -join ""
}

$rows = Get-Content $InputTsv | ForEach-Object {
    $parts = $_ -split "`t"
    if ($parts.Count -ge 2) {
        [PSCustomObject]@{ cluster = $parts[0]; name = $parts[1] }
    }
}

$targets = New-Object System.Collections.Generic.List[object]
foreach ($r in $rows) {
    $full = Slugify $r.name
    $short = Slugify (($r.name -split '\s+')[0])
    $variants = @($full, $short) | Select-Object -Unique
    foreach ($v in $variants) {
        if (-not $v) { continue }
        $targets.Add([PSCustomObject]@{ cluster=$r.cluster; name=$r.name; ats="greenhouse"; slug=$v; url="https://boards-api.greenhouse.io/v1/boards/$v/jobs?content=false" })
        $targets.Add([PSCustomObject]@{ cluster=$r.cluster; name=$r.name; ats="ashby"; slug=$v; url="https://api.ashbyhq.com/posting-api/job-board/$v" })
        $targets.Add([PSCustomObject]@{ cluster=$r.cluster; name=$r.name; ats="lever"; slug=$v; url="https://api.lever.co/v0/postings/$v`?mode=json" })
    }
    $srCandidates = @((PascalWords $r.name), (PascalWords (($r.name -split '\s+')[0]))) | Select-Object -Unique
    foreach ($sr in $srCandidates) {
        if (-not $sr) { continue }
        $targets.Add([PSCustomObject]@{ cluster=$r.cluster; name=$r.name; ats="smartrecruiters"; slug=$sr; url="https://api.smartrecruiters.com/v1/companies/$([uri]::EscapeDataString($sr))/postings?limit=1" })
    }
}

Write-Host "Probing $($targets.Count) URLs for $($rows.Count) companies..."

# Fire requests in capped-concurrency batches of async Tasks (no subprocesses).
$results = New-Object System.Collections.Generic.List[object]
$batchSize = 40
for ($i = 0; $i -lt $targets.Count; $i += $batchSize) {
    $batch = $targets[$i..[Math]::Min($i + $batchSize - 1, $targets.Count - 1)]
    $tasks = @{}
    foreach ($t in $batch) {
        $tasks[$t] = $client.GetStringAsync($t.url)
    }
    foreach ($t in $batch) {
        try {
            $body = $tasks[$t].GetAwaiter().GetResult()
            $count = 0
            $ok = $false
            if ($t.ats -eq "smartrecruiters") {
                if ($body -match '"totalFound":(\d+)') {
                    $count = [int]$Matches[1]
                    $ok = $count -gt 0
                }
            } else {
                $count = ([regex]::Matches($body, '"id"\s*:')).Count
                $ok = $count -gt 0
            }
            if ($ok) {
                $results.Add([PSCustomObject]@{ cluster=$t.cluster; name=$t.name; ats=$t.ats; slug=$t.slug; count=$count })
            }
        } catch { }
    }
    Write-Host "  ...$([Math]::Min($i+$batchSize,$targets.Count))/$($targets.Count)"
}

$results | ForEach-Object { "$($_.cluster)`t$($_.name)`t$($_.ats)`t$($_.slug)`t$($_.count)" } | Set-Content -Path $OutputTsv -Encoding utf8
Write-Host "Wrote $($results.Count) hits to $OutputTsv"
