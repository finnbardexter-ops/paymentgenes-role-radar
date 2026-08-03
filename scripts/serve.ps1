<#
  Minimal static file server for local preview of docs/ (no Node/Python
  available in this environment). Serves docs/role-radar.html and
  docs/feed.json over plain HTTP so fetch() works, unlike file://.
#>
param(
    [int]$Port = 8090
)

$root = Join-Path $PSScriptRoot "..\docs"
$root = (Resolve-Path $root).Path

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port/ (Ctrl+C to stop)"

$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".svg"  = "image/svg+xml"
    ".js"   = "application/javascript"
    ".css"  = "text/css"
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        $path = $req.Url.AbsolutePath
        if ($path -eq "/") { $path = "/role-radar.html" }
        $file = Join-Path $root ($path.TrimStart("/"))

        if (Test-Path $file -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($file)
            $ct = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $res.ContentType = $ct
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $res.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $path")
            $res.OutputStream.Write($msg, 0, $msg.Length)
        }
        $res.OutputStream.Close()
    }
} finally {
    $listener.Stop()
}
