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
            try {
                $PreviousDomain = $PreviousResults | Where-Object { $_.Domain -eq $Domain.Domain }
                $PreviousRecords = if ($PreviousDomain.ActualMXRecords) { @($PreviousDomain.ActualMXRecords -split ',' | Sort-Object) } else { @() }
                $CurrentRecords = if ($Domain.ActualMXRecords.Hostname) { @($Domain.ActualMXRecords.Hostname | Sort-Object) } else { @() }

                # Only compare if both have records
                $Differences = $null
                if ($PreviousRecords.Count -gt 0 -and $CurrentRecords.Count -gt 0) {
                    $Differences = Compare-Object -ReferenceObject $PreviousRecords -DifferenceObject $CurrentRecords
                }

                if ($PreviousRecords.Count -eq 0 -and $CurrentRecords.Count -gt 0) {
                    Write-Information "New MX records detected for domain $($Domain.Domain): $($CurrentRecords -join ', ')"
                    $Differences = 'NewRecords'
                } elseif ($PreviousRecords.Count -gt 0 -and $CurrentRecords.Count -eq 0) {
                    Write-Information "All MX records removed for domain $($Domain.Domain). Previous records were: $($PreviousRecords -join ', ')"
                    $Differences = 'RemovedRecords'
                }

                if ($Differences) {
                    "$($Domain.Domain): MX records changed from [$($PreviousRecords -join ', ')] to [$($CurrentRecords -join ', ')]"
                }
            } catch {
                Write-Information "Error checking domain $($Domain.Domain): $($_.Exception.Message)"
            }
        }
        # Update cache with current data
        foreach ($Domain in $DomainData) {
            $CurrentRecords = @($Domain.ActualMXRecords.Hostname | Sort-Object)
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

        if ($ChangedDomains) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $ChangedDomains
        }
        return $true

    } catch {
        Write-LogMessage -message "Failed to check MX record changes: $($_.Exception.Message)" -API 'MX Record Alert' -tenant $TenantFilter -sev Error
    }
}
