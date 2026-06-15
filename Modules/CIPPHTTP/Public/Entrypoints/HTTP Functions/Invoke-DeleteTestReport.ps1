function Invoke-DeleteTestReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Dashboard.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $ReportId = $Request.Body.ReportId
        $Table = Get-CippTable -tablename 'CippReportTemplates'
        $ExistingReport = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$ReportId'"
        Remove-AzDataTableEntity @Table -Entity $ExistingReport

        $Body = [PSCustomObject]@{
            Results = 'Successfully deleted custom report'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message "Failed to delete report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = [PSCustomObject]@{
            Results = "Failed to delete report: $($ErrorMessage.NormalizedError)"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10
        })
}
