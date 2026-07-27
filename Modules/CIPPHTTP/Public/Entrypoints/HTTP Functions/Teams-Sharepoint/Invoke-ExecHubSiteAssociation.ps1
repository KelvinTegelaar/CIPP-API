function Invoke-ExecHubSiteAssociation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $DisplayName = $Request.Body.DisplayName
    $Disconnect = [bool]$Request.Body.Disconnect
    $RawHubId = $Request.Body.HubSiteId
    # autoComplete fields may arrive as { label, value }
    $HubSiteId = if ($RawHubId -is [PSCustomObject] -and $null -ne $RawHubId.value) { $RawHubId.value } else { $RawHubId }
    $SiteLabel = if ($DisplayName) { $DisplayName } else { $SiteUrl }

    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if (-not $SiteUrl) { throw 'SiteUrl is required' }
        if (-not $Disconnect -and -not $HubSiteId) { throw 'Provide HubSiteId to join a hub, or Disconnect: true to leave' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $TargetHubId = if ($Disconnect) { '00000000-0000-0000-0000-000000000000' } else { $HubSiteId }

        # Site-level REST: delegated only (no -AsApp)
        $null = New-GraphPOSTRequest `
            -scope "$($SharePointInfo.SharePointUrl)/.default" `
            -uri "$SiteUrl/_api/site/JoinHubSite('$TargetHubId')" `
            -body '{}' `
            -tenantid $TenantFilter `
            -type POST `
            -AddedHeaders @{ 'accept' = 'application/json' }

        $Results = if ($Disconnect) {
            "Successfully disconnected '$SiteLabel' from its hub site."
        } else {
            "Successfully connected '$SiteLabel' to the selected hub site."
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = $ErrorMessage.NormalizedError
        if ($ErrorText -match 'approval|permission to join') {
            $ErrorText = "This hub requires approval to join, or the connecting account lacks join permission on the hub. Original error: $ErrorText"
        }
        $Results = "Failed to update hub association for '$SiteLabel'. Error: $ErrorText"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = $Results }
        })
    }
}
