param(
    [Parameter(Mandatory)][ValidateSet("A", "C")][string]$Phase,
    [string]$ImageTag
)
& "$PSScriptRoot\..\..\scripts\deploy.ps1" -Phase $Phase -ImageTag $ImageTag
