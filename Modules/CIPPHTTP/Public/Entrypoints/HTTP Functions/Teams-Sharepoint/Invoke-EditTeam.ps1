function Invoke-EditTeam {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Group.ReadWrite
    .DESCRIPTION
        Updates a team's member, guest, messaging and fun settings. Settings left out of the request are not changed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Team (Microsoft 365 group) id.
    $TeamID = $Request.Body.TeamID

    if ("$TeamID" -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'TeamID must be a team id' } })
    }

    $Allowed = @{
        memberSettings    = @('allowCreateUpdateChannels', 'allowCreatePrivateChannels', 'allowDeleteChannels', 'allowAddRemoveApps', 'allowCreateUpdateRemoveTabs', 'allowCreateUpdateRemoveConnectors')
        guestSettings     = @('allowCreateUpdateChannels', 'allowDeleteChannels')
        messagingSettings = @('allowUserEditMessages', 'allowUserDeleteMessages', 'allowOwnerDeleteMessages', 'allowTeamMentions', 'allowChannelMentions')
        funSettings       = @('allowGiphy', 'allowStickersAndMemes', 'allowCustomMemes')
    }
    $Patch = @{}
    foreach ($Section in $Allowed.Keys) {
        $Values = $Request.Body.$Section
        if ($null -eq $Values) { continue }
        $Settings = @{}
        foreach ($Name in $Allowed[$Section]) {
            $Value = $Values.$Name
            if ($null -ne $Value) { $Settings[$Name] = "$Value" -eq 'true' }
        }
        if ($Section -eq 'funSettings' -and $Values.giphyContentRating) {
            $Rating = $Values.giphyContentRating.value ?? $Values.giphyContentRating
            if ($Rating -notin @('strict', 'moderate')) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'giphyContentRating must be strict or moderate' } })
            }
            $Settings.giphyContentRating = "$Rating".ToLowerInvariant()
        }
        if ($Settings.Count) { $Patch[$Section] = $Settings }
    }
    if ($Patch.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'No team settings to change' } })
    }

    try {
        # Teams rejects partner (delegated) access for this call, so it runs as the application.
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/teams/$TeamID" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject $Patch -Compress -Depth 5) -AsApp $true
        $Result = 'Updated the team settings'
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result for team $TeamID" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update the team settings. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result Team $TeamID" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
