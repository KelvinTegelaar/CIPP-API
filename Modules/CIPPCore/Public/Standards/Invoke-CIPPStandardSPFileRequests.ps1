function Invoke-CIPPStandardSPFileRequests {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPFileRequests
    .SYNOPSIS
        (Label) Set SharePoint and OneDrive File Requests
    .DESCRIPTION
        (Helptext) Enables or disables File Requests for SharePoint and OneDrive, allowing users to create secure upload-only links. Optionally sets the maximum number of days for the link to remain active.
        (DocsDescription) File Requests allow users to create secure upload-only share links where uploads are hidden from other people using the link. This creates a secure and private way for people to upload files to a folder. This standard enables or disables this feature and optionally configures link expiration settings.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.SPFileRequests.state","label":"Enable File Requests"}
            {"type":"number","name":"standards.SPFileRequests.expirationDays","label":"Link Expiration Days (Optional - 1-730)","required":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-07-30
        POWERSHELLEQUIVALENT
            Set-SPOTenant -CoreRequestFilesLinkEnabled \$true -OneDriveRequestFilesLinkEnabled \$true -CoreRequestFilesLinkExpirationInDays 30 -OneDriveRequestFilesLinkExpirationInDays 30
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPFileRequests' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU','ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'The tenant is not licenced for this standard SPFileRequests' -sev Error
        return $true
    }

    try {
        $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant | Select-Object _ObjectIdentity_, TenantFilter, CoreRequestFilesLinkEnabled, OneDriveRequestFilesLinkEnabled, CoreRequestFilesLinkExpirationInDays, OneDriveRequestFilesLinkExpirationInDays
    }
    catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to get current state of SPO tenant details' -sev Error
        return
    }

    # Input validation
    if (($Settings.state -eq $null) -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Invalid state parameter set for standard SPFileRequests' -sev Error
        return
    }

    $WantedState = $Settings.state
    $ExpirationDays = $Settings.expirationDays
    $HumanReadableState = if ($WantedState -eq $true) { 'enabled' } else { 'disabled' }

    # Check if current state matches desired state
    $CoreStateIsCorrect = if ($CurrentState.CoreRequestFilesLinkEnabled -eq $WantedState) { $true } else { $false }
    $OneDriveStateIsCorrect = if ($CurrentState.OneDriveRequestFilesLinkEnabled -eq $WantedState) { $true } else { $false }
    $StateIsCorrect = $CoreStateIsCorrect -and $OneDriveStateIsCorrect

    # Check expiration settings if specified
    $ExpirationIsCorrect = $true
    if ($ExpirationDays -ne $null -and $WantedState -eq $true) {
        $CoreExpirationIsCorrect = ($CurrentState.CoreRequestFilesLinkExpirationInDays -eq $ExpirationDays)
        $OneDriveExpirationIsCorrect = ($CurrentState.OneDriveRequestFilesLinkExpirationInDays -eq $ExpirationDays)
        $ExpirationIsCorrect = $CoreExpirationIsCorrect -and $OneDriveExpirationIsCorrect
    }

    $AllSettingsCorrect = $StateIsCorrect -and $ExpirationIsCorrect

    if ($Settings.remediate -eq $true) {

        if ($AllSettingsCorrect -eq $false) {
            try {
                $Properties = @{
                    CoreRequestFilesLinkEnabled = $WantedState
                    OneDriveRequestFilesLinkEnabled = $WantedState
                }

                # Add expiration settings if specified and feature is being enabled
                if ($ExpirationDays -ne $null -and $WantedState -eq $true) {
                    $Properties['CoreRequestFilesLinkExpirationInDays'] = $ExpirationDays
                    $Properties['OneDriveRequestFilesLinkExpirationInDays'] = $ExpirationDays
                }

                $CurrentState | Set-CIPPSPOTenant -Properties $Properties

                $ExpirationMessage = if ($ExpirationDays -ne $null -and $WantedState -eq $true) { " with $ExpirationDays day expiration" } else { "" }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set File Requests to $HumanReadableState$ExpirationMessage" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set File Requests to $HumanReadableState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            $ExpirationMessage = if ($ExpirationDays -ne $null -and $WantedState -eq $true) { " with $ExpirationDays day expiration" } else { "" }
            Write-LogMessage -API 'Standards' -tenant $tenant -message "File Requests are already set to the wanted state of $HumanReadableState$ExpirationMessage" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($AllSettingsCorrect -eq $true) {
            $ExpirationMessage = if ($ExpirationDays -ne $null -and $WantedState -eq $true) { " with $ExpirationDays day expiration" } else { "" }
            Write-LogMessage -API 'Standards' -tenant $tenant -message "File Requests are already set to the wanted state of $HumanReadableState$ExpirationMessage" -sev Info
        } else {
            $AlertMessage = "File Requests are not set to the wanted state of $HumanReadableState"
            if ($ExpirationDays -ne $null -and $WantedState -eq $true) {
                $AlertMessage += " with $ExpirationDays day expiration"
            }
            Write-StandardsAlert -message $AlertMessage -object $CurrentState -tenant $tenant -standardName 'SPFileRequests' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SPFileRequestsEnabled' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'SPCoreFileRequestsEnabled' -FieldValue $CurrentState.CoreRequestFilesLinkEnabled -StoreAs bool -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'SPOneDriveFileRequestsEnabled' -FieldValue $CurrentState.OneDriveRequestFilesLinkEnabled -StoreAs bool -Tenant $Tenant

        if ($ExpirationDays -ne $null) {
            Add-CIPPBPAField -FieldName 'SPCoreFileRequestsExpirationDays' -FieldValue $CurrentState.CoreRequestFilesLinkExpirationInDays -StoreAs string -Tenant $Tenant
            Add-CIPPBPAField -FieldName 'SPOneDriveFileRequestsExpirationDays' -FieldValue $CurrentState.OneDriveRequestFilesLinkExpirationInDays -StoreAs string -Tenant $Tenant
        }

        if ($AllSettingsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPFileRequests' -FieldValue $FieldValue -Tenant $Tenant
    }
}
