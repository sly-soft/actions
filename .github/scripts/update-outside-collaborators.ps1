# Write-Host "Org: $env:OUTSIDE_COLLABORATORS_GITHUB_ORG"
Write-Host "**update-outside-collaborators**"

Set-Location external-collaborators

foreach ($file in Get-ChildItem) {
    $content = Get-Content $file
    foreach ($line in $content) {
        Write-Host $content
    }
}