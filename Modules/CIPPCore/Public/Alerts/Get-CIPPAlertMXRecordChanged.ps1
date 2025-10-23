function Get-CIPPAlertMXRecordChanged {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        $InputValue
    )

    try {
        $DomainData = Get-CIPPDomainAnalyser -TenantFilter $TenantFilter
        $CacheTable = Get-CippTable -tablename 'CacheMxRecords'
        $PreviousResults = Get-CIPPAzDataTableEntity @CacheTable -Filter "PartitionKey eq '$TenantFilter'"

        $ChangedDomains = foreach ($Domain in $DomainData) {
            $PreviousDomain = $PreviousResults | Where-Object { $_.Domain -eq $Domain.Domain }
            if ($PreviousDomain -and $PreviousDomain.ActualMXRecords -ne $Domain.ActualMXRecords) {
                "$($Domain.Domain): MX records changed from [$($PreviousDomain.ActualMXRecords -join ', ')] to [$($Domain.ActualMXRecords -join ', ')]"
            }
        }

        if ($ChangedDomains) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $ChangedDomains
        }

        # Update cache with current data
        foreach ($Domain in $DomainData) {
            $CacheEntity = @{
                PartitionKey    = $TenantFilter
                RowKey          = $Domain.Domain
                Domain          = $Domain.Domain
                ActualMXRecords = $Domain.ActualMXRecords
                LastRefresh     = $Domain.LastRefresh
                MailProvider    = $Domain.MailProvider
            }
            Add-CIPPAzDataTableEntity @CacheTable -Entity $CacheEntity -Force
        }
    } catch {
        Write-LogMessage -message "Failed to check MX record changes: $($_.Exception.Message)" -API 'MX Record Alert' -tenant $TenantFilter -sev Error
    }
}
