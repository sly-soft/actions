Write-Host "**update-outside-collaborators**"

$org = $env:OUTSIDE_COLLABORATORS_GITHUB_ORG
#$token = $env:GITHUB_TOKEN

function LoadCollaborators($repo) {
    Write-Host "Loading collaborators from file '$repo'"
    
    $collaborators = New-Object Collections.Generic.List[string]
    foreach ($collaborator in $content) {
        $collaborators.Add($collaborator)
    }
    return $collaborators
}

function HandleRepo($repo) {
    Write-Host "Handling Repo '$org/$repo'"

    $collaborators = LoadCollaborators $repo

    Write-Host $collaborators
}


#main logic

Set-Location ./external-collaborators

foreach ($file in Get-ChildItem) {
    HandleRepo $file.name
}