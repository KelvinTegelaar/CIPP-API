function Invoke-CIPPBaselineConsentPolicySettings {
    <#
    .SYNOPSIS
        ConsentPolicySettings executor: writes the Consent Policy Settings directory setting.
    .DESCRIPTION
        Instantiates the setting from its template (dffd5d46-495d-40a9-8e21-954ff55e198a)
        when the tenant has none, otherwise PATCHes the FULL values array - Graph rejects a
        directory-settings update that omits a value - with every live value resent and the
        two managed values overridden. The object is always read LIVE because a cached id can
        be stale. App-only, like the other directory-setting executors: the delegated
        identity's GDAP roles rarely carry the right this object demands.
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
        BlockUserConsentForRiskyApps = & $AsFlag $Remediate.blockUserConsentForRiskyApps
        EnableAdminConsentRequests   = & $AsFlag $Remediate.enableAdminConsentRequests
    }
    $TemplateId = 'dffd5d46-495d-40a9-8e21-954ff55e198a'

    $Live = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/settings' -tenantid $TenantFilter) | Where-Object { "$($_.templateId)" -eq $TemplateId } | Select-Object -First 1
    $SettingId = "$($Live.id)"
    if ([string]::IsNullOrWhiteSpace($SettingId)) {
        $Template = try {
            (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directorySettingTemplates/$TemplateId" -tenantid $TenantFilter).values
        } catch {
            '[{"name":"BlockUserConsentForRiskyApps","defaultValue":"true"},{"name":"EnableAdminConsentRequests","defaultValue":"false"}]' | ConvertFrom-Json
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
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied consent policy settings: block risky app consent $($Desired.BlockUserConsentForRiskyApps), admin consent requests $($Desired.EnableAdminConsentRequests)." -Sev 'Info'
}
