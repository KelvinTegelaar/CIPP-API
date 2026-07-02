function Invoke-ExecPermissionRepair {
    <#
    .SYNOPSIS
        Reconciles the CIPP-SAM permissions and re-applies them to the partner service principal.
    .DESCRIPTION
        Reconciles the saved additional-permission set (Update-CippSamPermissions), then refreshes the
        grants on the CIPP-SAM service principal in the PARTNER tenant so the current effective set
        (manifest + extras) is consented. This never writes the app registration's requiredResourceAccess;
        permissions are applied as service-principal grants, the same way the routine refresh does.
        Client tenants pick up the same effective set through their own permission refresh.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json
        $UpdatedBy = $User.UserDetails ?? 'CIPP-API'

        # 1) Reconcile the saved extras table (no app-registration write).
        $TableResult = Update-CippSamPermissions -UpdatedBy $UpdatedBy

        # 2) Refresh the grants on the partner CIPP-SAM service principal so the effective set
        #    (manifest + extras, read from the table) is actually consented on the SP.
        $AppResults = Add-CIPPApplicationPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -TenantFilter $env:TenantID -AsApp $true
        $DelegatedResults = Add-CIPPDelegatedPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -TenantFilter $env:TenantID -AsApp $true

        $Results = @($TableResult) + @($AppResults) + @($DelegatedResults) | Where-Object { $_ }
        Write-LogMessage -Headers $Request.Headers -API 'ExecPermissionRepair' -message "CIPP-SAM permissions repaired by $UpdatedBy" -Sev 'Info' -LogData @{ Results = @($Results) }
        $Body = @{'Results' = ($Results -join [Environment]::NewLine) }
    } catch {
        $Body = @{
            'Results' = "$($_.Exception.Message) - at line $($_.InvocationInfo.ScriptLineNumber)"
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
