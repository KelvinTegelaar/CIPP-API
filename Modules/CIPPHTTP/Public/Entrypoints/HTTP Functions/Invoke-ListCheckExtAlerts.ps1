function Invoke-ListCheckExtAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter
    $Table = Get-CIPPTable -tablename CheckExtensionAlerts

    if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
        $Filter = "PartitionKey eq 'CheckAlert' and tenantFilter eq '$TenantFilter'"
    } else {
        $Filter = "PartitionKey eq 'CheckAlert'"
    }

    try {
        $Tenants = Get-Tenants -IncludeErrors
        $Alerts = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $Tenants.defaultDomainName -contains $_.tenantFilter }) ?? @()
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve check extension alerts: $($_.Exception.Message)" -Sev 'Error'
        $Alerts = @()
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Alerts | Sort-Object -Property Timestamp -Descending)
    }
}
