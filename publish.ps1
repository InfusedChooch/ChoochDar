param(
  [ValidateSet('Debug','Release')]
  [string]$Configuration = 'Release',

  [string]$Runtime = 'win-x64',

  [bool]$SelfContained = $true,

  [bool]$SingleFile = $false,

  [switch]$Clean,

  [string[]]$Projects = @(
    'eft-dma-radar\eft-dma-radar.csproj',
    'arena-dma-radar\arena-dma-radar.csproj'
  ),

  [string]$AdditionalMsBuildProps = ''
)

$ErrorActionPreference = 'Stop'

function Assert-DotNet {
  $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
  if (-not $dotnet) {
    Write-Error "dotnet SDK not found. Install .NET SDK 9.0+ and retry."
  }
  $ver = (& dotnet --version)
  Write-Host "dotnet version: $ver" -ForegroundColor DarkGray
}

function Get-TargetFramework([string]$ProjectPath) {
  try {
    $match = Select-String -Path $ProjectPath -Pattern '<TargetFramework>([^<]+)</TargetFramework>' -SimpleMatch:$false | Select-Object -First 1
    if ($match) {
      return $match.Matches[0].Groups[1].Value
    }
  } catch {}
  return 'net9.0-windows'
}

function Publish-Project {
  param(
    [string]$ProjectPath,
    [string]$Configuration,
    [string]$Runtime,
    [bool]$SelfContained,
    [bool]$SingleFile,
    [switch]$Clean,
    [string]$AdditionalMsBuildProps
  )

  if (-not (Test-Path $ProjectPath)) {
    Write-Error "Project not found: $ProjectPath"
  }

  $projectDir = Split-Path -Parent $ProjectPath
  $tfm = Get-TargetFramework -ProjectPath $ProjectPath

  if ($Clean) {
    Write-Host "Cleaning $ProjectPath ($Configuration)" -ForegroundColor Yellow
    dotnet clean $ProjectPath -c $Configuration --nologo | Out-Null
  }

  $props = @(
    "/p:SelfContained=$SelfContained",
    "/p:PublishSingleFile=$SingleFile"
  )

  if ($SingleFile) {
    $props += "/p:IncludeNativeLibrariesForSelfExtract=true"
    $props += "/p:EnableCompressionInSingleFile=true"
  }

  if ($AdditionalMsBuildProps -and $AdditionalMsBuildProps.Trim()) {
    $props += $AdditionalMsBuildProps.Trim()
  }

  Write-Host "Publishing $ProjectPath -> $Configuration | $Runtime | SelfContained=$SelfContained | SingleFile=$SingleFile" -ForegroundColor Cyan
  dotnet publish $ProjectPath -c $Configuration -r $Runtime --nologo -v minimal @props

  $publishDir = Join-Path $projectDir (Join-Path "bin" (Join-Path $Configuration (Join-Path $tfm (Join-Path $Runtime "publish"))))
  if (-not (Test-Path $publishDir)) {
    Write-Error "Publish folder not found: $publishDir"
  }

  $exes = Get-ChildItem -Path $publishDir -Filter *.exe -File -ErrorAction SilentlyContinue
  Write-Host "Output: $publishDir" -ForegroundColor Green
  if ($exes) {
    foreach ($exe in $exes) {
      Write-Host "  -> $($exe.FullName)" -ForegroundColor Green
    }
  }

  return $publishDir
}

Push-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
try {
  Assert-DotNet

  $sln = 'eft-dma-radar.sln'
  if (Test-Path $sln) {
    Write-Host "Restoring solution packages..." -ForegroundColor DarkGray
    dotnet restore $sln --nologo | Out-Null
  } else {
    Write-Host "Solution not found, restoring per project..." -ForegroundColor DarkGray
    foreach ($p in $Projects) {
      if (Test-Path $p) { dotnet restore $p --nologo | Out-Null }
    }
  }

  $published = @()
  foreach ($proj in $Projects) {
    $published += Publish-Project -ProjectPath $proj -Configuration $Configuration -Runtime $Runtime -SelfContained $SelfContained -SingleFile $SingleFile -Clean:$Clean -AdditionalMsBuildProps $AdditionalMsBuildProps
  }

  Write-Host "Publish complete." -ForegroundColor Green
  Write-Host "Folders:" -ForegroundColor Green
  $published | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
}
finally {
  Pop-Location
}

