function Invoke-ExecAPIPermissionList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Roles = Get-CIPPHttpFunctions -ByRoleGroup | ConvertTo-Json -Depth 10

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Roles
    }
}
