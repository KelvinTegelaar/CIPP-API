function Invoke-CIPPStandardTeamsMeetingRecordingExpiration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsMeetingRecordingExpiration
    .SYNOPSIS
        (Label) Set Teams Meeting Recording Expiration
    .DESCRIPTION
        (Helptext) Sets the default number of days after which Teams meeting recordings automatically expire. Valid values are -1 (Never Expire) or between 1 and 99999. The default value is 120 days.
        (DocsDescription) Allows administrators to configure a default expiration period (in days) for Teams meeting recordings. Recordings older than this period will be automatically moved to the recycle bin. This setting helps manage storage consumption and enforce data retention policies.
    .NOTES
        CAT
            Teams Standards
        TAG
        EXECUTIVETEXT
            Automatically removes old Teams meeting recordings after a specified period to manage storage costs and comply with data retention policies. This helps organizations balance the need to preserve important meeting content with storage efficiency and regulatory compliance requirements.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.TeamsMeetingRecordingExpiration.ExpirationDays","label":"Recording Expiration Days (e.g., 365)","required":true}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-04-17
        POWERSHELLEQUIVALENT
            Set-CsTeamsMeetingPolicy -Identity Global -MeetingRecordingExpirationDays \<days\>
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsMeetingRecordingExpiration'

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsMeetingRecordingExpiration' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1','Teams_Room_Standard')

    # Input validation

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    $ExpirationDays = try { [int64]$Settings.ExpirationDays } catch { Write-Warning "Invalid ExpirationDays value provided: $($Settings.ExpirationDays)"; return }
    if (($ExpirationDays -ne -1) -and ($ExpirationDays -lt 1 -or $ExpirationDays -gt 99999)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Invalid ExpirationDays value: $ExpirationDays. Must be -1 (Never Expire) or between 1 and 99999." -sev Error
        return
    }

    try {
        $CurrentExpirationDays = (New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' }).NewMeetingRecordingExpirationDays
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsMeetingRecordingExpiration state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $StateIsCorrect = if ($CurrentExpirationDays -eq $ExpirationDays) { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams Meeting Recording Expiration Policy already set to $ExpirationDays days." -sev Info
        } else {
            $cmdParams = @{
                Identity                          = 'Global'
                NewMeetingRecordingExpirationDays = $ExpirationDays
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -CmdParams $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully updated Teams Meeting Recording Expiration Policy to $ExpirationDays days." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Meeting Recording Expiration Policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams Meeting Recording Expiration Policy is set correctly ($($CurrentExpirationDays) days)." -sev Info
        } else {
            Write-StandardsAlert -message "Teams Meeting Recording Expiration Policy is not set correctly. Current: $CurrentExpirationDays days, Desired: $ExpirationDays days." -object $CurrentExpirationDays -tenant $Tenant -standardName 'TeamsMeetingRecordingExpiration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams Meeting Recording Expiration Policy is not set correctly (Current: $CurrentExpirationDays, Desired: $ExpirationDays)." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsMeetingRecordingExpiration' -FieldValue $CurrentExpirationDays -StoreAs string -Tenant $Tenant

        $CurrentExpirationDays = if ($StateIsCorrect) { $true } else { $CurrentExpirationDays }

        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsMeetingRecordingExpiration' -FieldValue $CurrentExpirationDays -Tenant $Tenant
    }
}
