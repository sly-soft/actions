Write-Host "**update-outside-collaborators**"


$org = $env:GITHUB_ORG
#$org = 'sly-soft'
if ($Null -eq $org) {
    "Environment variable 'GITHUB_ORG' not provided"
    exit 1
}

$token = $env:GITHUB_TOKEN
if ($Null -eq $token) {
    "Environment variable 'GITHUB_TOKEN' not provided"
    exit 1
}

# Setup Headers
$GitHubHeaders = @{
    'Accept'               = 'application/vnd.github+json'
    'Authorization'        = "Bearer $token"
    'X-GitHub-Api-Version' = '2022-11-28'
}

Write-Host $GitHubHeaders

function RetrieveCurrentCollaborators($repo) {
    $url = "https://api.github.com/repos/$org/$repo/collaborators"
    #$url = "https://api.github.com/repos/$org/$repo/collaborators/affiliation=outside"

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"

    $collaborators = New-Object Collections.Generic.List[string]

    $response = Invoke-RestMethod `
        -Headers $GitHubHeaders  `
        -URI $url `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 200) {
        Write-Error "Error retrieving current collaborators: $statusCode"
        return $collaborators
    }

    Write-Host "response: $response"
    return $collaborators
}

function LoadDesiredCollaborators($repo) {
    Write-Host "Loading collaborators from file '$repo'"
    
    $content = Get-Content $file.Name
    $collaborators = New-Object Collections.Generic.List[string]
    foreach ($collaborator in $content) {
        $collaborators.Add($collaborator)
    }

    return $collaborators
}

function UpdateRepo($repo) {
    Write-Host "Handling Repo '$org/$repo'"

    $existingCollaborators = RetrieveCurrentCollaborators($repo)
    Write-Host $existingCollaborators

    $desiredCollaborators = LoadDesiredCollaborators $repo

    Write-Host $desiredCollaborators
}


#main logic

Set-Location ./external-collaborators

foreach ($file in Get-ChildItem) {
    UpdateRepo $file.name
}