function Invoke-ExecReportBuilderTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        $Body = $Request.Body
        $Action = $Body.Action

        $Table = Get-CippTable -tablename 'templates'

        switch ($Action) {
            'save' {
                if ([string]::IsNullOrEmpty($Body.Name)) {
                    throw 'Template name is required'
                }

                $GUID = if ($Body.GUID) { $Body.GUID } else { (New-Guid).GUID }
                $JSON = ConvertTo-Json -InputObject @{
                    Name      = $Body.Name
                    Blocks    = @($Body.Blocks)
                    GUID      = $GUID
                    CreatedAt = (Get-Date).ToString('o')
                } -Depth 20 -Compress

                $Table.Force = $true
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    PartitionKey = 'ReportBuilderTemplate'
                    RowKey       = [string]$GUID
                    JSON         = [string]$JSON
                    GUID         = [string]$GUID
                }
                Write-LogMessage -headers $Headers -API $APIName -message "Saved report builder template '$($Body.Name)' with GUID $GUID" -Sev 'Info'

                $Result = @{
                    Results = "Successfully saved report builder template '$($Body.Name)'"
                    GUID    = $GUID
                }
            }
            'delete' {
                if ([string]::IsNullOrEmpty($Body.GUID)) {
                    throw 'Template GUID is required for deletion'
                }

                $ExistingEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ReportBuilderTemplate' and RowKey eq '$($Body.GUID)'"
                if ($ExistingEntity) {
                    Remove-AzDataTableEntity @Table -Entity $ExistingEntity
                    Write-LogMessage -headers $Headers -API $APIName -message "Deleted report builder template '$($Body.GUID)'" -Sev 'Info'
                    $Result = @{ Results = 'Successfully deleted report builder template' }
                } else {
                    throw 'Template not found'
                }
            }
            default {
                throw "Unknown action: $Action"
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Report builder template error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Result = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Result -Depth 10
        })
}
