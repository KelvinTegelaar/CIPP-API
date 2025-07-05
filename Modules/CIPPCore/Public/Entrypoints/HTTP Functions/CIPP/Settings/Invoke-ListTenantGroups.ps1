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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $groupFilter = $Request.Query.groupId ?? $Request.Body.groupId
    $TenantGroups = (Get-TenantGroups -GroupId $groupFilter) ?? @()
    $Body = @{ Results = @($TenantGroups) }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
