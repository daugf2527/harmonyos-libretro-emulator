param(
  [string[]]$SdkRoots = @(
    'D:\command-line-tools\sdk\default',
    'D:\hongmeng\command-line-tools\sdk\default',
    'D:\Program Files\DevEco Studio\sdk\default'
  )
)

$ErrorActionPreference = 'Stop'

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Show-Package {
  param(
    [string]$Label,
    [string]$Path
  )

  $pkg = Read-JsonFile -Path $Path
  if ($null -eq $pkg) {
    Write-Host "  ${Label}: missing ($Path)"
    return $false
  }

  $apiVersion = if ($pkg.data.apiVersion) { $pkg.data.apiVersion } else { $pkg.apiVersion }
  $version = if ($pkg.data.version) { $pkg.data.version } else { $pkg.version }
  $displayName = if ($pkg.data.displayName) { $pkg.data.displayName } else { $pkg.displayName }
  Write-Host "  ${Label}: apiVersion=$apiVersion version=$version displayName=$displayName"
  return [string]$apiVersion -eq '26'
}

$foundApi26 = $false

foreach ($root in $SdkRoots) {
  Write-Host "SDK root: $root"
  if (-not (Test-Path -LiteralPath $root)) {
    Write-Host "  missing"
    continue
  }

  $rootIsApi26 = Show-Package -Label 'sdk-pkg' -Path (Join-Path $root 'sdk-pkg.json')
  $nativeIsApi26 = Show-Package -Label 'native' -Path (Join-Path $root 'openharmony\native\oh-uni-package.json')
  $etsIsApi26 = Show-Package -Label 'ets' -Path (Join-Path $root 'openharmony\ets\oh-uni-package.json')
  $toolchainsIsApi26 = Show-Package -Label 'toolchains' -Path (Join-Path $root 'openharmony\toolchains\oh-uni-package.json')
  $previewerIsApi26 = Show-Package -Label 'previewer' -Path (Join-Path $root 'openharmony\previewer\oh-uni-package.json')

  $hmsNative = Join-Path $root 'hms\native\sysroot\usr'
  if (Test-Path -LiteralPath $hmsNative) {
    Write-Host "  hms native: present ($hmsNative)"
  } else {
    Write-Host "  hms native: missing ($hmsNative)"
  }

  if ($rootIsApi26 -and $nativeIsApi26 -and $etsIsApi26 -and $toolchainsIsApi26 -and $previewerIsApi26) {
    $foundApi26 = $true
  }
}

if (-not $foundApi26) {
  Write-Error 'HarmonyOS API26 SDK packages were not found. Install HarmonyOS 7.0/API26 SDK in DevEco Studio SDK Manager, then rerun this script.'
}

Write-Host 'HarmonyOS API26 SDK packages are present.'
