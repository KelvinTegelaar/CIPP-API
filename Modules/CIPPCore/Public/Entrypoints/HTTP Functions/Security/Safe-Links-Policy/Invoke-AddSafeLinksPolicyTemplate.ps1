using namespace System.Net
Function Invoke-AddSafeLinksPolicyTemplate {
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
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev Debug

    # Debug: Log the incoming request body
    Write-LogMessage -Headers $Headers -API $APINAME -message "Request body: $($Request.body | ConvertTo-Json -Depth 5 -Compress)" -Sev Debug

    try {
        $GUID = (New-Guid).GUID

        # Validate required fields
        if ([string]::IsNullOrEmpty($Request.body.Name)) {
            throw "Template name is required but was not provided"
        }

        if ([string]::IsNullOrEmpty($Request.body.PolicyName)) {
            throw "Policy name is required but was not provided"
        }

        # Create a new ordered hashtable to store selected properties
        $policyObject = [ordered]@{}

        # Set name and comments - prioritize template-specific fields
        $policyObject["TemplateName"] = $Request.body.TemplateName
        $policyObject["TemplateDescription"] = $Request.body.TemplateDescription

        # For templates, if no specific policy description is provided, use template description as default
        if ([string]::IsNullOrEmpty($Request.body.AdminDisplayName) -and -not [string]::IsNullOrEmpty($Request.body.Description)) {
            $Request.body.AdminDisplayName = $Request.body.Description
            Write-LogMessage -Headers $Headers -API $APINAME -message "Using template description as default policy description" -Sev Debug
        }

        # Log what we're using for template name and description
        Write-LogMessage -Headers $Headers -API $APINAME -message "Template Name: '$($policyObject.TemplateName)', Description: '$($policyObject.TemplateDescription)'" -Sev Debug

        # Copy specific properties we want to keep
        $propertiesToKeep = @(
            # Policy properties
            "PolicyName", "EnableSafeLinksForEmail", "EnableSafeLinksForTeams", "EnableSafeLinksForOffice",
            "TrackClicks", "AllowClickThrough", "ScanUrls", "EnableForInternalSenders",
            "DeliverMessageAfterScan", "DisableUrlRewrite", "DoNotRewriteUrls",
            "AdminDisplayName", "CustomNotificationText", "EnableOrganizationBranding",
            # Rule properties
            "RuleName", "Priority", "State", "Comments",
            "SentTo", "SentToMemberOf", "RecipientDomainIs",
            "ExceptIfSentTo", "ExceptIfSentToMemberOf", "ExceptIfRecipientDomainIs"
        )

        # Copy each property if it exists
        foreach ($prop in $propertiesToKeep) {
            if ($null -ne $Request.body.$prop) {
                $policyObject[$prop] = $Request.body.$prop
                Write-LogMessage -Headers $Headers -API $APINAME -message "Added property '$prop' with value '$($Request.body.$prop)'" -Sev Debug
            }
        }

        # Convert to JSON
        $JSON = $policyObject | ConvertTo-Json -Depth 10
        Write-LogMessage -Headers $Headers -API $APINAME -message "Final JSON: $JSON" -Sev Debug

        # Save the template to Azure Table Storage
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SafeLinksTemplate'
        }

        Write-LogMessage -Headers $Headers -API $APINAME -message "Created SafeLinks Policy Template '$($policyObject.TemplateName)' with GUID $GUID" -Sev Info
        $body = [pscustomobject]@{'Results' = "Created SafeLinks Policy Template '$($policyObject.TemplateName)' with GUID $GUID" }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APINAME -message "Failed to create SafeLinks policy template: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed to create SafeLinks policy template: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
