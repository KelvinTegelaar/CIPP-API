function Invoke-ExecAPIPermissionList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Roles = Get-CIPPHttpFunctions -ByRoleGroup | ConvertTo-Json -Depth 10

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Roles
        })
}
