function Invoke-ExecAPIPermissionList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.Read
    .DESCRIPTION
        Lists every CIPP API endpoint grouped by the role that gates it. Backs the permission picker in the custom role editor.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Roles = Get-CIPPHttpFunctions -ByRoleGroup | ConvertTo-Json -Depth 10

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Roles
        })
}
