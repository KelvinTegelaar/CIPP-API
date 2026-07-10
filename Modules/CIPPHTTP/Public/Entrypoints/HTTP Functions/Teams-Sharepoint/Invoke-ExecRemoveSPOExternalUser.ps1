function Invoke-ExecRemoveSPOExternalUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Fully removes an external user's guest access: deletes their Entra guest account (when
        one exists) AND removes them from every SharePoint site they hold membership on, in one
        pass - so no orphaned accounts or lingering site access are left behind. The inert
        SharePoint external-store entry cannot be deleted (Microsoft deprecated
        RemoveExternalUsers) and ages out on its own; sharing links the user received are
        revoked separately via the Sharing Report.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $EntraUserId = $Request.Body.EntraUserId
    $LoginName = $Request.Body.LoginName
    $SiteUrls = @($Request.Body.SiteUrls) | Where-Object { $_ }
    $DisplayName = $Request.Body.DisplayName ?? $EntraUserId ?? $LoginName

    try {
        if (-not $EntraUserId -and $SiteUrls.Count -eq 0) {
            throw 'This entry has no Entra guest account and no known site memberships. The remaining SharePoint store entry cannot be removed (Microsoft deprecated the API) and ages out on its own; revoke any sharing links they hold via the Sharing Report.'
        }

        $Messages = [System.Collections.Generic.List[string]]::new()
        $Errors = [System.Collections.Generic.List[string]]::new()

        # 1. Strip the SharePoint footprint first (needs the login; falls back to the Entra UPN).
        if ($SiteUrls.Count -gt 0) {
            $RemovalLogin = $LoginName
            if (-not $RemovalLogin -and $EntraUserId) {
                try {
                    $RemovalLogin = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($EntraUserId)?`$select=userPrincipalName" -tenantid $TenantFilter -AsApp $true).userPrincipalName
                } catch {
                    $Errors.Add("Could not resolve the user's login for site removal: $($_.Exception.Message)")
                }
            }
            if ($RemovalLogin) {
                $Removal = Remove-CIPPSPOSiteUser -TenantFilter $TenantFilter -SiteUrls $SiteUrls -LoginName $RemovalLogin
                if ($Removal.Succeeded.Count -gt 0) {
                    $Messages.Add("Removed from $($Removal.Succeeded.Count) site(s): $($Removal.Succeeded -join ', ').")
                }
                if ($Removal.Failed.Count -gt 0) {
                    $Errors.Add("Site removal failed on: $($Removal.Failed -join '; ')")
                }
            }
        }

        # 2. Delete the Entra guest account so the user cannot sign in anywhere.
        if ($EntraUserId) {
            try {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$EntraUserId" -tenantid $TenantFilter -type DELETE -body '' -asapp $true
                $Messages.Add('Deleted the Entra guest account, blocking their sign-in.')
            } catch {
                $Errors.Add("Deleting the Entra guest account failed: $($_.Exception.Message)")
            }
        }

        if ($Messages.Count -eq 0) {
            throw ($Errors -join ' ')
        }
        $Results = "Removed guest access for $($DisplayName): $($Messages -join ' ')"
        if ($Errors.Count -gt 0) {
            $Results += " Issues: $($Errors -join '; ')"
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to remove guest access for $($DisplayName): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
