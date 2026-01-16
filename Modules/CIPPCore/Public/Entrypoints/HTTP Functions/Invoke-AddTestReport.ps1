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

        # Generate a unique ID
        $ReportId = New-Guid
        $IdentityTests = $Body.IdentityTests ? ($Body.IdentityTests | ConvertTo-Json -Compress) : '[]'
        $DevicesTests = $Body.DevicesTests ? ($Body.DevicesTests | ConvertTo-Json -Compress) : '[]'

        # Create report object
        $Report = [PSCustomObject]@{
            PartitionKey  = 'Report'
            RowKey        = [string]$ReportId
            name          = [string]$Body.name
            description   = [string]$Body.description
            version       = '1.0'
            IdentityTests = [string]$IdentityTests
            DevicesTests  = [string]$DevicesTests
            CreatedAt     = [string](Get-Date).ToString('o')
        }

        # Save to table
        $Table = Get-CippTable -tablename 'CippReportTemplates'
        Add-CIPPAzDataTableEntity -Entity $Report @Table
        $Body = [PSCustomObject]@{
            Results  = 'Successfully created custom report'
            ReportId = $ReportId
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message "Failed to create report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = [PSCustomObject]@{
            Results = "Failed to create report: $($ErrorMessage.NormalizedError)"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10
        })
}
