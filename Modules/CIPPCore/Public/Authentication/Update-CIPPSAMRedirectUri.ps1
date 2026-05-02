function Update-CIPPSAMRedirectUri {
    <#
    .SYNOPSIS
    Ensures the SAM app registration includes the current host's redirect URIs.

    .DESCRIPTION
    Checks the SAM app's web.redirectUris and adds any
    missing URIs for the current CIPP instance. Requires
    $env:ApplicationID, $env:TenantID, and WEBSITE_HOSTNAME to be set.
    #>
    [CmdletBinding()]
    param()

    $CurrentHost = $env:WEBSITE_HOSTNAME
    if (-not $CurrentHost) {
        Write-Information '[SAM-Redirect] WEBSITE_HOSTNAME not set, skipping redirect URI update'
        return
    }

    if (-not $env:ApplicationID -or -not $env:TenantID) {
        Write-Information '[SAM-Redirect] SAM credentials not loaded, skipping redirect URI update'
        return
    }

    $CurrentUrl = "https://$CurrentHost"
    $RequiredUris = @(
        "$CurrentUrl/authredirect",
        "$CurrentUrl/.auth/callback"
    )

    try {
        $AppResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($env:ApplicationID)')?`$select=id,web" -tenantid $env:TenantID -NoAuthCheck $true
        $ExistingUris = @($AppResponse.web.redirectUris)
        $MissingUris = $RequiredUris | Where-Object { $_ -notin $ExistingUris }

        if ($MissingUris.Count -eq 0) {
            Write-Information '[SAM-Redirect] All redirect URIs already present'
            return
        }

        $UpdatedUris = [System.Collections.Generic.List[string]]::new()
        $ExistingUris | ForEach-Object { $UpdatedUris.Add($_) }
        $MissingUris | ForEach-Object { $UpdatedUris.Add($_) }

        $Body = @{
            web = @{ redirectUris = $UpdatedUris }
        } | ConvertTo-Json -Depth 5

        New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)" -body $Body -tenantid $env:TenantID -type PATCH -NoAuthCheck $true
        Write-Information "[SAM-Redirect] Added redirect URIs: $($MissingUris -join ', ')"
        Write-LogMessage -API 'SAM-Redirect' -message "Added redirect URIs: $($MissingUris -join ', ')" -sev Info
    } catch {
        Write-LogMessage -API 'SAM-Redirect' -message "Failed to update redirect URIs: $_" -LogData (Get-CippException -Exception $_) -sev Warning
    }
}
