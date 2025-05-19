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
    $TenantGroups = (Get-TenantGroups -GroupId $groupFilter) ?? @()
    $Body = @{ Results = @($TenantGroups) }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
