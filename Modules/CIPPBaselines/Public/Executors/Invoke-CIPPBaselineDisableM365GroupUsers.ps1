function Invoke-CIPPBaselineDisableM365GroupUsers {
    <#
    .SYNOPSIS
        DisableM365GroupUsers executor: turns off user-driven M365 group creation, with an
        optional exempt group.
    .DESCRIPTION
        The classic's three-step write: create the exempt group when requested and missing
        (through New-CIPPGroup), instantiate the Group.Unified directory setting from its
        template when the tenant has none (live template fetch with the classic's offline
        fallback), then PATCH EnableGroupCreation false plus - when an exempt group is
        configured and resolved - GroupCreationAllowedGroupId.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $AllowedGroupName = "$($Remediate.allowedGroupName)"
    $GroupId = "$($Current.resolvedGroupId)"

    if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName) -and [string]::IsNullOrWhiteSpace($GroupId) -and ($Remediate.createGroup -eq $true -or "$($Remediate.createGroup)" -eq 'True')) {
        $Username = ($AllowedGroupName -replace '[^a-zA-Z0-9]', '')
        if ($Username.Length -gt 64) { $Username = $Username.Substring(0, 64) }
        $Result = New-CIPPGroup -GroupObject ([PSCustomObject]@{
                groupType = 'generic'; displayName = $AllowedGroupName; username = $Username; securityEnabled = $true
            }) -TenantFilter $TenantFilter -APIName 'Baselines'
        $GroupId = "$($Result.GroupId)"
    }
    if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName) -and [string]::IsNullOrWhiteSpace($GroupId)) {
        throw "The allowed group '$AllowedGroupName' does not exist and group creation was not enabled - refusing to disable group creation without the exemption."
    }

    # Always read the object LIVE: a cached id can be mid-rewrite stale (concurrent
    # one-offs share the Settings cache), and the update must resend EVERY template value -
    # Graph rejects a partial values array - so the other thirteen Group.Unified values
    # come from the live object.
    $Live = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/settings' -tenantid $TenantFilter) | Where-Object { "$($_.displayName)" -eq 'Group.Unified' } | Select-Object -First 1
    $SettingId = "$($Live.id)"
    if ([string]::IsNullOrWhiteSpace($SettingId)) {
        # No Group.Unified setting object yet: instantiate it from the template with defaults.
        $Template = try {
            (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directorySettingTemplates/62375ab9-6b52-47ed-826b-58e47e0e304b' -tenantid $TenantFilter).values
        } catch {
            '[{"name":"NewUnifiedGroupWritebackDefault","defaultValue":"true"},{"name":"EnableMIPLabels","defaultValue":"false"},{"name":"CustomBlockedWordsList","defaultValue":""},{"name":"EnableMSStandardBlockedWords","defaultValue":"false"},{"name":"ClassificationDescriptions","defaultValue":""},{"name":"DefaultClassification","defaultValue":""},{"name":"PrefixSuffixNamingRequirement","defaultValue":""},{"name":"AllowGuestsToBeGroupOwner","defaultValue":"false"},{"name":"AllowGuestsToAccessGroups","defaultValue":"true"},{"name":"GuestUsageGuidelinesUrl","defaultValue":""},{"name":"GroupCreationAllowedGroupId","defaultValue":""},{"name":"AllowToAddGuests","defaultValue":"true"},{"name":"UsageGuidelinesUrl","defaultValue":""},{"name":"ClassificationList","defaultValue":""},{"name":"EnableGroupCreation","defaultValue":"true"}]' | ConvertFrom-Json
        }
        $Values = @($Template | ForEach-Object { @{ name = "$($_.name)"; value = "$($_.defaultValue)" } })
        $Body = @{ templateId = '62375ab9-6b52-47ed-826b-58e47e0e304b'; values = $Values } | ConvertTo-Json -Depth 10 -Compress
        # App-only, like the classic: the delegated identity's GDAP roles rarely include the
        # Groups Administrator right this object demands, and app Directory.ReadWrite.All does.
        $Created = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/settings' -type POST -body $Body -AsApp $true
        $SettingId = "$($Created.id)"
        $Live = $Created
    }

    # Full values array: every live value resent, ours overridden.
    $PatchValues = @(@($Live.values) | ForEach-Object {
            $Name = "$($_.name)"
            $Value = "$($_.value)"
            if ($Name -eq 'EnableGroupCreation') { $Value = 'false' }
            if ($Name -eq 'GroupCreationAllowedGroupId' -and -not [string]::IsNullOrWhiteSpace($GroupId)) { $Value = $GroupId }
            @{ name = $Name; value = $Value }
        })
    $Body = @{ values = $PatchValues } | ConvertTo-Json -Depth 10 -Compress
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/settings/$SettingId" -type PATCH -body $Body -AsApp $true
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Disabled user M365 group creation$(if ($GroupId) { " (exempt group $AllowedGroupName)" })." -Sev 'Info'
}
