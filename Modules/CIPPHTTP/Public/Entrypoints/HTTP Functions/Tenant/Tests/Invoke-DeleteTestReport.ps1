function Invoke-DeleteTestReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Tests.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        $Table = Get-CippTable -tablename 'CippReportTemplates'
        # Validate ReportId as a GUID so it cannot inject into the filter and mass-delete reports.
        try {
            $ReportId = ConvertTo-CIPPODataFilterValue -Value ([string]$Request.Body.ReportId).ToLowerInvariant() -Type Guid
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = ConvertTo-Json -InputObject @{ Results = 'Failed to delete report: Invalid ReportId' }
                })
        }
        $ExistingReport = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Report' and RowKey eq '$ReportId'"
        if (-not $ExistingReport) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = ConvertTo-Json -InputObject @{ Results = 'Custom report not found' }
                })
        }
        Remove-CIPPAzDataTableEntity @Table -Entity $ExistingReport

        $Result = 'Successfully deleted custom report'
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -tenant 'Global' -message $Result -Sev 'Info'
        $Body = [PSCustomObject]@{
            Results = $Result
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -tenant 'Global' -message "Failed to delete report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = [PSCustomObject]@{
            Results = "Failed to delete report: $($ErrorMessage.NormalizedError)"
        }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10
        })
}
