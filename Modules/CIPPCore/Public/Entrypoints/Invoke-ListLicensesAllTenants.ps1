using namespace System.Net

Function Invoke-ListLicensesAllTenants {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        
    $RawGraphRequest = Get-Tenants | ForEach-Object -Parallel { 
        $domainName = $_.defaultDomainName
        
        Import-Module '.\GraphHelper.psm1'
        Import-Module '.\Modules\AzBobbyTables'
        Import-Module '.\Modules\CIPPCore'
        try {
            Write-Host "Processing $domainName"
            Get-CIPPLicenseOverview -TenantFilter $domainName
        } catch {
            [pscustomobject]@{
                Tenant         = [string]$domainName
                License        = "Could not connect to client: $($_.Exception.Message)"
                'PartitionKey' = 'License'
                'RowKey'       = "$($domainName)-$(New-Guid)"
            } 
        }
    }

    $Table = Get-CIPPTable -TableName cachelicenses
    foreach ($GraphRequest in $RawGraphRequest) {
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
    }

}
