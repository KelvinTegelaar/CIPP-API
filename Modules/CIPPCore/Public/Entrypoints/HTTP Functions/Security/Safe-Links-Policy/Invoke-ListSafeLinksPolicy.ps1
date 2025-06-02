using namespace System.Net
Function Invoke-ListSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SafeLinksPolicy.Read
    .DESCRIPTION
        This function is used to list the Safe Links policies in the tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter

    try {
        $Policies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-SafeLinksPolicy' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'
        $Rules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-SafeLinksRule' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'
        $BuiltInRules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-EOPProtectionPolicyRule' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'

        # Single-pass processing optimized for Azure Functions
        $Output = foreach ($policy in $Policies) {
            $policyName = $policy.Name

            # Find associated rule (single lookup per policy)
            $associatedRule = $null
            foreach ($rule in $Rules) {
                if ($rule.SafeLinksPolicy -eq $policyName) {
                    $associatedRule = $rule
                    break
                }
            }

            # Find matching built-in rule (single lookup per policy)
            $matchingBuiltInRule = $null
            foreach ($builtInRule in $BuiltInRules) {
                if ($policyName -like "$($builtInRule.Name)*") {
                    $matchingBuiltInRule = $builtInRule
                    break
                }
            }

            # Create output object with all properties in one go
            [PSCustomObject]@{
                # Copy all original policy properties
                Name = $policy.Name
                AdminDisplayName = $policy.AdminDisplayName
                EnableSafeLinksForEmail = $policy.EnableSafeLinksForEmail
                EnableSafeLinksForTeams = $policy.EnableSafeLinksForTeams
                EnableSafeLinksForOffice = $policy.EnableSafeLinksForOffice
                TrackClicks = $policy.TrackClicks
                AllowClickThrough = $policy.AllowClickThrough
                ScanUrls = $policy.ScanUrls
                EnableForInternalSenders = $policy.EnableForInternalSenders
                DeliverMessageAfterScan = $policy.DeliverMessageAfterScan
                DisableUrlRewrite = $policy.DisableUrlRewrite
                DoNotRewriteUrls = $policy.DoNotRewriteUrls
                CustomNotificationText = $policy.CustomNotificationText
                EnableOrganizationBranding = $policy.EnableOrganizationBranding

                # Calculated properties
                PolicyName = $policyName
                RuleName = $associatedRule.Name
                Priority = if ($matchingBuiltInRule) { $matchingBuiltInRule.Priority } else { $associatedRule.Priority }
                State = if ($matchingBuiltInRule) { $matchingBuiltInRule.State } else { $associatedRule.State }
                SentTo = $associatedRule.SentTo
                SentToMemberOf = $associatedRule.SentToMemberOf
                RecipientDomainIs = $associatedRule.RecipientDomainIs
                ExceptIfSentTo = $associatedRule.ExceptIfSentTo
                ExceptIfSentToMemberOf = $associatedRule.ExceptIfSentToMemberOf
                ExceptIfRecipientDomainIs = $associatedRule.ExceptIfRecipientDomainIs
                Description = $policy.AdminDisplayName
                IsBuiltIn = ($matchingBuiltInRule -ne $null)
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Retrieved $($Output.Count) Safe Links policies" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -message "Error retrieving Safe Links policies: $ErrorMessage" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::Forbidden
        $Output = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Output
        })
}
