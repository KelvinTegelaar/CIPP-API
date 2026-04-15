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

    try {
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json
        $Result = Update-CippSamPermissions -UpdatedBy ($User.UserDetails ?? 'CIPP-API')
        $Body = @{'Results' = $Result }
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
