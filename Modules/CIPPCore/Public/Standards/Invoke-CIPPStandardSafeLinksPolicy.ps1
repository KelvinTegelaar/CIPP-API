function Invoke-CIPPStandardSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SafeLinksPolicy
    .SYNOPSIS
        (Label) Default Safe Links Policy
    .DESCRIPTION
        (Helptext) This creates a Safe Links policy that automatically scans, tracks, and and enables safe links for Email, Office, and Teams for both external and internal senders
        (DocsDescription) This creates a Safe Links policy that automatically scans, tracks, and and enables safe links for Email, Office, and Teams for both external and internal senders
    .NOTES
        CAT
            Defender Standards
        TAG
            "CIS"
            "mdo_safelinksforemail"
            "mdo_safelinksforOfficeApps"
        ADDEDCOMPONENT
            {"type":"switch","label":"AllowClickThrough","name":"standards.SafeLinksPolicy.AllowClickThrough"}
            {"type":"switch","label":"DisableUrlRewrite","name":"standards.SafeLinksPolicy.DisableUrlRewrite"}
            {"type":"switch","label":"EnableOrganizationBranding","name":"standards.SafeLinksPolicy.EnableOrganizationBranding"}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SafeLinksPolicy.DoNotRewriteUrls","label":"Do not rewrite the following URLs in email"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-03-25
        POWERSHELLEQUIVALENT
            Set-SafeLinksPolicy or New-SafeLinksPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    Test-CIPPStandardLicense -StandardName 'SafeLinksPolicy' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    $ServicePlans = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus?$select=servicePlans' -tenantid $Tenant
    $ServicePlans = $ServicePlans.servicePlans.servicePlanName
    $MDOLicensed = $ServicePlans -contains 'ATP_ENTERPRISE'

    if ($MDOLicensed) {
        $PolicyList = @('CIPP Default SafeLinks Policy', 'Default SafeLinks Policy')
        $ExistingPolicy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksPolicy' | Where-Object -Property Name -In $PolicyList
        if ($null -eq $ExistingPolicy.Name) {
            $PolicyName = $PolicyList[0]
        } else {
            $PolicyName = $ExistingPolicy.Name
        }
        $RuleList = @( 'CIPP Default SafeLinks Rule', 'CIPP Default SafeLinks Policy')
        $ExistingRule = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksRule' | Where-Object -Property Name -In $RuleList
        if ($null -eq $ExistingRule.Name) {
            $RuleName = $RuleList[0]
        } else {
            $RuleName = $ExistingRule.Name
        }

        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksPolicy' |
            Where-Object -Property Name -EQ $PolicyName |
            Select-Object Name, EnableSafeLinksForEmail, EnableSafeLinksForTeams, EnableSafeLinksForOffice, TrackClicks, AllowClickThrough, ScanUrls, EnableForInternalSenders, DeliverMessageAfterScan, DisableUrlRewrite, EnableOrganizationBranding, DoNotRewriteUrls

        $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
        ($CurrentState.EnableSafeLinksForEmail -eq $true) -and
        ($CurrentState.EnableSafeLinksForTeams -eq $true) -and
        ($CurrentState.EnableSafeLinksForOffice -eq $true) -and
        ($CurrentState.TrackClicks -eq $true) -and
        ($CurrentState.ScanUrls -eq $true) -and
        ($CurrentState.EnableForInternalSenders -eq $true) -and
        ($CurrentState.DeliverMessageAfterScan -eq $true) -and
        ($CurrentState.AllowClickThrough -eq $Settings.AllowClickThrough) -and
        ($CurrentState.DisableUrlRewrite -eq $Settings.DisableUrlRewrite) -and
        ($CurrentState.EnableOrganizationBranding -eq $Settings.EnableOrganizationBranding) -and
        (!(Compare-Object -ReferenceObject $CurrentState.DoNotRewriteUrls -DifferenceObject ($Settings.DoNotRewriteUrls.value ?? $Settings.DoNotRewriteUrls ?? @())))

        $AcceptedDomains = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AcceptedDomain'

        $RuleState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksRule' |
            Where-Object -Property Name -EQ $RuleName |
            Select-Object Name, SafeLinksPolicy, Priority, RecipientDomainIs

        $RuleStateIsCorrect = ($RuleState.Name -eq $RuleName) -and
        ($RuleState.SafeLinksPolicy -eq $PolicyName) -and
        ($RuleState.Priority -eq 0) -and
        (!(Compare-Object -ReferenceObject $RuleState.RecipientDomainIs -DifferenceObject $AcceptedDomains.Name))

        if ($Settings.remediate -eq $true) {

            if ($StateIsCorrect -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy already correctly configured' -sev Info
            } else {
                $cmdParams = @{
                    EnableSafeLinksForEmail    = $true
                    EnableSafeLinksForTeams    = $true
                    EnableSafeLinksForOffice   = $true
                    TrackClicks                = $true
                    ScanUrls                   = $true
                    EnableForInternalSenders   = $true
                    DeliverMessageAfterScan    = $true
                    AllowClickThrough          = $Settings.AllowClickThrough
                    DisableUrlRewrite          = $Settings.DisableUrlRewrite
                    EnableOrganizationBranding = $Settings.EnableOrganizationBranding
                    DoNotRewriteUrls           = $Settings.DoNotRewriteUrls.value ?? @{'@odata.type' = '#Exchange.GenericHashTable' }
                }

                if ($CurrentState.Name -eq $Policyname) {
                    try {
                        $cmdParams.Add('Identity', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksPolicy' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLink policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update SafeLink policy $PolicyName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdParams.Add('Name', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksPolicy' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created SafeLink policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create SafeLink policy $PolicyName." -sev Error -LogData $_
                    }
                }
            }

            if ($RuleStateIsCorrect -eq $false) {
                $cmdParams = @{
                    Priority          = 0
                    RecipientDomainIs = $AcceptedDomains.Name
                }

                if ($RuleState.SafeLinksPolicy -ne $PolicyName) {
                    $cmdParams.Add('SafeLinksPolicy', $PolicyName)
                }

                if ($RuleState.Name -eq $RuleName) {
                    try {
                        $cmdParams.Add('Identity', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksRule' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLink rule $RuleName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update SafeLink rule $RuleName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdParams.Add('Name', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksRule' -cmdParams $cmdParams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created SafeLink rule $RuleName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create SafeLink rule $RuleName." -sev Error -LogData $_
                    }
                }
            }
        }

        if ($Settings.alert -eq $true) {

            if ($StateIsCorrect -eq $true) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy is enabled' -sev Info
            } else {
                Write-StandardsAlert -message 'SafeLink Policy is not enabled' -object $CurrentState -tenant $Tenant -standardName 'SafeLinksPolicy' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy is not enabled' -sev Info
            }
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeLinksPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
            if ($StateIsCorrect) {
                $FieldValue = $true
            } else {
                $FieldValue = $CurrentState
            }
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksPolicy' -FieldValue $FieldValue -Tenant $Tenant
        }
    } else {
        if ($Settings.remediate -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to create SafeLink policy: Tenant does not have Microsoft Defender for Office 365 license' -sev Error
        }

        if ($Settings.alert -eq $true) {
            Write-StandardsAlert -message 'SafeLink Policy is not enabled: Tenant does not have Microsoft Defender for Office 365 license' -object $MDOLicensed -tenant $Tenant -standardName 'SafeLinksPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy is not enabled: Tenant does not have Microsoft Defender for Office 365 license' -sev Info
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeLinksPolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksPolicy' -FieldValue $false -Tenant $Tenant
        }
    }
}
