param([Parameter(ValueFromRemainingArguments=$true)][string[]]$FlutterArgs)
$ErrorActionPreference = 'Stop'
$flutterCommand = Get-Command flutter -ErrorAction Stop
$sdk = Split-Path (Split-Path $flutterCommand.Source)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  $desktopGit = Get-ChildItem "$env:LOCALAPPDATA/GitHubDesktop/app-*/resources/app/git/cmd/git.exe" -ErrorAction SilentlyContinue | Select-Object -Last 1
  if ($desktopGit) { $env:Path = (Split-Path $desktopGit.FullName) + ';' + $env:Path }
}
# Windows PowerShell can turn redirected native stderr warnings into errors.
# Let Flutter's actual exit code determine success.
$ErrorActionPreference = 'Continue'
& "$sdk/bin/cache/dart-sdk/bin/dart.exe" "$sdk/bin/cache/flutter_tools.snapshot" @FlutterArgs
exit $LASTEXITCODE
