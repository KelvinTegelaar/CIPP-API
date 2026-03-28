function Invoke-ListGeneratedReports {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.TenantFilter ?? $Request.Query.tenantFilter
        $ReportGUID = $Request.Query.ReportGUID

        $Table = Get-CippTable -tablename 'ReportBuilderReports'

        if ($ReportGUID) {
            # Fetch specific report
            $Filter = "RowKey eq '$ReportGUID'"
            $Entities = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        } elseif ($TenantFilter) {
            # Fetch all reports for tenant
            $Filter = "PartitionKey eq '$TenantFilter'"
            $Entities = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        } else {
            # Fetch all reports
            $Entities = @(Get-CIPPAzDataTableEntity @Table)
        }

        $Reports = @($Entities | ForEach-Object {
                $Blocks = @()
                if ($_.Blocks) {
                    try {
                        $Blocks = @(ConvertFrom-Json -InputObject $_.Blocks)
                    } catch {
                        $Blocks = @()
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
                    Sections     = $SectionCount
                    TestCount    = $TestCount
                    CustomCount  = $CustomCount
                    GeneratedAt  = $_.GeneratedAt
                    Status       = $_.Status
                    ReportURL    = "/tools/report-builder?reportId=$($_.RowKey)"
                }
            })

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Reports)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message "Failed to list generated reports: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        })
}
