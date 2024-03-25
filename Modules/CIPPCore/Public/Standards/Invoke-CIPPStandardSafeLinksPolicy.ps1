function Invoke-CIPPStandardSafeLinksPolicy {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $SafeLinkState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksPolicy' | 
    Where-Object -Property Name -eq "SafeLinks Policy" | 
    Select-Object Name, EnableSafeLinksForEmail, EnableSafeLinksForTeams, EnableSafeLinksForOffice, TrackClicks, AllowClickThrough, ScanUrls, EnableForInternalSenders, DeliverMessageAfterScan, DisableUrlRewrite, EnableOrganizationBranding

    $StateIsCorrect = if (
        ($SafeLinkState.Name -eq "SafeLinks Policy") -and
        ($SafeLinkState.EnableSafeLinksForEmail -eq $true) -and 
        ($SafeLinkState.EnableSafeLinksForTeams -eq $true) -and 
        ($SafeLinkState.EnableSafeLinksForOffice -eq $true) -and 
        ($SafeLinkState.TrackClicks -eq $true) -and 
        ($SafeLinkState.ScanUrls -eq $true) -and 
        ($SafeLinkState.EnableForInternalSenders -eq $true) -and 
        ($SafeLinkState.DeliverMessageAfterScan -eq $true) -and 
        ($SafeLinkState.AllowClickThrough -eq $Settings.AllowClickThrough) -and
        ($SafeLinkState.DisableUrlRewrite -eq $Settings.DisableUrlRewrite) -and
        ($SafeLinkState.EnableOrganizationBranding -eq $Settings.EnableOrganizationBranding)
    ) { $true } else { $false }

    if ($Settings.remediate) {
        
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy already exists.' -sev Info
        } else {
            $cmdparams = @{
                EnableSafeLinksForEmail = $true
                EnableSafeLinksForTeams = $true
                EnableSafeLinksForOffice = $true
                TrackClicks = $true
                ScanUrls = $true
                EnableForInternalSenders = $true
                DeliverMessageAfterScan = $true
                AllowClickThrough = $Settings.AllowClickThrough
                DisableUrlRewrite = $Settings.DisableUrlRewrite
                EnableOrganizationBranding = $Settings.EnableOrganizationBranding
            }

            try {
                if ($SafeLinkState.Name -eq "SafeLinks Policy") {
                    $cmdparams.Add("Name", "SafeLinks Policy")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated SafeLink Policy' -sev Info
                } else {
                    $cmdparams.Add("Identity", "SafeLinks Policy")
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created SafeLink Policy' -sev Info
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create SafeLink Policy. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'SafeLinksPolicy' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $tenant
    }
    
}