function Invoke-ListGeneratedReports {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.ReportBuilder.Read
    .DESCRIPTION
        Lists generated reports from the CIPP Report Builder, filterable by tenant or report GUID.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        $TenantFilter = $Request.Query.TenantFilter ?? $Request.Query.tenantFilter
        $ReportGUID = $Request.Query.ReportGUID

        $Table = Get-CippTable -tablename 'ReportBuilderReports'
        # The list never needs a report's content, and Blocks is what makes these rows large
        $ListProperties = @('PartitionKey', 'RowKey', 'TemplateName', 'TenantFilter', 'GeneratedAt', 'Status')

        if ($ReportGUID) {
            # Fetch specific report
            $ReportGUID = try { ConvertTo-CIPPODataFilterValue -Value $ReportGUID -Type 'Guid' } catch { $FailCode = [HttpStatusCode]::BadRequest; throw }
            $Filter = "RowKey eq '$ReportGUID'"
            $Entities = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        } elseif ($TenantFilter) {
            # Fetch all reports for tenant
            $TenantFilter = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type 'String'
            if ($TenantFilter -ne 'AllTenants') {
                $Filter = "PartitionKey eq '$TenantFilter'"
                $Entities = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property $ListProperties)
            } else {
                $TenantDomains = [System.Collections.Generic.HashSet[string]]::new([string[]]@((Get-Tenants -IncludeErrors).defaultDomainName), [System.StringComparer]::OrdinalIgnoreCase)
                $Entities = @(Get-CIPPAzDataTableEntity @Table -Property $ListProperties).Where({ $TenantDomains.Contains([string]$_.PartitionKey) })
            }
        } else {
            # Fetch all reports
            $Entities = @(Get-CIPPAzDataTableEntity @Table -Property $ListProperties)
        }

        if (-not $ReportGUID) {
            # Without the split markers in the projection, split rows come back raw, so skip the part rows
            $Reports = @(foreach ($Entity in $Entities) {
                    if ($Entity.RowKey -match '-part\d+$') { continue }
                    [PSCustomObject]@{
                        RowKey       = $Entity.RowKey
                        TemplateName = $Entity.TemplateName
                        TenantFilter = $Entity.TenantFilter
                        GeneratedAt  = $Entity.GeneratedAt
                        Status       = $Entity.Status
                        ReportURL    = "/tools/report-builder?reportId=$($Entity.RowKey)"
                    }
                })
        } else {
            $Reports = @($Entities | ForEach-Object {
                    $Blocks = @()
                    if ($_.Blocks) {
                        try {
                            $Blocks = @(ConvertFrom-Json -InputObject $_.Blocks)
                        } catch {
                            $Blocks = @()
                        }
                    }
                    # Page setup and branding the report was generated with. Older reports have none,
                    # and the renderer falls back to its defaults for those.
                    $ReportSettings = $null
                    if ($_.Settings) {
                        try {
                            $ReportSettings = ConvertFrom-Json -InputObject $_.Settings
                        } catch {
                            $ReportSettings = $null
                        }
                    }
                    $SectionCount = $Blocks.Count
                    $TestCount = @($Blocks | Where-Object { $_.type -eq 'test' }).Count
                    $CustomCount = @($Blocks | Where-Object { $_.type -eq 'blank' }).Count
                    [PSCustomObject]@{
                        RowKey       = $_.RowKey
                        TemplateName = $_.TemplateName
                        TenantFilter = $_.TenantFilter
                        Blocks       = $Blocks
                        Settings     = $ReportSettings
                        Sections     = $SectionCount
                        TestCount    = $TestCount
                        CustomCount  = $CustomCount
                        GeneratedAt  = $_.GeneratedAt
                        Status       = $_.Status
                        ReportURL    = "/tools/report-builder?reportId=$($_.RowKey)"
                    }
                })
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Reports)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message "Failed to list generated reports: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = $FailCode ?? [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        })
}
