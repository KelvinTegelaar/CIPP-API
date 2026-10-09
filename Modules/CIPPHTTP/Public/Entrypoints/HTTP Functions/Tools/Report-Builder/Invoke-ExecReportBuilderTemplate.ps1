function Invoke-ExecReportBuilderTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.ReportBuilder.ReadWrite
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
                    $FailCode = [HttpStatusCode]::BadRequest
                    throw 'Template name is required'
                }
                if ($Body.Name.Length -gt 256) {
                    $FailCode = [HttpStatusCode]::BadRequest
                    throw 'Template name must be 256 characters or fewer'
                }

                $GUID = if ($Body.GUID) { $Body.GUID } else { (New-Guid).GUID }
                # Settings carries page setup for the template — page size, orientation, and which
                # branding preset to render against. Stored as given: it is the browser that renders
                # the PDF. Templates saved before cover/footer/watermark overrides were removed may
                # still carry those keys; the renderer ignores them, so they are neither stripped
                # here nor honoured.
                $JSON = ConvertTo-Json -InputObject @{
                    Name      = $Body.Name
                    Blocks    = @($Body.Blocks)
                    Settings  = $Body.Settings
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
                    $FailCode = [HttpStatusCode]::BadRequest
                    throw 'Template GUID is required for deletion'
                }

                $ExistingEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ReportBuilderTemplate' and RowKey eq '$($Body.GUID)'"
                if ($ExistingEntity) {
                    Remove-CIPPAzDataTableEntity @Table -Entity $ExistingEntity
                    Write-LogMessage -headers $Headers -API $APIName -message "Deleted report builder template '$($Body.GUID)'" -Sev 'Info'
                    $Result = @{ Results = 'Successfully deleted report builder template' }
                } else {
                    $FailCode = [HttpStatusCode]::NotFound
                    throw 'Template not found'
                }
            }
            default {
                $FailCode = [HttpStatusCode]::BadRequest
                throw "Unknown action: $Action"
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Report builder template error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Result = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = $FailCode ?? [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Result -Depth 10
        })
}
