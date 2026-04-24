Function Invoke-CreateSafeLinksPolicyTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.SafeLinks.ReadWrite
    .DESCRIPTION
        This function creates a new Safe Links policy template from scratch.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev Debug

    try {
        $GUID = (New-Guid).GUID

        # Create a new ordered hashtable to store selected properties
        $policyObject = [ordered]@{}

        # Set name and comments first
        $policyObject["TemplateName"] = $Request.body.TemplateName
        $policyObject["TemplateDescription"] = $Request.body.TemplateDescription

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
            }
        }

        # Convert to JSON
        $JSON = $policyObject | ConvertTo-Json -Depth 10

        # Save the template to Azure Table Storage
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SafeLinksTemplate'
        }

        Write-LogMessage -Headers $Headers -API $APINAME -message "Created SafeLinks Policy Template $($policyObject.TemplateName) with GUID $GUID" -Sev Info
        $body = [pscustomobject]@{'Results' = "Created SafeLinks Policy Template $($policyObject.TemplateName) with GUID $GUID" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APINAME -message "Failed to create SafeLinks policy template: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed to create SafeLinks policy template: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
