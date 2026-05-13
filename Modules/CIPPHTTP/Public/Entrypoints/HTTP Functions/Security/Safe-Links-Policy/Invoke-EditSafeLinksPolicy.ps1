function Invoke-EditSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    .DESCRIPTION
        This function modifies an existing Safe Links policy and its associated rule.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $PolicyName = $Request.Query.PolicyName ?? $Request.Body.PolicyName
    $RuleName = $Request.Query.RuleName ?? $Request.Body.RuleName

    # Helper function to process array fields
    function Process-ArrayField {
        param (
            [Parameter(Mandatory = $false)]
            $Field
        )

        if ($null -eq $Field) { return @() }

        # If already an array, process each item
        if ($Field -is [array]) {
            $result = [System.Collections.ArrayList]@()
            foreach ($item in $Field) {
                if ($item -is [string]) {
                    $result.Add($item) | Out-Null
                }
                elseif ($item -is [hashtable] -or $item -is [PSCustomObject]) {
                    # Extract value from object
                    if ($null -ne $item.value) {
                        $result.Add($item.value) | Out-Null
                    }
                    elseif ($null -ne $item.userPrincipalName) {
                        $result.Add($item.userPrincipalName) | Out-Null
                    }
                    elseif ($null -ne $item.id) {
                        $result.Add($item.id) | Out-Null
                    }
                    else {
                        $result.Add($item.ToString()) | Out-Null
                    }
                }
                else {
                    $result.Add($item.ToString()) | Out-Null
                }
            }
            return $result.ToArray()
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

    # Extract policy parameters from body
    $EnableSafeLinksForEmail = $Request.Body.EnableSafeLinksForEmail
    $EnableSafeLinksForTeams = $Request.Body.EnableSafeLinksForTeams
    $EnableSafeLinksForOffice = $Request.Body.EnableSafeLinksForOffice
    $TrackClicks = $Request.Body.TrackClicks
    $AllowClickThrough = $Request.Body.AllowClickThrough
    $ScanUrls = $Request.Body.ScanUrls
    $EnableForInternalSenders = $Request.Body.EnableForInternalSenders
    $DeliverMessageAfterScan = $Request.Body.DeliverMessageAfterScan
    $DisableUrlRewrite = $Request.Body.DisableUrlRewrite
    $DoNotRewriteUrls = Process-ArrayField -Field $Request.Body.DoNotRewriteUrls
    $AdminDisplayName = $Request.Body.AdminDisplayName
    $CustomNotificationText = $Request.Body.CustomNotificationText
    $EnableOrganizationBranding = $Request.Body.EnableOrganizationBranding

    # Extract rule parameters from body
    $Priority = $Request.Body.Priority
    $Comments = $Request.Body.Comments
    $State = $Request.Body.State

    # Process recipient-related parameters
    $SentTo = Process-ArrayField -Field $Request.Body.SentTo
    $SentToMemberOf = Process-ArrayField -Field $Request.Body.SentToMemberOf
    $RecipientDomainIs = Process-ArrayField -Field $Request.Body.RecipientDomainIs
    $ExceptIfSentTo = Process-ArrayField -Field $Request.Body.ExceptIfSentTo
    $ExceptIfSentToMemberOf = Process-ArrayField -Field $Request.Body.ExceptIfSentToMemberOf
    $ExceptIfRecipientDomainIs = Process-ArrayField -Field $Request.Body.ExceptIfRecipientDomainIs

    $Results = [System.Collections.ArrayList]@()
    $hasPolicyParams = $false
    $hasRuleParams = $false
    $hasRuleOperation = $false
    $ruleMessages = [System.Collections.ArrayList]@()

    try {
        # Check which types of updates we need to perform
        # PART 1: Build and check policy parameters
        $policyParams = @{
            Identity = $PolicyName
        }

        # Only add parameters that are explicitly provided
        if ($null -ne $EnableSafeLinksForEmail) { $policyParams.Add('EnableSafeLinksForEmail', $EnableSafeLinksForEmail); $hasPolicyParams = $true }
        if ($null -ne $EnableSafeLinksForTeams) { $policyParams.Add('EnableSafeLinksForTeams', $EnableSafeLinksForTeams); $hasPolicyParams = $true }
        if ($null -ne $EnableSafeLinksForOffice) { $policyParams.Add('EnableSafeLinksForOffice', $EnableSafeLinksForOffice); $hasPolicyParams = $true }
        if ($null -ne $TrackClicks) { $policyParams.Add('TrackClicks', $TrackClicks); $hasPolicyParams = $true }
        if ($null -ne $AllowClickThrough) { $policyParams.Add('AllowClickThrough', $AllowClickThrough); $hasPolicyParams = $true }
        if ($null -ne $ScanUrls) { $policyParams.Add('ScanUrls', $ScanUrls); $hasPolicyParams = $true }
        if ($null -ne $EnableForInternalSenders) { $policyParams.Add('EnableForInternalSenders', $EnableForInternalSenders); $hasPolicyParams = $true }
        if ($null -ne $DeliverMessageAfterScan) { $policyParams.Add('DeliverMessageAfterScan', $DeliverMessageAfterScan); $hasPolicyParams = $true }
        if ($null -ne $DisableUrlRewrite) { $policyParams.Add('DisableUrlRewrite', $DisableUrlRewrite); $hasPolicyParams = $true }
        if ($null -ne $DoNotRewriteUrls -and $DoNotRewriteUrls.Count -gt 0) { $policyParams.Add('DoNotRewriteUrls', $DoNotRewriteUrls); $hasPolicyParams = $true }
        if ($null -ne $AdminDisplayName) { $policyParams.Add('AdminDisplayName', $AdminDisplayName); $hasPolicyParams = $true }
        if ($null -ne $CustomNotificationText) { $policyParams.Add('CustomNotificationText', $CustomNotificationText); $hasPolicyParams = $true }
        if ($null -ne $EnableOrganizationBranding) { $policyParams.Add('EnableOrganizationBranding', $EnableOrganizationBranding); $hasPolicyParams = $true }

        # PART 2: Build and check rule parameters
        $ruleParams = @{
            Identity = $RuleName
        }

        # Add parameters that are explicitly provided
        if ($null -ne $Comments) { $ruleParams.Add('Comments', $Comments); $hasRuleParams = $true }
        if ($null -ne $Priority) { $ruleParams.Add('Priority', $Priority); $hasRuleParams = $true }
        if ($SentTo.Count -gt 0) { $ruleParams.Add('SentTo', $SentTo); $hasRuleParams = $true }
        if ($SentToMemberOf.Count -gt 0) { $ruleParams.Add('SentToMemberOf', $SentToMemberOf); $hasRuleParams = $true }
        if ($RecipientDomainIs.Count -gt 0) { $ruleParams.Add('RecipientDomainIs', $RecipientDomainIs); $hasRuleParams = $true }
        if ($ExceptIfSentTo.Count -gt 0) { $ruleParams.Add('ExceptIfSentTo', $ExceptIfSentTo); $hasRuleParams = $true }
        if ($ExceptIfSentToMemberOf.Count -gt 0) { $ruleParams.Add('ExceptIfSentToMemberOf', $ExceptIfSentToMemberOf); $hasRuleParams = $true }
        if ($ExceptIfRecipientDomainIs.Count -gt 0) { $ruleParams.Add('ExceptIfRecipientDomainIs', $ExceptIfRecipientDomainIs); $hasRuleParams = $true }

        # Now perform only the necessary operations

        # PART 1: Update policy if needed
        if ($hasPolicyParams) {
            $ExoPolicyRequestParam = @{
                tenantid         = $TenantFilter
                cmdlet           = 'Set-SafeLinksPolicy'
                cmdParams        = $policyParams
                useSystemMailbox = $true
            }

            $null = New-ExoRequest @ExoPolicyRequestParam
            $Results.Add("Successfully updated SafeLinks policy '$PolicyName'") | Out-Null
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Updated SafeLinks policy '$PolicyName'" -Sev 'Info'
        }

        # PART 2: Update rule if needed
        if ($hasRuleParams) {
            $ExoRuleRequestParam = @{
                tenantid         = $TenantFilter
                cmdlet           = 'Set-SafeLinksRule'
                cmdParams        = $ruleParams
                useSystemMailbox = $true
            }

            $null = New-ExoRequest @ExoRuleRequestParam
            $hasRuleOperation = $true
            $ruleMessages.Add("updated properties") | Out-Null
        }

        # Handle enable/disable if needed
        if ($null -ne $State) {
            $EnableCmdlet = $State ? 'Enable-SafeLinksRule' : 'Disable-SafeLinksRule'
            $EnableRequestParam = @{
                tenantid         = $TenantFilter
                cmdlet           = $EnableCmdlet
                cmdParams        = @{
                    Identity = $RuleName
                }
                useSystemMailbox = $true
            }

            $null = New-ExoRequest @EnableRequestParam
            $hasRuleOperation = $true
            $State = $State ? "enabled" : "disabled"
            $ruleMessages.Add($State) | Out-Null
        }

        # Add combined rule message if any rule operations were performed
        if ($hasRuleOperation) {
            $ruleOperations = $ruleMessages -join " and "
            $Results.Add("Successfully $ruleOperations SafeLinks rule '$RuleName'") | Out-Null
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$ruleOperations SafeLinks rule '$RuleName'" -Sev 'Info'
        }

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results.Add("Failed updating SafeLinks configuration '$PolicyName'. Error: $($ErrorMessage.NormalizedError)") | Out-Null
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed updating SafeLinks configuration '$PolicyName'. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Results }
        })
}
