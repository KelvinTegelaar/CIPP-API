function Invoke-CIPPStandardSafeLinksPolicy {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    SafeLinksPolicy
    .CAT
    Defender Standards
    .TAG
    "lowimpact"
    "CIS"
    "mdo_safelinksforemail"
    "mdo_safelinksforOfficeApps"
    .HELPTEXT
    This creates a safelink policy that automatically scans, tracks, and and enables safe links for Email, Office, and Teams for both external and internal senders
    .ADDEDCOMPONENT
    {"type":"boolean","label":"AllowClickThrough","name":"standards.SafeLinksPolicy.AllowClickThrough"}
    {"type":"boolean","label":"DisableUrlRewrite","name":"standards.SafeLinksPolicy.DisableUrlRewrite"}
    {"type":"boolean","label":"EnableOrganizationBranding","name":"standards.SafeLinksPolicy.EnableOrganizationBranding"}
    .LABEL
    Default SafeLinks Policy
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Set-SafeLinksPolicy or New-SafeLinksPolicy
    .RECOMMENDEDBY
    "CIS"
    .DOCSDESCRIPTION
    This creates a safelink policy that automatically scans, tracks, and and enables safe links for Email, Office, and Teams for both external and internal senders
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>





    param($Tenant, $Settings)
    $PolicyName = 'Default SafeLinks Policy'

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
        Where-Object -Property Name -EQ "CIPP $PolicyName" |
        Select-Object Name, SafeLinksPolicy, Priority, RecipientDomainIs

    $RuleStateIsCorrect = ($RuleState.Name -eq "CIPP $PolicyName") -and
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
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated SafeLink Policy' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update SafeLink Policy. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdparams.Add('Name', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksPolicy' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created SafeLink Policy' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create SafeLink Policy. Error: $ErrorMessage" -sev Error
                }
            }
        }

        if ($RuleStateIsCorrect -eq $false) {
            $cmdparams = @{
                SafeLinksPolicy   = $PolicyName
                Priority          = 0
                RecipientDomainIs = $AcceptedDomains.Name
            }

            if ($RuleState.Name -eq "CIPP $PolicyName") {
                try {
                    $cmdparams.Add('Identity', "CIPP $PolicyName")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated SafeLink Rule' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update SafeLink Rule. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdparams.Add('Name', "CIPP $PolicyName")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksRule' -cmdparams $cmdparams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created SafeLink Rule' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create SafeLink Rule. Error: $ErrorMessage" -sev Error
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

}




