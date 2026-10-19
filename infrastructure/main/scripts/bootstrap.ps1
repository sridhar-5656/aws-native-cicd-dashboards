param(
    [Parameter(Mandatory)][string]$Region,
    [Parameter(Mandatory)][string]$Repository
)
& "$PSScriptRoot\..\..\..\scripts\bootstrap.ps1" -Region $Region -Repository $Repository
