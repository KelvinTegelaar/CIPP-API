function Invoke-CIPPStandardSharePointMassDeletionAlert {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SharePointMassDeletionAlert
    .SYNOPSIS
        (Label) SharePoint Mass Deletion Alert
    .DESCRIPTION
        (Helptext) Sets a e-mail address to alert when a User deletes more than 20 SharePoint files within 60 minutes. NB: Requires a Office 365 E5 subscription, Office 365 E3 with Threat Intelligence or Office 365 EquivioAnalytics add-on.
        (DocsDescription) Sets a e-mail address to alert when a User deletes more than 20 SharePoint files within 60 minutes. This is useful for monitoring and ensuring that the correct SharePoint files are deleted. NB: Requires a Office 365 E5 subscription, Office 365 E3 with Threat Intelligence or Office 365 EquivioAnalytics add-on.
    .NOTES
        CAT
            Defender Standards
        TAG
        EXECUTIVETEXT
            Alerts administrators when employees delete large numbers of SharePoint files in a short time period, helping detect potential data destruction attacks, ransomware, or accidental mass deletions. This early warning system enables rapid response to protect critical business documents and data.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.SharePointMassDeletionAlert.Threshold","label":"Max files to delete within the time frame","defaultValue":20}
            {"type":"number","name":"standards.SharePointMassDeletionAlert.TimeWindow","label":"Time frame in minutes","defaultValue":60}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":true,"name":"standards.SharePointMassDeletionAlert.NotifyUser","label":"E-mail to receive the alert"}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-04-07
        POWERSHELLEQUIVALENT
            New-ProtectionAlert and Set-ProtectionAlert
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DeletedUserRentention' -TenantFilter $Tenant -RequiredCapabilities @('RMS_S_PREMIUM2')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    $PolicyName = 'CIPP SharePoint mass deletion of files by a user'

    try {
        $CurrentState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-ProtectionAlert' -Compliance |
            Where-Object { $_.Name -eq $PolicyName } |
            Select-Object -Property *
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the sharingCapability state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $EmailsOutsideSettings = $CurrentState.NotifyUser | Where-Object { $_ -notin $Settings.NotifyUser.value }
    $MissingEmailsInSettings = $Settings.NotifyUser.value | Where-Object { $_ -notin $CurrentState.NotifyUser }

    $StateIsCorrect = ($EmailsOutsideSettings.Count -eq 0) -and
    ($MissingEmailsInSettings.Count -eq 0) -and
    ($CurrentState.Threshold -eq $Settings.Threshold) -and
    ($CurrentState.TimeWindow -eq $Settings.TimeWindow)

    $CompareField = [PSCustomObject]@{
        'Threshold'  = $CurrentState.Threshold
        'TimeWindow' = $CurrentState.TimeWindow
        'NotifyUser' = $CurrentState.NotifyUser -join ', '
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint mass deletion of files alert is configured correctly' -sev Info
        } else {
            $cmdParams = @{
                'NotifyUser'      = $Settings.NotifyUser.value
                'Category'        = 'DataGovernance'
                'Operation'       = 'FileDeleted'
                'Severity'        = 'High'
                'AggregationType' = '1'
                'Threshold'       = $Settings.Threshold
                'TimeWindow'      = $Settings.TimeWindow
            }

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdParams['Identity'] = $PolicyName
                    New-ExoRequest -TenantId $Tenant -cmdlet 'Set-ProtectionAlert' -Compliance -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully configured SharePoint mass deletion of files alert' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to configure SharePoint mass deletion of files alert. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdParams['name'] = $PolicyName
                    $cmdParams['ThreatType'] = 'Activity'

                    New-ExoRequest -TenantId $Tenant -cmdlet 'New-ProtectionAlert' -Compliance -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully created SharePoint mass deletion of files alert' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to create SharePoint mass deletion of files alert. Error: $ErrorMessage" -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint mass deletion of files alert is enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'SharePoint mass deletion of files alert is disabled' -object $CompareField -tenant $tenant -standardName 'SharePointMassDeletionAlert' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint mass deletion of files alert is disabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            Threshold  = $CurrentState.Threshold
            TimeWindow = $CurrentState.TimeWindow
            NotifyUser = @($CurrentState.NotifyUser)
        }
        $ExpectedValue = @{
            Threshold  = $Settings.Threshold
            TimeWindow = $Settings.TimeWindow
            NotifyUser = @($Settings.NotifyUser.value)
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SharePointMassDeletionAlert' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'SharePointMassDeletionAlert' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
