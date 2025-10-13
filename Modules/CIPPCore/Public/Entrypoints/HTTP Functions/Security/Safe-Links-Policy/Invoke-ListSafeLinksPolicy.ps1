Function Invoke-ListSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SafeLinksPolicy.Read
    .DESCRIPTION
        This function is used to list the Safe Links policies in the tenant, including unmatched rules and policies.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Tenantfilter = $request.Query.tenantfilter

    try {
        $Policies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-SafeLinksPolicy' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'
        $Rules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-SafeLinksRule' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'
        $BuiltInRules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-EOPProtectionPolicyRule' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'

        # Track matched items to identify orphans
        $MatchedRules = [System.Collections.Generic.HashSet[string]]::new()
        $MatchedPolicies = [System.Collections.Generic.HashSet[string]]::new()
        $MatchedBuiltInRules = [System.Collections.Generic.HashSet[string]]::new()
        $Output = [System.Collections.Generic.List[PSCustomObject]]::new()

        # First pass: Process policies with their associated rules
        foreach ($policy in $Policies) {
            $policyName = $policy.Name
            $MatchedPolicies.Add($policyName) | Out-Null

            # Find associated rule (single lookup per policy)
            $associatedRule = $null
            foreach ($rule in $Rules) {
                if ($rule.SafeLinksPolicy -eq $policyName) {
                    $associatedRule = $rule
                    $MatchedRules.Add($rule.Name) | Out-Null
                    break
                }
            }

            # Find matching built-in rule (single lookup per policy)
            $matchingBuiltInRule = $null
            foreach ($builtInRule in $BuiltInRules) {
                if ($policyName -like "$($builtInRule.Name)*") {
                    $matchingBuiltInRule = $builtInRule
                    $MatchedBuiltInRules.Add($builtInRule.Name) | Out-Null
                    break
                }
            }

            # Create output object for matched policy
            $OutputItem = [PSCustomObject]@{
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
                IsValid = $policy.IsValid
                ConfigurationStatus = if ($associatedRule) { "Complete" } else { "Policy Only (Missing Rule)" }
            }
            $Output.Add($OutputItem)
        }

        # Second pass: Add unmatched rules (orphaned rules without policies)
        foreach ($rule in $Rules) {
            if (-not $MatchedRules.Contains($rule.Name)) {
                # This rule doesn't have a matching policy
                $OutputItem = [PSCustomObject]@{
                    # Policy properties (null since no policy exists)
                    Name = $null
                    AdminDisplayName = $null
                    EnableSafeLinksForEmail = $null
                    EnableSafeLinksForTeams = $null
                    EnableSafeLinksForOffice = $null
                    TrackClicks = $null
                    AllowClickThrough = $null
                    ScanUrls = $null
                    EnableForInternalSenders = $null
                    DeliverMessageAfterScan = $null
                    DisableUrlRewrite = $null
                    DoNotRewriteUrls = $null
                    CustomNotificationText = $null
                    EnableOrganizationBranding = $null

                    # Rule properties
                    PolicyName = $rule.SafeLinksPolicy
                    RuleName = $rule.Name
                    Priority = $rule.Priority
                    State = $rule.State
                    SentTo = $rule.SentTo
                    SentToMemberOf = $rule.SentToMemberOf
                    RecipientDomainIs = $rule.RecipientDomainIs
                    ExceptIfSentTo = $rule.ExceptIfSentTo
                    ExceptIfSentToMemberOf = $rule.ExceptIfSentToMemberOf
                    ExceptIfRecipientDomainIs = $rule.ExceptIfRecipientDomainIs
                    Description = $rule.Comments
                    IsBuiltIn = $false
                    ConfigurationStatus = "Rule Only (Missing Policy: $($rule.SafeLinksPolicy))"
                }
                $Output.Add($OutputItem)
            }
        }

        # Third pass: Add unmatched built-in rules
        foreach ($builtInRule in $BuiltInRules) {
            if (-not $MatchedBuiltInRules.Contains($builtInRule.Name)) {
                # Check if this built-in rule might be SafeLinks related
                if ($builtInRule.Name -like "*SafeLinks*" -or $builtInRule.Name -like "*Safe*Links*") {
                    $OutputItem = [PSCustomObject]@{
                        # Policy properties (null since no policy exists)
                        Name = $null
                        AdminDisplayName = $null
                        EnableSafeLinksForEmail = $null
                        EnableSafeLinksForTeams = $null
                        EnableSafeLinksForOffice = $null
                        TrackClicks = $null
                        AllowClickThrough = $null
                        ScanUrls = $null
                        EnableForInternalSenders = $null
                        DeliverMessageAfterScan = $null
                        DisableUrlRewrite = $null
                        DoNotRewriteUrls = $null
                        CustomNotificationText = $null
                        EnableOrganizationBranding = $null

                        # Built-in rule properties
                        PolicyName = $null
                        RuleName = $builtInRule.Name
                        Priority = $builtInRule.Priority
                        State = $builtInRule.State
                        SentTo = $builtInRule.SentTo
                        SentToMemberOf = $builtInRule.SentToMemberOf
                        RecipientDomainIs = $builtInRule.RecipientDomainIs
                        ExceptIfSentTo = $builtInRule.ExceptIfSentTo
                        ExceptIfSentToMemberOf = $builtInRule.ExceptIfSentToMemberOf
                        ExceptIfRecipientDomainIs = $builtInRule.ExceptIfRecipientDomainIs
                        Description = $builtInRule.Comments
                        IsBuiltIn = $true
                        ConfigurationStatus = "Built-In Rule Only (No Associated Policy)"
                    }
                    $Output.Add($OutputItem)
                }
            }
        }

        # Sort output by ConfigurationStatus and Name for better organization
        $SortedOutput = $Output.ToArray() | Sort-Object ConfigurationStatus, Name, RuleName

        # Generate summary statistics
        $CompleteConfigs = ($SortedOutput | Where-Object { $_.ConfigurationStatus -eq "Complete" }).Count
        $PolicyOnlyConfigs = ($SortedOutput | Where-Object { $_.ConfigurationStatus -like "*Policy Only*" }).Count
        $RuleOnlyConfigs = ($SortedOutput | Where-Object { $_.ConfigurationStatus -like "*Rule Only*" }).Count
        $BuiltInOnlyConfigs = ($SortedOutput | Where-Object { $_.ConfigurationStatus -like "*Built-In Rule Only*" }).Count

        if ($PolicyOnlyConfigs -gt 0 -or $RuleOnlyConfigs -gt 0) {
            Write-LogMessage -headers $Headers -API $APIName -message "Found $($PolicyOnlyConfigs + $RuleOnlyConfigs) orphaned SafeLinks configurations that may need attention" -Sev 'Warning'
        }

        $StatusCode = [HttpStatusCode]::OK
        $FinalOutput = $SortedOutput
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -message "Error retrieving Safe Links policies: $ErrorMessage" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::Forbidden
        $FinalOutput = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $FinalOutput
        })
}
