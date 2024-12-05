function Invoke-CIPPStandardSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SafeLinksPolicy
    .SYNOPSIS
        (Label) Default SafeLinks Policy
    .DESCRIPTION
        (Helptext) This creates a safelink policy that automatically scans, tracks, and and enables safe links for Email, Office, and Teams for both external and internal senders
        (DocsDescription) This creates a safelink policy that automatically scans, tracks, and and enables safe links for Email, Office, and Teams for both external and internal senders
    .NOTES
        CAT
            Defender Standards
        TAG
            "lowimpact"
            "CIS"
            "mdo_safelinksforemail"
            "mdo_safelinksforOfficeApps"
        ADDEDCOMPONENT
            {"type":"boolean","label":"AllowClickThrough","name":"standards.SafeLinksPolicy.AllowClickThrough"}
            {"type":"boolean","label":"DisableUrlRewrite","name":"standards.SafeLinksPolicy.DisableUrlRewrite"}
            {"type":"boolean","label":"EnableOrganizationBranding","name":"standards.SafeLinksPolicy.EnableOrganizationBranding"}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-SafeLinksPolicy or New-SafeLinksPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SafeLinksPolicy'

    $ServicePlans = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus?$select=servicePlans' -tenantid $Tenant
    $ServicePlans = $ServicePlans.servicePlans.servicePlanName
    $MDOLicensed = $ServicePlans -contains "ATP_ENTERPRISE"

    if ($MDOLicensed) {
        $PolicyList = @('CIPP Default SafeLinks Policy','Default SafeLinks Policy')
        $ExistingPolicy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksPolicy' | Where-Object -Property Name -In $PolicyList
        if ($null -eq $ExistingPolicy.Name) {
            $PolicyName = $PolicyList[0]
        } else {
            $PolicyName = $ExistingPolicy.Name
        }
        $RuleList = @( 'CIPP Default SafeLinks Rule','CIPP Default SafeLinks Policy')
        $ExistingRule = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksRule' | Where-Object -Property Name -In $RuleList
        if ($null -eq $ExistingRule.Name) {
            $RuleName = $RuleList[0]
        } else {
            $RuleName = $ExistingRule.Name
        }

        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksPolicy' |
            Where-Object -Property Name -EQ $PolicyName |
            Select-Object Name, EnableSafeLinksForEmail, EnableSafeLinksForTeams, EnableSafeLinksForOffice, TrackClicks, AllowClickThrough, ScanUrls, EnableForInternalSenders, DeliverMessageAfterScan, DisableUrlRewrite, EnableOrganizationBranding

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
                        ($CurrentState.EnableOrganizationBranding -eq $Settings.EnableOrganizationBranding)

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
                $cmdparams = @{
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
                }

                if ($CurrentState.Name -eq $Policyname) {
                    try {
                        $cmdparams.Add('Identity', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLink policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update SafeLink policy $PolicyName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdparams.Add('Name', $PolicyName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created SafeLink policy $PolicyName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create SafeLink policy $PolicyName." -sev Error -LogData $_
                    }
                }
            }

            if ($RuleStateIsCorrect -eq $false) {
                $cmdparams = @{
                    Priority          = 0
                    RecipientDomainIs = $AcceptedDomains.Name
                }

                if ($RuleState.SafeLinksPolicy -ne $PolicyName) {
                    $cmdparams.Add('SafeLinksPolicy', $PolicyName)
                }

                if ($RuleState.Name -eq $RuleName) {
                    try {
                        $cmdparams.Add('Identity', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksRule' -cmdparams $cmdparams -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLink rule $RuleName." -sev Info
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update SafeLink rule $RuleName." -sev Error -LogData $_
                    }
                } else {
                    try {
                        $cmdparams.Add('Name', $RuleName)
                        New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksRule' -cmdparams $cmdparams -UseSystemMailbox $true
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
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy is not enabled' -sev Alert
            }
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeLinksPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        }
    } else {
        if ($Settings.remediate -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create SafeLink policy: Tenant does not have Microsoft Defender for Office 365 license" -sev Error
        }

        if ($Settings.alert -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy is not enabled: Tenant does not have Microsoft Defender for Office 365 license' -sev Alert
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeLinksPolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
        }
    }
}
