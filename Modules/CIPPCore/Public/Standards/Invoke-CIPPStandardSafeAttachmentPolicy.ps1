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
            "lowimpact"
            "CIS"
            "mdo_safedocuments"
            "mdo_commonattachmentsfilter"
            "mdo_safeattachmentpolicy"
        ADDEDCOMPONENT
            {"type":"select","multiple":false,"label":"Action","name":"standards.SafeAttachmentPolicy.Action","options":[{"label":"Allow","value":"Allow"},{"label":"Block","value":"Block"},{"label":"DynamicDelivery","value":"DynamicDelivery"}]}
            {"type":"select","multiple":false,"label":"QuarantineTag","name":"standards.SafeAttachmentPolicy.QuarantineTag","options":[{"label":"AdminOnlyAccessPolicy","value":"AdminOnlyAccessPolicy"},{"label":"DefaultFullAccessPolicy","value":"DefaultFullAccessPolicy"},{"label":"DefaultFullAccessWithNotificationPolicy","value":"DefaultFullAccessWithNotificationPolicy"}]}
            {"type":"switch","label":"Redirect","name":"standards.SafeAttachmentPolicy.Redirect"}
            {"type":"textField","name":"standards.SafeAttachmentPolicy.RedirectAddress","label":"Redirect Address","required":false}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-SafeAttachmentPolicy or New-SafeAttachmentPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SafeAttachmentPolicy'

    $ServicePlans = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus?$select=servicePlans' -tenantid $Tenant
    $ServicePlans = $ServicePlans.servicePlans.servicePlanName
    $MDOLicensed = $ServicePlans -contains "ATP_ENTERPRISE"

    if ($MDOLicensed) {
        $PolicyList = @('CIPP Default Safe Attachment Policy','Default Safe Attachment Policy')
        $ExistingPolicy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentPolicy' | Where-Object -Property Name -In $PolicyList
        if ($null -eq $ExistingPolicy.Name) {
            $PolicyName = $PolicyList[0]
        } else {
            $PolicyName = $ExistingPolicy.Name
        }
        $RuleList = @( 'CIPP Default Safe Attachment Rule','CIPP Default Safe Attachment Policy')
        $ExistingRule = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentRule' | Where-Object -Property Name -In $RuleList
        if ($null -eq $ExistingRule.Name) {
            $RuleName = $RuleList[0]
        } else {
            $RuleName = $ExistingRule.Name
        }

        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentPolicy' |
            Where-Object -Property Name -EQ $PolicyName |
            Select-Object Name, Enable, Action, QuarantineTag, Redirect, RedirectAddress

        $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
                        ($CurrentState.Enable -eq $true) -and
                        ($CurrentState.Action -eq $Settings.SafeAttachmentAction) -and
                        ($CurrentState.QuarantineTag -eq $Settings.QuarantineTag) -and
                        ($CurrentState.Redirect -eq $Settings.Redirect) -and
                        (($null -eq $Settings.RedirectAddress) -or ($CurrentState.RedirectAddress -eq $Settings.RedirectAddress))

        $AcceptedDomains = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AcceptedDomain'

        $RuleState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentRule' |
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
                $cmdparams = @{
                    Enable          = $true
                    Action          = $Settings.SafeAttachmentAction
                    QuarantineTag   = $Settings.QuarantineTag
                    Redirect        = $Settings.Redirect
                    RedirectAddress = $Settings.RedirectAddress
                }

                if ($CurrentState.Name -eq $PolicyName) {
                    try {
                        $cmdparams.Add('Identity', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeAttachmentPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Safe Attachment policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Safe Attachment policy $PolicyName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdparams.Add('Name', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeAttachmentPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Safe Attachment policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Safe Attachment policy $PolicyName." -sev Error -LogData $_
                    }
                }
            }

            if ($RuleStateIsCorrect -eq $false) {
                $cmdparams = @{
                    Priority             = 0
                    RecipientDomainIs    = $AcceptedDomains.Name
                }

                if ($RuleState.SafeAttachmentPolicy -ne $PolicyName) {
                    $cmdparams.Add('SafeAttachmentPolicy', $PolicyName)
                }

                if ($RuleState.Name -eq $RuleName) {
                    try {
                        $cmdparams.Add('Identity', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeAttachmentRule' -cmdparams $cmdparams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Safe Attachment rule $RuleName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Safe Attachment rule $RuleName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdparams.Add('Name', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeAttachmentRule' -cmdparams $cmdparams -UseSystemMailbox $true
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
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is not enabled' -sev Alert
            }
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeAttachmentPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        }
    } else {
        if ($Settings.remediate -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Safe Attachment policy: Tenant does not have Microsoft Defender for Office 365 license" -sev Error
        }

        if ($Settings.alert -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is not enabled: Tenant does not have Microsoft Defender for Office 365 license' -sev Alert
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeAttachmentPolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
        }
    }
}
