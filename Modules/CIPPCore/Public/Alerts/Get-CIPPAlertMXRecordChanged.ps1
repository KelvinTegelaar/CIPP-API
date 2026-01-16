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
            $PreviousRecords = $PreviousDomain.ActualMXRecords -split ',' | Sort-Object
            $CurrentRecords = $Domain.ActualMXRecords.Hostname | Sort-Object
            if ($PreviousDomain -and $PreviousRecords -ne $CurrentRecords) {
                "$($Domain.Domain): MX records changed from [$($PreviousRecords -join ', ')] to [$($CurrentRecords -join ', ')]"
            }
        }

        if ($ChangedDomains) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $ChangedDomains
        }

        # Update cache with current data
        foreach ($Domain in $DomainData) {
            $CurrentRecords = $Domain.ActualMXRecords.Hostname | Sort-Object
            $CacheEntity = @{
                PartitionKey    = [string]$TenantFilter
                RowKey          = [string]$Domain.Domain
                Domain          = [string]$Domain.Domain
                ActualMXRecords = [string]($CurrentRecords -join ',')
                LastRefresh     = [string]$Domain.LastRefresh
                MailProvider    = [string]$Domain.MailProvider
            }
            Add-CIPPAzDataTableEntity @CacheTable -Entity $CacheEntity -Force
        }
    } catch {
        Write-LogMessage -message "Failed to check MX record changes: $($_.Exception.Message)" -API 'MX Record Alert' -tenant $TenantFilter -sev Error
    }
}
