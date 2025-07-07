using namespace System.Net

function Invoke-EditSafeLinksPolicyTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.SafeLinks.ReadWrite
    .DESCRIPTION
        This function updates an existing Safe Links policy template.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev Debug

    try {
        $ID = $Request.Body.ID

        if (-not $ID) {
            return @{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Template ID is required' }
            }
        }

        # Check if template exists
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'SafeLinksTemplate' and RowKey eq '$ID'"
        $ExistingTemplate = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $ExistingTemplate) {
            return @{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = @{ Results = "Template with ID '$ID' not found" }
            }
        }

        # Create a new ordered hashtable to store selected properties
        $policyObject = [ordered]@{}

        # Set name and comments
        $policyObject['TemplateName'] = $Request.body.TemplateName
        $policyObject['TemplateDescription'] = $Request.body.TemplateDescription

        # Copy specific properties we want to keep
        $propertiesToKeep = @(
            # Policy properties
            'PolicyName', 'EnableSafeLinksForEmail', 'EnableSafeLinksForTeams', 'EnableSafeLinksForOffice',
            'TrackClicks', 'AllowClickThrough', 'ScanUrls', 'EnableForInternalSenders',
            'DeliverMessageAfterScan', 'DisableUrlRewrite', 'DoNotRewriteUrls',
            'AdminDisplayName', 'CustomNotificationText', 'EnableOrganizationBranding',

            # Rule properties
            'RuleName', 'Priority', 'State', 'Comments',
            'SentTo', 'SentToMemberOf', 'RecipientDomainIs',
            'ExceptIfSentTo', 'ExceptIfSentToMemberOf', 'ExceptIfRecipientDomainIs'
        )

        # Copy each property if it exists
        foreach ($prop in $propertiesToKeep) {
            if ($null -ne $Request.body.$prop) {
                $policyObject[$prop] = $Request.body.$prop
            }
        }

        # Convert to JSON
        $JSON = $policyObject | ConvertTo-Json -Depth 10

        # Update the template in Azure Table Storage
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$ID"
            PartitionKey = 'SafeLinksTemplate'
        }

        $Result = "Updated SafeLinks Policy Template $($policyObject.TemplateName) with ID $ID"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update SafeLinks policy template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
