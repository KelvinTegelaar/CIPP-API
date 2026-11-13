function Invoke-ListSafeLinksPolicyTemplateDetails {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.SafeLinks.Read
    .DESCRIPTION
        This function retrieves details for a specific Safe Links policy template.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Get the template ID from query parameters
    $ID = $Request.Query.ID ?? $Request.Body.ID

    $Result = @{}

    if (-not $ID) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Template ID is required' } })
    }
    try {
        # Get the specific template from Azure Table Storage
        $Table = Get-CippTable -tablename 'templates'
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type String
        $Filter = "PartitionKey eq 'SafeLinksTemplate' and RowKey eq '$SafeID'"
        $Template = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $Template) {
            throw [System.Management.Automation.ItemNotFoundException]::new("Template with ID '$ID' not found")
        }

        # Parse the JSON data and add metadata
        $TemplateData = $Template.JSON | ConvertFrom-Json
        $TemplateData | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $Template.RowKey -Force

        $Result = $TemplateData
        $StatusCode = [HttpStatusCode]::OK
        Write-LogMessage -headers $Headers -API $APIName -message "Successfully retrieved template details for ID '$ID'" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to retrieve template details for ID '$ID'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error'
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}
