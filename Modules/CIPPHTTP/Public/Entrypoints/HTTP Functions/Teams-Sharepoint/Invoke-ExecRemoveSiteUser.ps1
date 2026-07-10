function Invoke-ExecRemoveSiteUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Removes a user from one or more SharePoint sites entirely: deleting the site user
        removes them from every site group and direct permission grant at once. Uses the
        SharePoint REST API with certificate authentication. Note this does not revoke
        sharing links the user received by mail; use the sharing link actions for those.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Single site (SiteUrl) or several at once (SiteUrls, e.g. from the External Users report).
    $SiteUrls = @($Request.Body.SiteUrls ?? $Request.Body.SiteUrl) | Where-Object { $_ }
    # The picker supplies the SP claims login via addedFields; fall back to building it from the UPN.
    $LoginName = $Request.Body.user.addedFields.LoginName ?? $Request.Body.user.value
    $Label = $Request.Body.DisplayName ?? $Request.Body.user.value ?? $LoginName

    try {
        if ($SiteUrls.Count -eq 0) { throw 'SiteUrl is required.' }
        if (-not $LoginName) { throw 'No user was selected.' }

        $Removal = Remove-CIPPSPOSiteUser -TenantFilter $TenantFilter -SiteUrls $SiteUrls -LoginName $LoginName

        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($Removal.Succeeded.Count -gt 0) {
            $Messages.Add("Successfully removed $Label (all site groups and direct permissions) from: $($Removal.Succeeded -join ', ').")
        }
        if ($Removal.Failed.Count -gt 0) {
            $Messages.Add("Failed on: $($Removal.Failed -join '; ')")
        }
        $Results = $Messages -join ' '
        if ($Removal.Succeeded.Count -eq 0) {
            throw $Results
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to remove $Label from the selected site(s): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
