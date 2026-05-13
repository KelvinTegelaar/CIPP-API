function Invoke-AddTestReport {
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
        $Body = $Request.Body

        # Validate required fields
        if ([string]::IsNullOrEmpty($Body.name)) {
            throw 'Report name is required'
        }
        if ($Body.name.Length -gt 256) {
            throw 'Report name must be 256 characters or fewer'
        }

        $IsUpdate = -not [string]::IsNullOrWhiteSpace([string]$Body.ReportId)
        $ReportTable = Get-CippTable -tablename 'CippReportTemplates'

        # Use existing ReportId for updates, otherwise generate a new ID
        $ReportId = if ($IsUpdate) { [string]$Body.ReportId } else { [string](New-Guid) }
        $IdentityTests = $Body.IdentityTests ? ($Body.IdentityTests | ConvertTo-Json -Compress) : '[]'
        $DevicesTests = $Body.DevicesTests ? ($Body.DevicesTests | ConvertTo-Json -Compress) : '[]'
        $CustomTests = $Body.CustomTests ? ($Body.CustomTests | ConvertTo-Json -Compress) : '[]'

        $CreatedAt = [string](Get-Date).ToString('o')
        if ($IsUpdate) {
            $ExistingReport = Get-CIPPAzDataTableEntity @ReportTable -Filter "PartitionKey eq 'Report' and RowKey eq '$ReportId'"
            if (-not $ExistingReport) {
                throw 'Custom report not found'
            }
            $CreatedAt = [string]($ExistingReport.CreatedAt ?? (Get-Date).ToString('o'))
        }

        # Create report object
        $Report = [PSCustomObject]@{
            PartitionKey  = 'Report'
            RowKey        = [string]$ReportId
            name          = [string]$Body.name
            description   = [string]$Body.description
            version       = '1.0'
            IdentityTests = [string]$IdentityTests
            DevicesTests  = [string]$DevicesTests
            CustomTests   = [string]$CustomTests
            CreatedAt     = $CreatedAt
            UpdatedAt     = [string](Get-Date).ToString('o')
        }

        # Save to table
        Add-CIPPAzDataTableEntity -Entity $Report @ReportTable -Force
        $Body = [PSCustomObject]@{
            Results  = if ($IsUpdate) { 'Successfully updated custom report' } else { 'Successfully created custom report' }
            ReportId = $ReportId
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message "Failed to save report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = [PSCustomObject]@{
            Results = "Failed to save report: $($ErrorMessage.NormalizedError)"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10
        })
}
