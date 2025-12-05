function Invoke-ExecAppApprovalTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Table = Get-CIPPTable -TableName 'templates'
    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json

    $Action = $Request.Query.Action ?? $Request.Body.Action

    switch ($Action) {
        'Save' {
            try {
                $GUID = $Request.Body.TemplateId ?? (New-Guid).GUID

                # Create structured object for the template
                $templateObject = $Request.Body | Select-Object -Property * -ExcludeProperty Action, TemplateId

                # Add additional metadata
                $templateObject | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID
                $templateObject | Add-Member -NotePropertyName 'CreatedBy' -NotePropertyValue ($User.UserDetails ?? 'CIPP-API')
                $templateObject | Add-Member -NotePropertyName 'CreatedOn' -NotePropertyValue (Get-Date).ToString('o')

                # If updating an existing template, add UpdatedBy and UpdatedOn
                if ($Request.Body.TemplateId) {
                    $templateObject | Add-Member -NotePropertyName 'UpdatedBy' -NotePropertyValue ($User.UserDetails ?? 'CIPP-API')
                    $templateObject | Add-Member -NotePropertyName 'UpdatedOn' -NotePropertyValue (Get-Date).ToString('o')
                }

                # Convert to JSON, preserving the original structure
                $templateJson = $templateObject | ConvertTo-Json -Depth 10 -Compress

                # Add to templates table with AppApprovalTemplate partition key
                $Table.Force = $true
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    JSON         = [string]$templateJson
                    RowKey       = "$GUID"
                    PartitionKey = 'AppApprovalTemplate'
                }

                # Return a proper array with ONE element containing the TemplateId
                $Body = @(
                    [PSCustomObject]@{
                        'Results'  = 'Template Saved'
                        'Metadata' = @{
                            'TemplateName' = $Request.Body.TemplateName
                            'TemplateId'   = $GUID
                        }
                    }
                )

                Write-LogMessage -headers $Headers -API $APIName -message "App Deployment Template Saved: $($Request.Body.TemplateName)" -Sev 'Info'
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
                Write-LogMessage -headers $Headers -API $APIName -message "App Deployment Template Save failed: $($_.Exception.Message)" -Sev 'Error'
            }
        }
        'Delete' {
            try {
                $TemplateId = $Request.Body.TemplateId

                # Get the template to delete
                $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$TemplateId'"

                if ($Template) {
                    $TemplateData = $Template.JSON | ConvertFrom-Json
                    $TemplateName = $TemplateData.TemplateName

                    # Remove the template
                    $null = Remove-AzDataTableEntity @Table -Entity $Template -Force

                    $Body = @{
                        'Results' = "Successfully deleted template '$TemplateName'"
                    }
                    Write-LogMessage -headers $Headers -API $APIName -message "App Deployment Template deleted: $TemplateName" -Sev 'Info'
                } else {
                    $Body = @{
                        'Results' = 'No template found with the provided ID'
                    }
                }
            } catch {
                $Body = @{
                    'Results' = "Failed to delete template: $($_.Exception.Message)"
                }
                Write-LogMessage -headers $Headers -API $APIName -message "App Deployment Template Delete failed: $($_.Exception.Message)" -Sev 'Error'
            }
        }
        'Get' {
            # Check if TemplateId is provided to filter results
            $filter = "PartitionKey eq 'AppApprovalTemplate'"
            if ($Request.Query.TemplateId) {
                $templateId = $Request.Query.TemplateId
                $filter = "PartitionKey eq 'AppApprovalTemplate' and RowKey eq '$templateId'"
            }

            $Templates = Get-CIPPAzDataTableEntity @Table -Filter $filter

            $Body = $Templates | ForEach-Object {
                # Parse the JSON
                $templateData = $_.JSON | ConvertFrom-Json

                # Create output object preserving original structure
                $outputObject = $templateData | Select-Object -Property *

                # Add the TemplateId (RowKey) to the output
                $outputObject | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $_.RowKey -Force

                # Add timestamp from the table entity
                $outputObject | Add-Member -NotePropertyName 'Timestamp' -NotePropertyValue $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') -Force

                return $outputObject
            }
        }
        default {
            # Default action - list all templates
            $filter = "PartitionKey eq 'AppApprovalTemplate'"

            $Templates = Get-CIPPAzDataTableEntity @Table -Filter $filter

            $Body = $Templates | ForEach-Object {
                # Parse the JSON
                $templateData = $_.JSON | ConvertFrom-Json

                # Create output object preserving original structure
                $outputObject = $templateData | Select-Object -Property *

                # Add the TemplateId (RowKey) to the output
                $outputObject | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $_.RowKey -Force

                # Add timestamp from the table entity
                $outputObject | Add-Member -NotePropertyName 'Timestamp' -NotePropertyValue $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') -Force

                return $outputObject
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject @($Body)
        })
}
