function Invoke-ListReportBuilderTemplates {
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
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'ReportBuilderTemplate'"
        $Entities = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        $Templates = @($Entities | ForEach-Object {
                $TemplateData = @{}
                $Blocks = @()
                if ($_.JSON) {
                    try {
                        $TemplateData = ConvertFrom-Json -InputObject $_.JSON
                        $Blocks = @($TemplateData.Blocks)
                    } catch {
                        $Blocks = @()
                    }
                }
                $TestCount = @($Blocks | Where-Object { $_.type -eq 'test' }).Count
                $CustomCount = @($Blocks | Where-Object { $_.type -eq 'blank' }).Count
                [PSCustomObject]@{
                    RowKey      = $_.RowKey
                    Name        = $TemplateData.Name
                    Blocks      = $Blocks
                    Sections    = $Blocks.Count
                    TestCount   = $TestCount
                    CustomCount = $CustomCount
                    CreatedAt   = $TemplateData.CreatedAt
                    GUID        = $_.GUID
                }
            })

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Templates)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message "Failed to list report builder templates: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        })
}
