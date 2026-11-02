function Invoke-CIPPStandardTeamsFilesPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsFilesPolicy
    .SYNOPSIS
        (Label) Global Files Policy for Microsoft Teams
    .DESCRIPTION
        (Helptext) Sets the properties of the Global Teams files policy, including file sharing in external (federated) chats.
        (DocsDescription) Sets the properties of the Global Teams files policy. File sharing in external chats controls whether users can attach files in 1:1, group and meeting chats with people from other organizations. Native file entry points controls the OneDrive and SharePoint attach options in chats and channels, and SharePoint channel files tab controls the SharePoint Files tab in channels.
    .NOTES
        CAT
            Teams Standards
        TAG
        EXECUTIVETEXT
            Controls whether employees can attach files directly in Microsoft Teams chats with people outside the organization. Microsoft is enabling this by default for all tenants, including those that had turned it off, so managing it as a standard keeps the organization's chosen external sharing posture in place.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.TeamsFilesPolicy.FileSharingInChatsWithExternalUsers","label":"File sharing in external chats","options":[{"label":"Don't change","value":"donotconfigure"},{"label":"Enabled","value":"Enabled"},{"label":"Disabled","value":"Disabled"}],"defaultValue":"Disabled"}
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.TeamsFilesPolicy.NativeFileEntryPoints","label":"OneDrive and SharePoint file entry points","options":[{"label":"Don't change","value":"donotconfigure"},{"label":"Enabled","value":"Enabled"},{"label":"Disabled","value":"Disabled"}],"defaultValue":"donotconfigure"}
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.TeamsFilesPolicy.SPChannelFilesTab","label":"SharePoint channel files tab","options":[{"label":"Don't change","value":"donotconfigure"},{"label":"Enabled","value":"Enabled"},{"label":"Disabled","value":"Disabled"}],"defaultValue":"donotconfigure"}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-09-28
        POWERSHELLEQUIVALENT
            Set-CsTeamsFilesPolicy -Identity Global -FileSharingInChatsWithExternalUsers Disabled
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "MCOSTANDARD"
            "MCOEV"
            "MCOIMP"
            "TEAMS1"
            "Teams_Room_Standard"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsFilesPolicy' -TenantFilter $Tenant -Preset Teams

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsFilesPolicy' -Action Get -Identity 'Global'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the Teams files policy state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Only settings the admin picked are managed; blank or "Don't change" leaves the tenant value alone
    $ExpectedValue = @{}
    foreach ($Name in @('FileSharingInChatsWithExternalUsers', 'NativeFileEntryPoints', 'SPChannelFilesTab')) {
        $Value = $Settings.$Name.value ?? $Settings.$Name
        if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq 'donotconfigure') { continue }
        $ExpectedValue[$Name] = [string]$Value
    }
    $CurrentValue = @{}
    foreach ($Name in $ExpectedValue.Keys) { $CurrentValue[$Name] = $CurrentState.$Name }
    $StateIsCorrect = @($ExpectedValue.Keys | Where-Object { $CurrentValue[$_] -ne $ExpectedValue[$_] }).Count -eq 0

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Teams files policy already configured.' -sev Info
        } else {
            $cmdParams = @{ Identity = 'Global' } + $ExpectedValue

            try {
                $null = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsFilesPolicy' -Action Set -Parameters $cmdParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated global Teams files policy: $(($ExpectedValue.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure global Teams files policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Teams files policy is configured correctly.' -sev Info
        } else {
            Write-StandardsAlert -message 'Global Teams files policy is not configured correctly.' -object $CurrentValue -tenant $Tenant -standardName 'TeamsFilesPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Global Teams files policy is not configured correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsFilesPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
