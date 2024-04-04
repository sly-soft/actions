Write-Host "**update-outside-collaborators**"

$org = $env:OUTSIDE_COLLABORATORS_GITHUB_ORG

Set-Location ./external-collaborators

foreach ($file in Get-ChildItem) {
    Write-Host "Repo: $org/$($file.name)"
    $content = Get-Content $file.Name
    foreach ($line in $content) {
        Write-Host "  External Collaborator:" $content
    }
}