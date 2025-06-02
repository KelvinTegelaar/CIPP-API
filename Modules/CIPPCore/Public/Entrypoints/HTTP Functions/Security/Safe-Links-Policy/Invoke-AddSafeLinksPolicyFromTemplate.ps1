using namespace System.Net

Function Invoke-AddSafeLinksPolicyFromTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SafeLinks.ReadWrite
    .DESCRIPTION
        This function deploys a SafeLinks policy and rule from a template to selected tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $RequestBody = $Request.Body

        # Extract tenant IDs from the selectedTenants objects - just get the value property
        $SelectedTenants = $RequestBody.selectedTenants | ForEach-Object { $_.value }
        if ('AllTenants' -in $SelectedTenants) { $SelectedTenants = (Get-Tenants).defaultDomainName }

        # Parse the PolicyConfig if it's a string
        if ($RequestBody.PolicyConfig -is [string]) {
            $PolicyConfig = $RequestBody.PolicyConfig | ConvertFrom-Json -ErrorAction Stop
        } else {
            $PolicyConfig = $RequestBody.PolicyConfig
        }

        # Helper function to process array fields
        function Process-ArrayField {
            param (
                [Parameter(Mandatory = $false)]
                $Field
            )

            if ($null -eq $Field) { return @() }

            # If already an array, process each item
            if ($Field -is [array]) {
                $result = @()
                foreach ($item in $Field) {
                    if ($item -is [string]) {
                        $result += $item
                    }
                    elseif ($item -is [hashtable] -or $item -is [PSCustomObject]) {
                        # Extract value from object
                        if ($null -ne $item.value) {
                            $result += $item.value
                        }
                        elseif ($null -ne $item.userPrincipalName) {
                            $result += $item.userPrincipalName
                        }
                        elseif ($null -ne $item.id) {
                            $result += $item.id
                        }
                        else {
                            $result += $item.ToString()
                        }
                    }
                    else {
                        $result += $item.ToString()
                    }
                }
                return $result
            }

            # If it's a single object
            if ($Field -is [hashtable] -or $Field -is [PSCustomObject]) {
                if ($null -ne $Field.value) { return @($Field.value) }
                if ($null -ne $Field.userPrincipalName) { return @($Field.userPrincipalName) }
                if ($null -ne $Field.id) { return @($Field.id) }
            }

            # If it's a string, return as an array with one item
            if ($Field -is [string]) {
                return @($Field)
            }

            return @($Field)
        }

        $Results = foreach ($TenantFilter in $SelectedTenants) {
            try {
                # Extract policy name from template
                $PolicyName = $PolicyConfig.PolicyName ?? $PolicyConfig.Name
                $RuleName = $PolicyConfig.RuleName ?? $PolicyName

                # Check if policy exists by listing all policies and filtering
                $ExistingPoliciesParam = @{
                    tenantid         = $TenantFilter
                    cmdlet           = 'Get-SafeLinksPolicy'
                    useSystemMailbox = $true
                }

                $ExistingPolicies = New-ExoRequest @ExistingPoliciesParam
                $PolicyExists = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName }

                if ($PolicyExists) {
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Policy with name '$PolicyName' already exists in tenant $TenantFilter" -Sev 'Warning'
                    "Policy with name '$PolicyName' already exists in tenant $TenantFilter"
                    continue
                }

                # Check if rule exists by listing all rules and filtering
                $ExistingRulesParam = @{
                    tenantid         = $TenantFilter
                    cmdlet           = 'Get-SafeLinksRule'
                    useSystemMailbox = $true
                }

                $ExistingRules = New-ExoRequest @ExistingRulesParam
                $RuleExists = $ExistingRules | Where-Object { $_.Name -eq $RuleName }

                if ($RuleExists) {
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Rule with name '$RuleName' already exists in tenant $TenantFilter" -Sev 'Warning'
                    "Rule with name '$RuleName' already exists in tenant $TenantFilter"
                    continue
                }

                # Process arrays in the template
                $DoNotRewriteUrls = Process-ArrayField -Field $PolicyConfig.DoNotRewriteUrls
                $SentTo = Process-ArrayField -Field $PolicyConfig.SentTo
                $SentToMemberOf = Process-ArrayField -Field $PolicyConfig.SentToMemberOf
                $RecipientDomainIs = Process-ArrayField -Field $PolicyConfig.RecipientDomainIs
                $ExceptIfSentTo = Process-ArrayField -Field $PolicyConfig.ExceptIfSentTo
                $ExceptIfSentToMemberOf = Process-ArrayField -Field $PolicyConfig.ExceptIfSentToMemberOf
                $ExceptIfRecipientDomainIs = Process-ArrayField -Field $PolicyConfig.ExceptIfRecipientDomainIs

                # PART 1: Create SafeLinks Policy
                # Build command parameters for policy
                $policyParams = @{
                    Name = $PolicyName
                }

                # Only add parameters that are explicitly provided in the template
                if ($null -ne $PolicyConfig.EnableSafeLinksForEmail) { $policyParams.Add('EnableSafeLinksForEmail', $PolicyConfig.EnableSafeLinksForEmail) }
                if ($null -ne $PolicyConfig.EnableSafeLinksForTeams) { $policyParams.Add('EnableSafeLinksForTeams', $PolicyConfig.EnableSafeLinksForTeams) }
                if ($null -ne $PolicyConfig.EnableSafeLinksForOffice) { $policyParams.Add('EnableSafeLinksForOffice', $PolicyConfig.EnableSafeLinksForOffice) }
                if ($null -ne $PolicyConfig.TrackClicks) { $policyParams.Add('TrackClicks', $PolicyConfig.TrackClicks) }
                if ($null -ne $PolicyConfig.AllowClickThrough) { $policyParams.Add('AllowClickThrough', $PolicyConfig.AllowClickThrough) }
                if ($null -ne $PolicyConfig.ScanUrls) { $policyParams.Add('ScanUrls', $PolicyConfig.ScanUrls) }
                if ($null -ne $PolicyConfig.EnableForInternalSenders) { $policyParams.Add('EnableForInternalSenders', $PolicyConfig.EnableForInternalSenders) }
                if ($null -ne $PolicyConfig.DeliverMessageAfterScan) { $policyParams.Add('DeliverMessageAfterScan', $PolicyConfig.DeliverMessageAfterScan) }
                if ($null -ne $PolicyConfig.DisableUrlRewrite) { $policyParams.Add('DisableUrlRewrite', $PolicyConfig.DisableUrlRewrite) }
                if ($null -ne $DoNotRewriteUrls -and $DoNotRewriteUrls.Count -gt 0) { $policyParams.Add('DoNotRewriteUrls', $DoNotRewriteUrls) }
                if ($null -ne $PolicyConfig.AdminDisplayName) { $policyParams.Add('AdminDisplayName', $PolicyConfig.AdminDisplayName) }
                if ($null -ne $PolicyConfig.CustomNotificationText) { $policyParams.Add('CustomNotificationText', $PolicyConfig.CustomNotificationText) }
                if ($null -ne $PolicyConfig.EnableOrganizationBranding) { $policyParams.Add('EnableOrganizationBranding', $PolicyConfig.EnableOrganizationBranding) }

                $ExoPolicyRequestParam = @{
                    tenantid         = $TenantFilter
                    cmdlet           = 'New-SafeLinksPolicy'
                    cmdParams        = $policyParams
                    useSystemMailbox = $true
                }

                $null = New-ExoRequest @ExoPolicyRequestParam
                $PolicyResult = "Successfully created new SafeLinks policy '$PolicyName'"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $PolicyResult -Sev 'Info'

                # PART 2: Create SafeLinks Rule
                # Build command parameters for rule
                $ruleParams = @{
                    Name = $RuleName
                    SafeLinksPolicy = $PolicyName
                }

                # Only add parameters that are explicitly provided
                if ($null -ne $PolicyConfig.Priority) { $ruleParams.Add('Priority', $PolicyConfig.Priority) }
                if ($null -ne $PolicyConfig.Description) { $ruleParams.Add('Comments', $PolicyConfig.Description) }
                if ($null -ne $SentTo -and $SentTo.Count -gt 0) { $ruleParams.Add('SentTo', $SentTo) }
                if ($null -ne $SentToMemberOf -and $SentToMemberOf.Count -gt 0) { $ruleParams.Add('SentToMemberOf', $SentToMemberOf) }
                if ($null -ne $RecipientDomainIs -and $RecipientDomainIs.Count -gt 0) { $ruleParams.Add('RecipientDomainIs', $RecipientDomainIs) }
                if ($null -ne $ExceptIfSentTo -and $ExceptIfSentTo.Count -gt 0) { $ruleParams.Add('ExceptIfSentTo', $ExceptIfSentTo) }
                if ($null -ne $ExceptIfSentToMemberOf -and $ExceptIfSentToMemberOf.Count -gt 0) { $ruleParams.Add('ExceptIfSentToMemberOf', $ExceptIfSentToMemberOf) }
                if ($null -ne $ExceptIfRecipientDomainIs -and $ExceptIfRecipientDomainIs.Count -gt 0) { $ruleParams.Add('ExceptIfRecipientDomainIs', $ExceptIfRecipientDomainIs) }

                $ExoRuleRequestParam = @{
                    tenantid         = $TenantFilter
                    cmdlet           = 'New-SafeLinksRule'
                    cmdParams        = $ruleParams
                    useSystemMailbox = $true
                }

                $null = New-ExoRequest @ExoRuleRequestParam
                $RuleResult = "Successfully created new SafeLinks rule '$RuleName'"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $RuleResult -Sev 'Info'

                # If State is specified in the template, enable or disable the rule
                if ($null -ne $PolicyConfig.State) {
                    $Enabled = $PolicyConfig.State -eq "Enabled"
                    $EnableCmdlet = $Enabled ? 'Enable-SafeLinksRule' : 'Disable-SafeLinksRule'
                    $EnableRequestParam = @{
                        tenantid         = $TenantFilter
                        cmdlet           = $EnableCmdlet
                        cmdParams        = @{
                            Identity = $RuleName
                        }
                        useSystemMailbox = $true
                    }

                    $null = New-ExoRequest @EnableRequestParam
                    $StateMsg = $Enabled ? "enabled" : "disabled"
                }

                # Return success message as a simple string
                "Successfully deployed SafeLinks policy '$PolicyName' and rule '$RuleName' to tenant $TenantFilter" + $(if ($null -ne $PolicyConfig.State) { " (rule $StateMsg)" } else { "" })
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                $ErrorDetail = "Failed to deploy SafeLinks policy template to tenant $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ErrorDetail -Sev 'Error'

                # Return error message as a simple string
                "Failed to deploy SafeLinks policy template to tenant $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to process template deployment request. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Results}
        })
}
