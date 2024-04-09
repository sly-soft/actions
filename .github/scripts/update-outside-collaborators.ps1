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

$jcKey = $env:JUMP_CLOUD_KEY
if ($Null -eq $jcKey) {
    "Environment variable 'JUMP_CLOUD_KEY' not provided"
    exit 1
}

# Setup Headers
$GitHubHeaders = @{
    'Accept'               = 'application/vnd.github+json'
    'Authorization'        = "Bearer $token"
    'X-GitHub-Api-Version' = '2022-11-28'
}


$JumpCloudHeaders = @{
    'x-api-key' = $jcKey
}


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

function UpdateRepo($repo, $configuredCollaborators) {
    Write-Host "Handling Repo '$org/$repo'"

    [array]$existingCollaborators = RetrieveCurrentCollaborators $repo
    [array]$invitations = RetrieveInvitations $repo

    [array]$collaboratorsToAdd = IdentifyMissingCollabortors $existingCollaborators $invitations $configuredCollaborators
    foreach ($collaborator in $collaboratorsToAdd) {
        AddCollaboratorToRepo $repo $collaborator
    }

    [array]$collaboratorsToRemove = IdentifyCollaboratorsToRemove $existingCollaborators $configuredCollaborators
    foreach ($collaborator in $collaboratorsToRemove) {
        RemoveCollaboratorFromRepo $repo $collaborator 
    }

    [array]$invitationsToRescend = IdentifyInvitiationsToRescend $invitations $configuredCollaborators
    foreach ($invitation in $invitationsToRescend) {
        RescendInvitation $repo $invitation
    }
}

function GetGitHubUsernameForJumpCloudUser($jcUserId) {
    $url = "https://console.jumpcloud.com/api/systemusers/$jcUserId"

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"

    $userData = Invoke-RestMethod `
        -Headers $JumpCloudHeaders  `
        -URI $url `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 200) {
        Write-Error "Error retrieving member data for '$jcUserId' from JumpCloud: $statusCode"
        return $null
    }

    foreach ($attribute in $userData.Attributes) {
        if ($attribute.name -eq "GitHubUsername") {
            return $attribute.Value
        }        
    }

    return $null
}

function GetGroupMembersFromJumpCloud($group) {
    Write-Host "Getting members of $group"

    $groupMembers = New-Object Collections.Generic.List[string]

    $url = "https://console.jumpcloud.com/api/v2/usergroups?filter=name:eq:$group"

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"

    $groupData = Invoke-RestMethod `
        -Headers $JumpCloudHeaders  `
        -URI $url `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 200) {
        Write-Error "Error retrieving group '$group' from JumpCloud: $statusCode"
        return $groupMembers
    }
    
    $groupId = $groupData.id

    $url = "https://console.jumpcloud.com/api/v2/usergroups/$groupId/members"

    Write-Debug "-- Invoke-RestMethod --"
    Write-Debug "url: $url"

    $members = Invoke-RestMethod `
        -Headers $JumpCloudHeaders  `
        -URI $url `
        -StatusCodeVariable statusCode `
        -SkipHttpErrorCheck

    if ($statusCode -ne 200) {
        Write-Error "Error retrieving members for group '$group' from JumpCloud: $statusCode"
        return $groupMembers
    }

    foreach ($member in $members) {
        $gitHubUserName = GetGitHubUsernameForJumpCloudUser $member.to.id
        if ($null -eq $gitHubUserName) {
            continue
        }

        $groupMembers.Add($gitHubUserName)
    }

    return $groupMembers;
}

function GetConfiguredCollaborators($repoConfiguration) {
    if ($null -eq $repoConfiguration.individuals) {
        $configuredCollaborators = New-Object Collections.Generic.List[string]
    } else {
        $configuredCollaborators = $repoConfiguration.individuals
    }
    
    foreach ($group in $repoConfiguration.groups) {
        $groupMembers = GetGroupMembersFromJumpCloud $group
        foreach ($groupMember in $groupMembers) {
            if ($configuredCollaborators -contains $groupMember) {
                continue
            }

            $configuredCollaborators.Add($groupMember)
        }
    }

    return $configuredCollaborators
}


#main logic

#clear
Set-Location ./external-collaborators

$yaml = Get-Content -Path "team-config.yml" | Out-String

Import-Module powershell-yaml

$repos = ConvertFrom-Yaml $yaml 
foreach ($repo in $repos.Keys) {
    [array]$configuredCollaborators = GetConfiguredCollaborators $repos[$repo]
    UpdateRepo $repo $configuredCollaborators
}