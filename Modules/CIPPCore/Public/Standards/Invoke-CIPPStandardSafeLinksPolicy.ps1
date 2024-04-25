function Invoke-CIPPStandardSafeLinksPolicy {
    <#
    .FUNCTIONALITY
    Internal
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

    if ($Settings.remediate) {
        
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLink Policy already correctly configured' -sev Info
        } else {
            $cmdparams = @{
                EnableSafeLinksForEmail     = $true
                EnableSafeLinksForTeams     = $true
                EnableSafeLinksForOffice    = $true
                TrackClicks                 = $true
                ScanUrls                    = $true
                EnableForInternalSenders    = $true
                DeliverMessageAfterScan     = $true
                AllowClickThrough           = $Settings.AllowClickThrough
                DisableUrlRewrite           = $Settings.DisableUrlRewrite
                EnableOrganizationBranding  = $Settings.EnableOrganizationBranding
            }

            try {
                if ($CurrentState.Name -eq $PolicyName) {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated SafeLink Policy' -sev Info
                } else {
                    $cmdparams.Add('Name', $PolicyName)
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