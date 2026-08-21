$env:HOME = $env:USERPROFILE
$env:USER = $env:USERNAME
$env:DOTFILES = (Get-Item $PSScriptRoot).Parent.FullName

[Environment]::SetEnvironmentVariable("HOME", $env:HOME, "User")
[Environment]::SetEnvironmentVariable("USER", $env:USER, "User")
[Environment]::SetEnvironmentVariable("DOTFILES", $env:DOTFILES, "User")

Import-Module (Join-Path $env:DOTFILES ".config\powershell\functions.psm1") -DisableNameChecking -Force

$configPath = Join-Path $PSScriptRoot "config.json"
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

foreach ($bucket in $config.scoop.buckets) {
    & scoop bucket add $bucket[0] $bucket[1] *>$null
}

& scoop update *>$null

foreach ($app in $config.scoop.apps) {
    $appId = $app[0]
    $appName = $app[1]
    $postInstall = $app[2]

    if (Test-App -App $appId) {
        Write-Host "scoop: '$appName' already installed, skipping..."
    } else {
        Write-Host "scoop: Installing '$appName'..."
        & scoop install $appName *>$null
    }

    if (-not [string]::IsNullOrWhiteSpace($postInstall)) {
        Write-Host "scoop: Running post-install for $appName..."
        try {
            $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
            Invoke-Expression $postInstall *>$null
        }
        catch {
            Write-Warning "scoop: Post-install failed for $appName"
            Write-Error $_.Exception.Message
        }
    }
}

foreach ($app in $config.winget.apps) {
    $appId = if ([string]::IsNullOrWhiteSpace($app[0])) { $app[1] } else { $app[0] }
    $wingetId = $app[1]
    $postInstall = $app[2]
    $wingetArgs = @(
        "--id", $wingetId,
        "--exact",
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements"
    )

    if (Test-App -App $appId) {
        Write-Host "winget: '$wingetId' already installed, skipping..."
    } else {
        Write-Host "winget: Installing '$wingetId'..."
        & winget install $wingetArgs *>$null
    }

    if (-not [string]::IsNullOrWhiteSpace($postInstall)) {
        Write-Host "winget: Running post-install for $wingetId..."
        try {
            $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
            Invoke-Expression $postInstall *>$null
        }
        catch {
            Write-Warning "winget: Post-install failed for $wingetId"
            Write-Error $_.Exception.Message
        }
    }
}

foreach ($link in $config.symlinks) {
    $source = Join-Path $env:DOTFILES $link[0].Replace("/", "\")
    $destination = [Environment]::ExpandEnvironmentVariables($link[1].Replace("/", "\"))

    if ((Test-Path $source) -and (($source.EndsWith(".json")) -or ($source.EndsWith(".jsonc")))) {
      $content = Get-Content -Path $source -Raw
      $content = [regex]::Replace($content, '(?i)[A-Z]:\\\\Users\\\\[^\\"]+', $env:USERPROFILE.Replace("\", "\\"))
      $content = [regex]::Replace($content, '(?i)[A-Z]:/Users/[^/"]+', $env:USERPROFILE.Replace("\", "/"))

      Set-Content -Path $source -Value $content -NoNewline
    }

    Link-Path -Target $source -Path $destination
}
