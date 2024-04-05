Write-Host "**update-outside-collaborators**"


$org = $env:GITHUB_ORG
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
    Write-Host "Retrieving existing collaborators for '$repo'"

    #$url = "https://api.github.com/repos/$org/$repo/collaborators"
    $url = "https://api.github.com/repos/$org/$repo/collaborators?affiliation=outside"

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

    foreach ($collaborator in $response) {
        $collaborators.Add($collaborator.login)
    }

    return $collaborators
}

function RetrieveInvitations($repo) {
    Write-Host "Retrieving invitations for '$repo'"

    $url = "https://api.github.com/repos/$org/$repo/invitations"

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"

    $invitations = Invoke-RestMethod `
        -Headers $GitHubHeaders  `
        -URI $url `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 200) {
        Write-Error "Error retrieving current collaborators: $statusCode"
        return $null
    }

    return $invitations
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

function IdentifyMissingCollabortors($existingCollaborators, $invitations, $desiredCollaborators) {
    $collaboratorsAndInvitiations = New-Object Collections.Generic.List[string]
    foreach ($invitation in $invitations) {
        $collaboratorsAndInvitiations.Add($invitation.invitee.login)
    }
    $collaboratorsAndInvitiations = $existingCollaborators + $collaboratorsAndInvitiations

    if ($collaboratorsAndInvitiations.Length -eq 0) {
        return $desiredCollaborators
    }

    $missingCollaborators = New-Object Collections.Generic.List[string]
    foreach ($desiredCollaborator in $desiredCollaborators) {
        if ($collaboratorsAndInvitiations -notcontains $desiredCollaborator) {
            $missingCollaborators.Add($desiredCollaborator)
        }
    }

    return $missingCollaborators
}

function IdentifyCollaboratorsToRemove($existingCollaborators, $desiredCollaborator) {
    $collaboratorsToRemove = New-Object Collections.Generic.List[string]

    foreach ($collaborator in $existingCollaborators) {
        if ($desiredCollaborators -notcontains $collaborator) {
            $collaboratorsToRemove.Add($collaborator)            
        }
    }

    return $collaboratorsToRemove
}

function IdentifyInvitiationsToRescend($invitations, $desiredCollaborators) {
    $invitiationsToRescend = New-Object Collections.Generic.List[object]

    foreach ($invitation in $invitations) {
        if ($desiredCollaborators -notcontains $invitation.invitee.login) {
            $invitiationsToRescend.Add($invitation)            
        }
    }

    return $invitiationsToRescend
}

function AddCollaboratorToRepo($repo, $collaborator) {
    Write-Host "Inviting '$collaborator' to '$repo'"

    $url = "https://api.github.com/repos/$org/$repo/collaborators/$collaborator"

    $body = @{
        permission = "write"
    } | ConvertTo-Json

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"
    Write-Debug "body: $body"

    Invoke-RestMethod `
        -Method PUT `
        -Headers $GitHubHeaders  `
        -URI $url `
        -Body $body `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 201) {
        Write-Error "Error adding '$collaborator' to '$repo': $statusCode"
    }
}

function RemoveCollaboratorFromRepo($repo, $collaborator) {
    Write-Host "Removing '$collaborator' from '$repo'"

    $url = "https://api.github.com/repos/$org/$repo/collaborators/$collaborator"

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"

    Invoke-RestMethod `
        -Method DELETE `
        -Headers $GitHubHeaders  `
        -URI $url `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 204) {
        Write-Error "Error removing '$collaborator' from '$repo': $statusCode"
    }
}

function RescendInvitation($repo, $invitation) {
    Write-Host "Rescending invitiation for '$($invitation.invitee.login)' to '$repo'"

    $url = "https://api.github.com/repos/$org/$repo/invitations/$($invitation.id)"

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"

    Invoke-RestMethod `
        -Method DELETE `
        -Headers $GitHubHeaders  `
        -URI $url `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 204) {
        Write-Error "Error recending invitation for '$($invitation.invitee.login)' to '$repo': $statusCode"
    }
}

function UpdateRepo($repo) {
    Write-Host "Handling Repo '$org/$repo'"

    [array]$existingCollaborators = RetrieveCurrentCollaborators $repo
    [array]$invitations = RetrieveInvitations $repo

    [array]$desiredCollaborators = LoadDesiredCollaborators $repo

    [array]$collaboratorsToAdd = IdentifyMissingCollabortors $existingCollaborators $invitations $desiredCollaborators
    foreach ($collaborator in $collaboratorsToAdd) {
        AddCollaboratorToRepo $repo $collaborator
    }

    [array]$collaboratorsToRemove = IdentifyCollaboratorsToRemove $existingCollaborators $desiredCollaborators
    foreach ($collaborator in $collaboratorsToRemove) {
        RemoveCollaboratorFromRepo $repo $collaborator 
    }

    [array]$invitationsToRescend = IdentifyInvitiationsToRescend $invitations $desiredCollaborators
    foreach ($invitation in $invitationsToRescend) {
        RescendInvitation $repo $invitation
    }
}


#main logic

Set-Location ./external-collaborators

foreach ($file in Get-ChildItem) {
    UpdateRepo $file.name
}