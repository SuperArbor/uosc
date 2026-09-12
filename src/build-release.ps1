param(
	[string]$OutputDirectory = (Join-Path $PSScriptRoot "..\release")
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SourceDirectory = Join-Path $RepoRoot "src"
$StageDirectory = Join-Path $OutputDirectory "uosc"
$ZipFile = Join-Path $OutputDirectory "uosc.zip"
$ConfFile = Join-Path $OutputDirectory "uosc.conf"

function Remove-PathIfExists {
	param([Parameter(Mandatory = $true)][string]$Path)

	if (Test-Path -LiteralPath $Path) {
		Remove-Item -LiteralPath $Path -Recurse -Force
	}
}

function Normalize-TextFile {
	param([Parameter(Mandatory = $true)][string]$Path)

	$Text = [System.IO.File]::ReadAllText($Path)
	$Text = $Text -replace "`r`n", "`n"
	$Text = $Text -replace "`r", "`n"
	$Text = $Text.TrimEnd("`r", "`n") + "`n"
	[System.IO.File]::WriteAllText(
		$Path,
		$Text,
		(New-Object System.Text.UTF8Encoding($false))
	)
}

function Copy-ReleaseTree {
	param(
		[Parameter(Mandatory = $true)][string]$Source,
		[Parameter(Mandatory = $true)][string]$Destination
	)

	New-Item -ItemType Directory -Force -Path $Destination | Out-Null
	Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
		Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
	}
}

if (!(Test-Path -LiteralPath (Join-Path $SourceDirectory "uosc") -PathType Container)) {
	throw "Missing source directory: $SourceDirectory\uosc"
}
if (!(Test-Path -LiteralPath (Join-Path $SourceDirectory "fonts") -PathType Container)) {
	throw "Missing source directory: $SourceDirectory\fonts"
}
if (!(Test-Path -LiteralPath (Join-Path $SourceDirectory "uosc.conf") -PathType Leaf)) {
	throw "Missing source file: $SourceDirectory\uosc.conf"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Remove-PathIfExists $StageDirectory
Remove-PathIfExists $ZipFile
Remove-PathIfExists $ConfFile
New-Item -ItemType Directory -Force -Path $StageDirectory | Out-Null

# Build the archive with the same layout expected by the installer.
$BinaryDirectory = Join-Path $SourceDirectory "uosc\bin"
$BinaryNames = @("ziggy-windows.exe", "ziggy-linux", "ziggy-darwin")
if (!(Get-Command go -ErrorAction SilentlyContinue)) {
	throw "Go is required to build ziggy binaries."
}
New-Item -ItemType Directory -Force -Path $BinaryDirectory | Out-Null
foreach ($BinaryName in $BinaryNames) {
	Remove-PathIfExists (Join-Path $BinaryDirectory $BinaryName)
}

Push-Location $RepoRoot
try {
	& pwsh -NoProfile -File (Join-Path $RepoRoot "tools\build.ps1") ziggy
}
finally {
	Pop-Location
}

foreach ($BinaryName in $BinaryNames) {
	$BinaryPath = Join-Path $BinaryDirectory $BinaryName
	if (!(Test-Path -LiteralPath $BinaryPath -PathType Leaf) -or (Get-Item -LiteralPath $BinaryPath).Length -eq 0) {
		throw "ziggy build did not produce a valid binary: $BinaryName"
	}
}

Copy-ReleaseTree (Join-Path $SourceDirectory "uosc") (Join-Path $StageDirectory "scripts\uosc")
Copy-ReleaseTree (Join-Path $SourceDirectory "fonts") (Join-Path $StageDirectory "fonts")

$TextExtensions = @(".lua", ".json", ".conf", ".txt")
Get-ChildItem -LiteralPath $StageDirectory -Recurse -File |
	Where-Object { $TextExtensions -contains $_.Extension.ToLowerInvariant() } |
	ForEach-Object { Normalize-TextFile $_.FullName }

Copy-Item -LiteralPath (Join-Path $SourceDirectory "uosc.conf") -Destination $ConfFile -Force
Normalize-TextFile $ConfFile

Compress-Archive `
	-Path (Join-Path $StageDirectory "*") `
	-DestinationPath $ZipFile `
	-CompressionLevel Optimal

Write-Output "Created: $ZipFile"
Write-Output "Created: $ConfFile"
