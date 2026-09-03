function Invoke-ExecPermissionRepair {
    <#
    .SYNOPSIS
        This endpoint will update the CIPP-SAM app permissions.
    .DESCRIPTION
        Merges new permissions from the SAM manifest into the AppPermissions entry for CIPP-SAM.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint ?? 'PermissionRepair'
    $Headers = $Request.Headers

    try {
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json
        $UpdatedBy = $User.UserDetails ?? 'CIPP-API'
        $Result = Update-CippSamPermissions -UpdatedBy $UpdatedBy
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "CIPP-SAM permissions reconciled by $UpdatedBy: applied table now contains the CIPP manifest permissions plus any additional permissions." -Sev 'Info'
        $Body = @{'Results' = $Result }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to reconcile permissions: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{
            'Results' = "$($_.Exception.Message) - at line $($_.InvocationInfo.ScriptLineNumber)"
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
