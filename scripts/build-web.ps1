param(
    [switch]$LoveOnly,
    [string]$LoveJsRef = "9355186de22db13bd88bf2a0db75d2925647d036"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WebRoot = Join-Path $ProjectRoot "web"
$RuntimeRoot = Join-Path $WebRoot "11.5"
$LuaRoot = Join-Path $WebRoot "lua"
$GamePackage = Join-Path $WebRoot "game.love"
$StageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ashfall-love-" + [guid]::NewGuid())

function Get-UpstreamFile([string]$Path, [string]$Destination) {
    $url = "https://raw.githubusercontent.com/2dengine/love.js/$LoveJsRef/$Path"
    Write-Host "Downloading $Path"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Destination
}

try {
    New-Item -ItemType Directory -Force -Path $WebRoot, $RuntimeRoot, $LuaRoot, $StageRoot | Out-Null

    # (the raw asset packs stay out: the game uses its own copies in sprites/ and maps/)
    Get-ChildItem -Force $ProjectRoot |
        Where-Object { $_.Name -notin @(".git", "web", "scripts", "docs", "attached_assets", ".agents", ".local", ".cache", ".env", ".config", "cloudflare", "wrangler.jsonc", ".claude", "contracts", "node_modules", "package.json", "package-lock.json", ".gitignore", ".wrangler", ".dev.vars", "tests", "tiles", "hp-mana-stamina-and-scroll-bar-pixel-rpg-asset-pack", "Mana Capacity Math.docx", "dist", "farm", "blacksmith", "npcs are market") } |
        Copy-Item -Destination $StageRoot -Recurse -Force
    # (nor the maps' backups)
    Get-ChildItem -Force (Join-Path $StageRoot "maps") -Directory | Where-Object { $_.Name -like "_old*" } | Remove-Item -Recurse -Force

    if (Test-Path $GamePackage) {
        Remove-Item $GamePackage -Force
    }

    Compress-Archive -Path (Join-Path $StageRoot "*") -DestinationPath $GamePackage -CompressionLevel Optimal
    Write-Host "Created $GamePackage"

    # New b= numbers on the page's script and style links, so browsers load the
    # new index.html, style.css, bridge.js, menu.js and player.js after a deploy
    $IndexHtml = Join-Path $WebRoot "index.html"
    $BuildId = Get-Date -Format "yyyyMMddHHmm"
    $IndexSource = [System.IO.File]::ReadAllText($IndexHtml)
    $IndexSource = [regex]::Replace($IndexSource, '([?;]b=)\d+', '${1}' + $BuildId)
    [System.IO.File]::WriteAllText($IndexHtml, $IndexSource, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Stamped build $BuildId into index.html"

    if ($LoveOnly) {
        exit 0
    }

    Get-UpstreamFile "player.js" (Join-Path $WebRoot "player.js")
    $PlayerJs = Join-Path $WebRoot "player.js"
    $PlayerSource = Get-Content -Raw $PlayerJs
    $PlayerSource = $PlayerSource.Replace('fetch(uri, { credentials: "same-origin" })', 'fetch(uri, { credentials: "same-origin", cache: "no-store" })')
    Set-Content -Path $PlayerJs -Value $PlayerSource -NoNewline
    Get-UpstreamFile "11.5/love.js" (Join-Path $RuntimeRoot "love.js")
    Get-UpstreamFile "11.5/love.wasm" (Join-Path $RuntimeRoot "love.wasm")
    Get-UpstreamFile "lua/normalize1.lua" (Join-Path $LuaRoot "normalize1.lua")
    Get-UpstreamFile "lua/normalize2.lua" (Join-Path $LuaRoot "normalize2.lua")

    Write-Host "Web build is ready in $WebRoot"
}
finally {
    if (Test-Path $StageRoot) {
        Remove-Item $StageRoot -Recurse -Force
    }
}