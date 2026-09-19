param(
  [double]$MinimumPercent = 65
)

$ErrorActionPreference = "Stop"

$coverageOutput = @(
  & moon coverage analyze -p "ppyj663/moonavro/src" -- -f summary 2>&1
)
$moonExitCode = $LASTEXITCODE
$coverageText = $coverageOutput -join [Environment]::NewLine
Write-Output $coverageText

if ($moonExitCode -ne 0) {
  throw "MoonBit coverage analysis failed with exit code $moonExitCode."
}

$coverageMatch = [regex]::Match(
  $coverageText,
  "(?m)^Total:\s*(\d+)\s*/\s*(\d+)\s*$"
)
if (-not $coverageMatch.Success) {
  throw "Could not parse the MoonBit coverage summary."
}

$coveredLines = [double]$coverageMatch.Groups[1].Value
$totalLines = [double]$coverageMatch.Groups[2].Value
if ($totalLines -le 0) {
  throw "MoonBit reported no instrumented library lines."
}

$coveragePercent = 100 * $coveredLines / $totalLines
$formattedPercent = "{0:N1}" -f $coveragePercent
Write-Output "Library line coverage: $formattedPercent% (minimum $MinimumPercent%)"

if ($coveragePercent -lt $MinimumPercent) {
  throw "Coverage $formattedPercent% is below the required $MinimumPercent%."
}

if ($env:GITHUB_STEP_SUMMARY) {
  Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value "MoonAvro library line coverage: **$formattedPercent%** (minimum $MinimumPercent%)."
}
