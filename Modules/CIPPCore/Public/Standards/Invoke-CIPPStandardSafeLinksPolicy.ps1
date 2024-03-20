function Invoke-CIPPStandardSafeLinksPolicy {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $SafeLinkState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksPolicy' | 
    Where-Object -Property Name -eq $Settings.Name | 
    Select-Object Name, EnableSafeLinksForEmail, EnableSafeLinksForTeams, EnableSafeLinksForOffice, TrackClicks, AllowClickThrough, ScanUrls, EnableForInternalSenders, DeliverMessageAfterScan, DisableUrlRewrite, EnableOrganizationBranding

    $StateIsCorrect = if (
        ($SafeLinkState.Name -eq $Settings.Name) -and
        ($SafeLinkState.EnableSafeLinksForEmail -eq $Settings.EnableSafeLinksForEmail) -and 
        ($SafeLinkState.EnableSafeLinksForTeams -eq $Settings.EnableSafeLinksForTeams) -and 
        ($SafeLinkState.EnableSafeLinksForOffice -eq $Settings.EnableSafeLinksForOffice) -and 
        ($SafeLinkState.TrackClicks -eq $Settings.TrackClicks) -and 
        ($SafeLinkState.ScanUrls -eq $Settings.ScanUrls) -and 
        ($SafeLinkState.EnableForInternalSenders -eq $Settings.EnableForInternalSenders) -and 
        ($SafeLinkState.DeliverMessageAfterScan -eq $Settings.DeliverMessageAfterScan) -and 
        ($SafeLinkState.AllowClickThrough -eq $Settings.AllowClickThrough) -and
        ($SafeLinkState.DisableUrlRewrite -eq $Settings.DisableUrlRewrite) -and
        ($SafeLinkState.EnableOrganizationBranding -eq $Settings.EnableOrganizationBranding)
    ) { $true } else { $false }

    if ($Settings.remediate) {
        
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy already exists.' -sev Info
        } else {
            $cmdparams = @{
                Identity = $Settings.Name
                EnableSafeLinksForEmail = $Settings.EnableSafeLinksForEmail
                EnableSafeLinksForTeams = $Settings.EnableSafeLinksForTeams
                EnableSafeLinksForOffice = $Settings.EnableSafeLinksForOffice
                TrackClicks = $Settings.TrackClicks
                ScanUrls = $Settings.ScanUrls
                EnableForInternalSenders = $Settings.EnableForInternalSenders
                DeliverMessageAfterScan = $Settings.DeliverMessageAfterScan
                AllowClickThrough = $Settings.AllowClickThrough
                DisableUrlRewrite = $Settings.DisableUrlRewrite
                EnableOrganizationBranding = $Settings.EnableOrganizationBranding
            }

            try {
                if ($SafeLinkState.Name -eq $Settings.Name) {
                    $cmdparams.Add("Identity", $Settings.Name)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated SafeLink Policy' -sev Info
                } else {
                    $cmdparams.Add("Name", $Settings.Name)
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