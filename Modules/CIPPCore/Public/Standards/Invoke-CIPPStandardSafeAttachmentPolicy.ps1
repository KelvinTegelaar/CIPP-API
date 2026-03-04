function Invoke-CIPPStandardSafeAttachmentPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SafeAttachmentPolicy
    .SYNOPSIS
        (Label) Default Safe Attachment Policy
    .DESCRIPTION
        (Helptext) This creates a Safe Attachment policy
        (DocsDescription) This creates a Safe Attachment policy
    .NOTES
        CAT
            Defender Standards
        TAG
            "CIS M365 5.0 (2.1.4)"
            "mdo_safedocuments"
            "mdo_commonattachmentsfilter"
            "mdo_safeattachmentpolicy"
            "NIST CSF 2.0 (DE.CM-09)"
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.SafeAttachmentPolicy.name","label":"Policy Name","required":true,"defaultValue":"CIPP Default Safe Attachment Policy"}
            {"type":"select","multiple":false,"label":"Safe Attachment Action","name":"standards.SafeAttachmentPolicy.SafeAttachmentAction","options":[{"label":"Allow","value":"Allow"},{"label":"Block","value":"Block"},{"label":"DynamicDelivery","value":"DynamicDelivery"}]}
            {"type":"select","multiple":false,"creatable":true,"label":"QuarantineTag","name":"standards.SafeAttachmentPolicy.QuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"switch","label":"Redirect","name":"standards.SafeAttachmentPolicy.Redirect"}
            {"type":"textField","name":"standards.SafeAttachmentPolicy.RedirectAddress","label":"Redirect Address","required":false,"condition":{"field":"standards.SafeAttachmentPolicy.Redirect","compareType":"is","compareValue":true}}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-03-25
        POWERSHELLEQUIVALENT
            Set-SafeAttachmentPolicy or New-SafeAttachmentPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SafeAttachmentPolicy' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $TenantCapabilities = Get-CIPPTenantCapabilities -TenantFilter $Tenant
    $MDOLicensed = $TenantCapabilities.ATP_ENTERPRISE -eq $true

    if ($MDOLicensed) {
        # Cache all Safe Attachment Policies to avoid duplicate API calls
        try {
            $AllSafeAttachmentPolicies = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentPolicy'
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SafeAttachmentPolicy state for $Tenant. Error: $ErrorMessage" -Sev Error
            return
        }
        # Cache all Safe Attachment Rules to avoid duplicate API calls
        try {
            $AllSafeAttachmentRule = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentRule'
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SafeAttachmentRule state for $Tenant. Error: $ErrorMessage" -Sev Error
            return
        }

        # Use custom name if provided, otherwise use default for backward compatibility
        $PolicyName = if ($Settings.name) { $Settings.name } else { 'CIPP Default Safe Attachment Policy' }
        $PolicyList = @($PolicyName, 'CIPP Default Safe Attachment Policy', 'Default Safe Attachment Policy')
        $ExistingPolicy = $AllSafeAttachmentPolicies | Where-Object -Property Name -In $PolicyList | Select-Object -First 1
        if ($null -eq $ExistingPolicy.Name) {
            # No existing policy - use the configured/default name
            $PolicyName = if ($Settings.name) { $Settings.name } else { 'CIPP Default Safe Attachment Policy' }
        } else {
            # Use existing policy name if found
            $PolicyName = $ExistingPolicy.Name
        }
        # Derive rule name from policy name, but check for old names for backward compatibility
        $DesiredRuleName = "$PolicyName Rule"
        $RuleList = @($DesiredRuleName, 'CIPP Default Safe Attachment Rule', 'CIPP Default Safe Attachment Policy')
        $ExistingRule = $AllSafeAttachmentRule | Where-Object -Property Name -In $RuleList | Select-Object -First 1
        if ($null -eq $ExistingRule.Name) {
            # No existing rule - use the derived name
            $RuleName = $DesiredRuleName
        } else {
            # Use existing rule name if found
            $RuleName = $ExistingRule.Name
        }

        $CurrentState = $AllSafeAttachmentPolicies |
            Where-Object -Property Name -EQ $PolicyName |
            Select-Object Name, Enable, Action, QuarantineTag, Redirect, RedirectAddress

        $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
        ($CurrentState.Enable -eq $true) -and
        ($CurrentState.Action -eq $Settings.SafeAttachmentAction) -and
        ($CurrentState.QuarantineTag -eq $Settings.QuarantineTag) -and
        ($CurrentState.Redirect -eq $Settings.Redirect) -and
        (($null -eq $Settings.RedirectAddress) -or ($CurrentState.RedirectAddress -eq $Settings.RedirectAddress))

        $AcceptedDomains = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AcceptedDomain'

        $RuleState = $AllSafeAttachmentRule |
        Where-Object -Property Name -EQ $RuleName |
        Select-Object Name, SafeAttachmentPolicy, Priority, RecipientDomainIs

        $RuleStateIsCorrect = ($RuleState.Name -eq $RuleName) -and
        ($RuleState.SafeAttachmentPolicy -eq $PolicyName) -and
        ($RuleState.Priority -eq 0) -and
        (!(Compare-Object -ReferenceObject $RuleState.RecipientDomainIs -DifferenceObject $AcceptedDomains.Name))

        if ($Settings.remediate -eq $true) {

            if ($StateIsCorrect -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy already correctly configured' -sev Info
            } else {
                $cmdParams = @{
                    Enable          = $true
                    Action          = $Settings.SafeAttachmentAction
                    QuarantineTag   = $Settings.QuarantineTag
                    Redirect        = $Settings.Redirect
                    RedirectAddress = $Settings.RedirectAddress
                }

                if ($CurrentState.Name -eq $PolicyName) {
                    try {
                        $cmdParams.Add('Identity', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeAttachmentPolicy' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Safe Attachment policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Safe Attachment policy $PolicyName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdParams.Add('Name', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeAttachmentPolicy' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Safe Attachment policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Safe Attachment policy $PolicyName." -sev Error -LogData $_
                    }
                }
            }

            if ($RuleStateIsCorrect -eq $false) {
                $cmdParams = @{
                    Priority          = 0
                    RecipientDomainIs = $AcceptedDomains.Name
                }

                if ($RuleState.SafeAttachmentPolicy -ne $PolicyName) {
                    $cmdParams.Add('SafeAttachmentPolicy', $PolicyName)
                }

                if ($RuleState.Name -eq $RuleName) {
                    try {
                        $cmdParams.Add('Identity', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeAttachmentRule' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Safe Attachment rule $RuleName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Safe Attachment rule $RuleName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdParams.Add('Name', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeAttachmentRule' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Safe Attachment rule $RuleName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Safe Attachment rule $RuleName." -sev Error -LogData $_
                    }
                }
            }
        }

        if ($Settings.alert -eq $true) {

            if ($StateIsCorrect -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is enabled' -sev Info
            } else {
                Write-StandardsAlert -message 'Safe Attachment Policy is not enabled' -object $CurrentState -tenant $Tenant -standardName 'SafeAttachmentPolicy' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is not enabled' -sev Info
            }
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeAttachmentPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant

            $CurrentValue = @{
                name            = $CurrentState.Name
                enable          = $CurrentState.Enable
                action          = $CurrentState.Action
                quarantineTag   = $CurrentState.QuarantineTag
                redirect        = $CurrentState.Redirect
                redirectAddress = $CurrentState.RedirectAddress
            }

            $ExpectedValue = [pscustomobject]@{
                name            = $PolicyName
                enable          = $true
                action          = $Settings.SafeAttachmentAction
                quarantineTag   = $Settings.QuarantineTag
                redirect        = $Settings.Redirect
                redirectAddress = "$($Settings.RedirectAddress)"
            }
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeAttachmentPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        }
    } else {
        if ($Settings.remediate -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to create Safe Attachment policy: Tenant does not have Microsoft Defender for Office 365 license' -sev Error
        }

        if ($Settings.alert -eq $true) {
            Write-StandardsAlert -message 'Safe Attachment Policy is not enabled: Tenant does not have Microsoft Defender for Office 365 license' -object $MDOLicensed -tenant $Tenant -standardName 'SafeAttachmentPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is not enabled: Tenant does not have Microsoft Defender for Office 365 license' -sev Info
        }

        if ($Settings.report -eq $true) {
            $state = @{ License = 'Failed to set policy: This tenant might not be licensed for this feature' }
            Add-CIPPBPAField -FieldName 'SafeAttachmentPolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeAttachmentPolicy' -FieldValue $state -Tenant $Tenant
        }
    }
}
