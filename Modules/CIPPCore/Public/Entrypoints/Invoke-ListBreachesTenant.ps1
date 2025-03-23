using namespace System.Net

Function Invoke-ListBreachesTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.query.tenantFilter

    $Table = Get-CIPPTable -TableName UserBreaches
    if ($TenantFilter -ne 'AllTenants') {
        $filter = "PartitionKey eq '$TenantFilter'"
    } else {
        $filter = $null
    }
    try {
        $usersResults = (Get-CIPPAzDataTableEntity @Table -Filter $filter).breaches | ConvertFrom-Json -ErrorAction SilentlyContinue
    } catch {
        $usersResults = $null
    }
    if ($null -eq $usersResults) {
        $usersResults = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($usersResults)
        })

}
