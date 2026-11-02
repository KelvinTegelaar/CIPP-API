function Invoke-CIPPBaselineM365GroupGuestSettings {
    <#
    .SYNOPSIS
        M365GroupGuestSettings executor: writes the guest values on the Group.Unified
        directory setting.
    .DESCRIPTION
        Instantiates Group.Unified from its template (live fetch with the same offline
        fallback DisableM365GroupUsers carries) when the tenant has none, then PATCHes the
        FULL values array - Graph rejects a partial values array - with every live value
        resent and only the two guest values overridden, so group creation and naming
        settings owned by other standards are untouched. The object is always read LIVE
        because a cached id can be stale. App-only, like DisableM365GroupUsers: this object
        demands the Groups Administrator right the delegated identity rarely holds.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $AsFlag = { param($Value) if ($Value -eq $true -or "$Value" -eq 'True') { 'true' } else { 'false' } }
    $Desired = @{
        AllowGuestsToBeGroupOwner = & $AsFlag $Remediate.allowGuestsToBeGroupOwner
        AllowGuestsToAccessGroups = & $AsFlag $Remediate.allowGuestsToAccessGroups
    }
    $TemplateId = '62375ab9-6b52-47ed-826b-58e47e0e304b'

    $Live = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/settings' -tenantid $TenantFilter) | Where-Object { "$($_.displayName)" -eq 'Group.Unified' } | Select-Object -First 1
    $SettingId = "$($Live.id)"
    if ([string]::IsNullOrWhiteSpace($SettingId)) {
        $Template = try {
            (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directorySettingTemplates/$TemplateId" -tenantid $TenantFilter).values
        } catch {
            '[{"name":"NewUnifiedGroupWritebackDefault","defaultValue":"true"},{"name":"EnableMIPLabels","defaultValue":"false"},{"name":"CustomBlockedWordsList","defaultValue":""},{"name":"EnableMSStandardBlockedWords","defaultValue":"false"},{"name":"ClassificationDescriptions","defaultValue":""},{"name":"DefaultClassification","defaultValue":""},{"name":"PrefixSuffixNamingRequirement","defaultValue":""},{"name":"AllowGuestsToBeGroupOwner","defaultValue":"false"},{"name":"AllowGuestsToAccessGroups","defaultValue":"true"},{"name":"GuestUsageGuidelinesUrl","defaultValue":""},{"name":"GroupCreationAllowedGroupId","defaultValue":""},{"name":"AllowToAddGuests","defaultValue":"true"},{"name":"UsageGuidelinesUrl","defaultValue":""},{"name":"ClassificationList","defaultValue":""},{"name":"EnableGroupCreation","defaultValue":"true"}]' | ConvertFrom-Json
        }
        $Values = @($Template | ForEach-Object { @{ name = "$($_.name)"; value = "$($_.defaultValue)" } })
        $Body = @{ templateId = $TemplateId; values = $Values } | ConvertTo-Json -Depth 10 -Compress
        $Created = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/settings' -type POST -body $Body -AsApp $true
        $SettingId = "$($Created.id)"
        $Live = $Created
    }

    $PatchValues = @(@($Live.values) | ForEach-Object {
            $Name = "$($_.name)"
            $Value = "$($_.value)"
            if ($Desired.ContainsKey($Name)) { $Value = $Desired[$Name] }
            @{ name = $Name; value = $Value }
        })
    $Body = @{ values = $PatchValues } | ConvertTo-Json -Depth 10 -Compress
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/settings/$SettingId" -type PATCH -body $Body -AsApp $true
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied M365 group guest settings: guests as owners $($Desired.AllowGuestsToBeGroupOwner), guest access to groups $($Desired.AllowGuestsToAccessGroups)." -Sev 'Info'
}
