function Invoke-ExecNewSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    .DESCRIPTION
        This function creates a new Safe Links policy and an associated rule.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    # Extract policy settings from body
    $PolicyName = $Request.Body.PolicyName
    $EnableSafeLinksForEmail = $Request.Body.EnableSafeLinksForEmail
    $EnableSafeLinksForTeams = $Request.Body.EnableSafeLinksForTeams
    $EnableSafeLinksForOffice = $Request.Body.EnableSafeLinksForOffice
    $TrackClicks = $Request.Body.TrackClicks
    $AllowClickThrough = $Request.Body.AllowClickThrough
    $ScanUrls = $Request.Body.ScanUrls
    $EnableForInternalSenders = $Request.Body.EnableForInternalSenders
    $DeliverMessageAfterScan = $Request.Body.DeliverMessageAfterScan
    $DisableUrlRewrite = $Request.Body.DisableUrlRewrite
    $DoNotRewriteUrls = $Request.Body.DoNotRewriteUrls
    $AdminDisplayName = $Request.Body.AdminDisplayName
    $CustomNotificationText = $Request.Body.CustomNotificationText
    $EnableOrganizationBranding = $Request.Body.EnableOrganizationBranding

    # Extract rule settings from body
    $Priority = $Request.Body.Priority
    $Comments = $Request.Body.Comments
    $State = $Request.Body.State
    $RuleName = $Request.Body.RuleName

    # Extract recipient fields and handle different input formats
    $SentTo = $Request.Body.SentTo
    $SentToMemberOf = $Request.Body.SentToMemberOf
    $RecipientDomainIs = $Request.Body.RecipientDomainIs
    $ExceptIfSentTo = $Request.Body.ExceptIfSentTo
    $ExceptIfSentToMemberOf = $Request.Body.ExceptIfSentToMemberOf
    $ExceptIfRecipientDomainIs = $Request.Body.ExceptIfRecipientDomainIs

    function Test-PolicyExists {
        param($TenantFilter, $PolicyName)
        $ExistingPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksPolicy' -useSystemMailbox $true
        return $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName }
    }

    function Test-RuleExists {
        param($TenantFilter, $RuleName)
        $ExistingRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksRule' -useSystemMailbox $true
        return $ExistingRules | Where-Object { $_.Name -eq $RuleName }
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

    # Process all array fields
    $SentTo = Process-ArrayField -Field $SentTo
    $SentToMemberOf = Process-ArrayField -Field $SentToMemberOf
    $RecipientDomainIs = Process-ArrayField -Field $RecipientDomainIs
    $ExceptIfSentTo = Process-ArrayField -Field $ExceptIfSentTo
    $ExceptIfSentToMemberOf = Process-ArrayField -Field $ExceptIfSentToMemberOf
    $ExceptIfRecipientDomainIs = Process-ArrayField -Field $ExceptIfRecipientDomainIs
    $DoNotRewriteUrls = Process-ArrayField -Field $DoNotRewriteUrls

    try {
        # Check if policy already exists
        if (Test-PolicyExists -TenantFilter $TenantFilter -PolicyName $PolicyName) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Policy '$PolicyName' already exists" -sev 'Warn'
            return "Policy '$PolicyName' already exists in tenant $TenantFilter"
        }

        # Check if rule already exists
        if (Test-RuleExists -TenantFilter $TenantFilter -RuleName $RuleName) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Rule '$RuleName' already exists" -sev 'Warn'
            return "Rule '$RuleName' already exists in tenant $TenantFilter"
        }

        # Build command parameters for policy
        $policyParams = @{
            Name = $PolicyName
        }

        # Only add parameters that are explicitly provided
        if ($null -ne $EnableSafeLinksForEmail) { $policyParams.Add('EnableSafeLinksForEmail', $EnableSafeLinksForEmail) }
        if ($null -ne $EnableSafeLinksForTeams) { $policyParams.Add('EnableSafeLinksForTeams', $EnableSafeLinksForTeams) }
        if ($null -ne $EnableSafeLinksForOffice) { $policyParams.Add('EnableSafeLinksForOffice', $EnableSafeLinksForOffice) }
        if ($null -ne $TrackClicks) { $policyParams.Add('TrackClicks', $TrackClicks) }
        if ($null -ne $AllowClickThrough) { $policyParams.Add('AllowClickThrough', $AllowClickThrough) }
        if ($null -ne $ScanUrls) { $policyParams.Add('ScanUrls', $ScanUrls) }
        if ($null -ne $EnableForInternalSenders) { $policyParams.Add('EnableForInternalSenders', $EnableForInternalSenders) }
        if ($null -ne $DeliverMessageAfterScan) { $policyParams.Add('DeliverMessageAfterScan', $DeliverMessageAfterScan) }
        if ($null -ne $DisableUrlRewrite) { $policyParams.Add('DisableUrlRewrite', $DisableUrlRewrite) }
        if ($null -ne $DoNotRewriteUrls -and $DoNotRewriteUrls.Count -gt 0) { $policyParams.Add('DoNotRewriteUrls', $DoNotRewriteUrls) }
        if ($null -ne $AdminDisplayName) { $policyParams.Add('AdminDisplayName', $AdminDisplayName) }
        if ($null -ne $CustomNotificationText) { $policyParams.Add('CustomNotificationText', $CustomNotificationText) }
        if ($null -ne $EnableOrganizationBranding) { $policyParams.Add('EnableOrganizationBranding', $EnableOrganizationBranding) }

        $ExoPolicyRequestParam = @{
            tenantid         = $TenantFilter
            cmdlet           = 'New-SafeLinksPolicy'
            cmdParams        = $policyParams
            useSystemMailbox = $true
        }

        $null = New-ExoRequest @ExoPolicyRequestParam
        $PolicyResult = "Successfully created new SafeLinks policy '$PolicyName'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $PolicyResult -Sev 'Info'

        # Build command parameters for rule
        $ruleParams = @{
            Name = $RuleName
            SafeLinksPolicy = $PolicyName
        }

        # Only add parameters that are explicitly provided
        if ($null -ne $Priority) { $ruleParams.Add('Priority', $Priority) }
        if ($null -ne $Comments) { $ruleParams.Add('Comments', $Comments) }
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

        # If State is specified, enable or disable the rule
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
        }

        $RuleResult = "Successfully created new SafeLinks rule '$RuleName'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $RuleResult -Sev 'Info'

        $Result = "Successfully created new SafeLinks policy '$PolicyName'and rule '$RuleName'"
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed creating new SafeLinks policy '$PolicyName'and rule '$RuleName'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}
