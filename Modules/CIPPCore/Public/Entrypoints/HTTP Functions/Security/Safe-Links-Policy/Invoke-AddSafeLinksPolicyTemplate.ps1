using namespace System.Net
function Invoke-AddSafeLinksPolicyTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.SafeLinks.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    # Debug: Log the incoming request body
    Write-LogMessage -Headers $Headers -API $APIName -message "Request body: $($Request.body | ConvertTo-Json -Depth 5 -Compress)" -Sev Debug

    try {
        $GUID = (New-Guid).GUID

        # Validate required fields
        if ([string]::IsNullOrEmpty($Request.body.Name)) {
            return @{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Template name is required but was not provided' }
            }
        }

        if ([string]::IsNullOrEmpty($Request.body.PolicyName)) {
            return @{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Policy name is required but was not provided' }
            }
        }

        # Create a new ordered hashtable to store selected properties
        $policyObject = [ordered]@{}

        # Set name and comments - prioritize template-specific fields
        $policyObject['TemplateName'] = $Request.body.TemplateName
        $policyObject['TemplateDescription'] = $Request.body.TemplateDescription

        # For templates, if no specific policy description is provided, use template description as default
        if ([string]::IsNullOrEmpty($Request.body.AdminDisplayName) -and -not [string]::IsNullOrEmpty($Request.body.Description)) {
            $Request.body.AdminDisplayName = $Request.body.Description
            Write-LogMessage -Headers $Headers -API $APIName -message 'Using template description as default policy description' -Sev Debug
        }

        # Log what we're using for template name and description
        Write-LogMessage -Headers $Headers -API $APIName -message "Template Name: '$($policyObject.TemplateName)', Description: '$($policyObject.TemplateDescription)'" -Sev Debug

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
                Write-LogMessage -Headers $Headers -API $APIName -message "Added property '$prop' with value '$($Request.body.$prop)'" -Sev Debug
            }
        }

        # Convert to JSON
        $JSON = $policyObject | ConvertTo-Json -Depth 10
        Write-LogMessage -Headers $Headers -API $APIName -message "Final JSON: $JSON" -Sev Debug

        # Save the template to Azure Table Storage
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SafeLinksTemplate'
        }

        $Result = "Created SafeLinks Policy Template '$($policyObject.TemplateName)' with GUID $GUID"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create SafeLinks policy template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
