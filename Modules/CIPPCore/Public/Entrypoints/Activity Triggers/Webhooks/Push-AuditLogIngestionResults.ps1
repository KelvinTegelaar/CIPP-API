function Push-AuditLogIngestionResults {
    <#
    .SYNOPSIS
        Post-execution handler for audit log ingestion
    .DESCRIPTION
        Aggregates download results and logs timing telemetry
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        $AuditLogStateTable = Get-CippTable -tablename 'AuditLogState'

        $TotalProcessedRecords = 0
        $AggregatedTimings = @{
            Download = 0
            Cache    = 0
        }
        $StateUpdates = @{}

        $TenantFilter = $Item.Parameters.TenantFilter
        # Process each download result
        foreach ($Result in $Item.Results) {
            if ($Result.Success) {
                $TotalProcessedRecords += $Result.ProcessedRecords

                # Aggregate timings
                if ($Result.Timings) {
                    foreach ($Key in $Result.Timings.Keys) {
                        $AggregatedTimings[$Key] += $Result.Timings[$Key]
                    }
                }

                # Build state update if we have content metadata
                if ($Result.ContentCreated -and $Result.ContentId) {
                    $ContentType = $Result.ContentType

                    if (!$StateUpdates[$ContentType]) {
                        $StateRowKey = "$TenantFilter-$ContentType"
                        $StateUpdates[$ContentType] = @{
                            PartitionKey          = 'AuditLogState'
                            RowKey                = $StateRowKey
                            ContentType           = $ContentType
                            SubscriptionEnabled   = $true
                            LastContentCreatedUtc = $Result.ContentCreated.ToString('yyyy-MM-ddTHH:mm:ss')
                            LastContentId         = $Result.ContentId
                            LastProcessedUtc      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
                        }
                    } else {
                        # Update if this result is newer
                        if ([DateTime]$Result.ContentCreated -gt [DateTime]$StateUpdates[$ContentType].LastContentCreatedUtc) {
                            $StateUpdates[$ContentType].LastContentCreatedUtc = $Result.ContentCreated.ToString('yyyy-MM-ddTHH:mm:ss')
                            $StateUpdates[$ContentType].LastContentId = $Result.ContentId
                            $StateUpdates[$ContentType].LastProcessedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
                        }
                    }
                }
            }
        }

        # Write state updates
        if ($StateUpdates.Count -gt 0) {
            $UpdateEntities = @($StateUpdates.Values)
            Add-CIPPAzDataTableEntity @AuditLogStateTable -Entity $UpdateEntities -Force
        }

        # Calculate total and log telemetry
        $TotalMs = 0
        foreach ($Timing in $AggregatedTimings.Values) {
            $TotalMs += $Timing
        }

        # Add TotalStopwatch from list activity function
        if ($Item.Parameters -and $Item.Parameters.TotalStopwatch) {
            $TotalMs += $Item.Parameters.TotalStopwatch
        }

        $TimingReport = "AUDITLOG: Total: $([math]::Round($TotalMs, 2))ms"
        foreach ($Key in ($AggregatedTimings.Keys | Sort-Object)) {
            $Ms = [math]::Round($AggregatedTimings[$Key], 2)
            $Pct = if ($TotalMs -gt 0) { [math]::Round(($AggregatedTimings[$Key] / $TotalMs) * 100, 1) } else { 0 }
            $TimingReport += " | $Key : $Ms ms ($Pct %)"
        }

        Write-Host $TimingReport
        Write-LogMessage -tenant $Item.Parameters.TenantFilter -API 'AuditLogIngestion' -message $TimingReport -sev Info
        Write-LogMessage -tenant $Item.Parameters.TenantFilter -API 'AuditLogIngestion' -message "Completed ingestion: $TotalProcessedRecords total records cached" -sev Info

        return @{
            Success      = $true
            TotalRecords = $TotalProcessedRecords
            StateUpdates = $StateUpdates.Count
            TotalMs      = $TotalMs
            TimingReport = $TimingReport
        }

    } catch {
        Write-LogMessage -tenant $Item.Parameters.TenantFilter -API 'AuditLogIngestion' -message "Error in post-execution: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
