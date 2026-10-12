function Invoke-EditContactTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Contact.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-Host ($request | ConvertTo-Json -Depth 10 -Compress)

    # Get the ContactTemplateID from the request body
    $ContactTemplateID = $Request.body.ContactTemplateID

    if (-not $ContactTemplateID) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{'Results' = 'Failed to update Contact template: ContactTemplateID is required for editing a template' }
            })
    }

    try {
        # Check if the template exists
        $Table = Get-CippTable -tablename 'templates'
        $SafeContactTemplateID = ConvertTo-CIPPODataFilterValue -Value $ContactTemplateID -Type Guid
        $Filter = "PartitionKey eq 'ContactTemplate' and RowKey eq '$SafeContactTemplateID'"
        $ExistingTemplate = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $ExistingTemplate) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = [pscustomobject]@{'Results' = "Failed to update Contact template: Contact template with ID $ContactTemplateID not found" }
                })
        }

        Write-LogMessage -Headers $Headers -API $APINAME -message "Updating Contact Template with ID: $ContactTemplateID" -Sev Info

        # Create a new ordered hashtable to store selected properties
        $contactObject = [ordered]@{}

        # Set name and comments
        $contactObject['name'] = $Request.body.displayName
        $contactObject['comments'] = "Contact template updated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

        # Copy specific properties we want to keep
        $propertiesToKeep = @(
            'displayName', 'firstName', 'lastName', 'email', 'hidefromGAL', 'streetAddress', 'postalCode',
            'city', 'state', 'country', 'companyName', 'mobilePhone', 'businessPhone', 'jobTitle', 'website', 'mailTip'
        )

        # Copy each property from the request
        foreach ($prop in $propertiesToKeep) {
            if ($null -ne $Request.body.$prop) {
                $contactObject[$prop] = $Request.body.$prop
            }
        }

        # Convert to JSON
        $JSON = $contactObject | ConvertTo-Json -Depth 10

        # Overwrite the template in Azure Table Storage
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$ContactTemplateID"
            PartitionKey = 'ContactTemplate'
        }

        Write-LogMessage -Headers $Headers -API $APINAME -message "Updated Contact Template $($contactObject.name) with GUID $ContactTemplateID" -Sev Info
        $body = [pscustomobject]@{'Results' = "Updated Contact Template $($contactObject.name) with GUID $ContactTemplateID" }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APINAME -message "Failed to update Contact template: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed to update Contact template: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
