function Invoke-ListJITAllowedRoles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Role.Read
    .DESCRIPTION
        Returns the directory roles the calling user is permitted to assign via JIT Admin, based on the
        JIT Role Template(s) attached to their CIPP custom role(s). When the caller is unrestricted the
        full role catalog is available (Restricted = false).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Allowed = Get-CIPPJITAdminAllowedRoles -Headers $Request.Headers

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Restricted     = $Allowed.Restricted
                AllowedRoleIds = @($Allowed.AllowedRoleIds)
            }
        })
}
