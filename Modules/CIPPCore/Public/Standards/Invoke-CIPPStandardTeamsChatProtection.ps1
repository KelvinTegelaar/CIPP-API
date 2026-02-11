function Invoke-CIPPStandardTeamsChatProtection {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsChatProtection
    .SYNOPSIS
        (Label) Set Teams Chat Protection Settings
    .DESCRIPTION
        (Helptext) Configures Teams chat protection settings including weaponizable file protection and malicious URL protection.
        (DocsDescription) Configures Teams messaging safety features to protect users from weaponizable files and malicious URLs in chats and channels. Weaponizable File Protection automatically blocks messages containing potentially dangerous file types (like .exe, .dll, .bat, etc.). Malicious URL Protection scans URLs in messages and displays warnings when potentially harmful links are detected. These protections work across internal and external collaboration scenarios.
    .NOTES
        CAT
            Teams Standards
        TAG
        EXECUTIVETEXT
            Enables automated security protections in Microsoft Teams to block dangerous files and warn users about malicious links in chat messages. This helps protect employees from file-based attacks and phishing attempts. These safeguards work seamlessly in the background, providing essential protection without disrupting normal business communication.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsChatProtection.FileTypeCheck","label":"Enable Weaponizable File Protection","defaultValue":true}
            {"type":"switch","name":"standards.TeamsChatProtection.UrlReputationCheck","label":"Enable Malicious URL Protection","defaultValue":true}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-10-02
        POWERSHELLEQUIVALENT
            Set-CsTeamsMessagingConfiguration -FileTypeCheck 'Enabled' -UrlReputationCheck 'Enabled' -ReportIncorrectSecurityDetections 'Enabled'
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsChatProtection' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMessagingConfiguration' | Select-Object -Property Identity, FileTypeCheck, UrlReputationCheck
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the Teams Chat Protection state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Set defaults to enabled if not specified
    $Settings.FileTypeCheck ??= $true
    $Settings.UrlReputationCheck ??= $true

    # Convert boolean to Enabled/Disabled string
    $FileTypeCheckState = $Settings.FileTypeCheck ? 'Enabled' : 'Disabled'
    $UrlReputationCheckState = $Settings.UrlReputationCheck ? 'Enabled' : 'Disabled'

    $StateIsCorrect = ($CurrentState.FileTypeCheck -eq $FileTypeCheckState) -and
    ($CurrentState.UrlReputationCheck -eq $UrlReputationCheckState)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Chat Protection settings already correctly configured.' -sev Info
        } else {
            $cmdParams = @{
                Identity           = 'Global'
                FileTypeCheck      = $FileTypeCheckState
                UrlReputationCheck = $UrlReputationCheckState
            }

            try {
                $null = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMessagingConfiguration' -CmdParams $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully updated Teams Chat Protection settings to FileTypeCheck: $FileTypeCheckState, UrlReputationCheck: $UrlReputationCheckState" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure Teams Chat Protection settings. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Chat Protection settings are configured correctly.' -sev Info
        } else {
            Write-StandardsAlert -message 'Teams Chat Protection settings are not configured correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsChatProtection' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Chat Protection settings are not configured correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsChatProtection' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

        $CurrentValue = @{
            FileTypeCheck      = $CurrentState.FileTypeCheck
            UrlReputationCheck = $CurrentState.UrlReputationCheck
        }
        $ExpectedValue = @{
            FileTypeCheck      = $FileTypeCheckState
            UrlReputationCheck = $UrlReputationCheckState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsChatProtection' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
