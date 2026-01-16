function Invoke-ListTenantGroups {
    <#
    .SYNOPSIS
        Entrypoint for listing tenant groups
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $groupFilter = $Request.Query.groupId ?? $Request.Body.groupId
    $TenantGroups = (Get-TenantGroups -GroupId $groupFilter -SkipCache) ?? @()
    $Body = @{ Results = @($TenantGroups) }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
