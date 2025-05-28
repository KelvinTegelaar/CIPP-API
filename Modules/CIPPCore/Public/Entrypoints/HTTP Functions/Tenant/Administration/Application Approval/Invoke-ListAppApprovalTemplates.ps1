function Invoke-ListAppApprovalTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -TableName 'templates'

    try {
        # Use the templates table with AppApprovalTemplate partition key
        $filter = "PartitionKey eq 'AppApprovalTemplate'"

        $Templates = Get-CIPPAzDataTableEntity @Table -Filter $filter

        $Body = $Templates | ForEach-Object {
            try {
                # Safely parse the JSON data - handle potential invalid JSON format
                $TemplateData = $null
                if ($_.JSON) {
                    $TemplateData = $_.JSON | ConvertFrom-Json -ErrorAction Stop
                }

                # Create a base object with properties directly from the table entity
                $templateObject = [PSCustomObject]@{
                    TemplateId = $_.RowKey
                    Timestamp  = $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                }

                # Add all properties from the JSON data if available
                if ($TemplateData) {
                    foreach ($property in $TemplateData.PSObject.Properties) {
                        $templateObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                    }
                }

                return $templateObject
            } catch {
                Write-LogMessage -headers $Headers -API $APIName -message "Error processing template $($_.RowKey): $($_.Exception.Message)" -Sev 'Error'
                return [PSCustomObject]@{
                    TemplateId   = $_.RowKey
                    TemplateName = 'Error parsing template data'
                    Error        = $_.Exception.Message
                    Timestamp    = $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
            }
        }

    } catch {
        $Body = @{
            Results = "Failed to list app deployment templates: $($_.Exception.Message)"
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject @($Body)
        })
}
