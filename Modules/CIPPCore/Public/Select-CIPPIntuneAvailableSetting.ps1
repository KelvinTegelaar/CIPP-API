function Select-CIPPIntuneAvailableSetting {
    <#
    .SYNOPSIS
        Reduces a Catalog policy to the settings the tenant actually offers, the way deployment does.
    .DESCRIPTION
        Endpoint Security policies - Catalog policies carrying a templateReference - expose a
        different set of settings per tenant depending on licensing and which features are enabled.
        Set-CIPPIntunePolicy drops the settings a tenant does not offer before sending the policy,
        so the deployed policy is a subset of the template.

        Comparing the full template against that subset reports the dropped settings as drift on
        exactly the tenants that cannot hold them, and remediation can never resolve it. Both the
        deploy path and the comparison paths call this so they are looking at the same policy.

        Policies without a templateReference are returned untouched. Setting template lookups are
        cached briefly per tenant and template, because a drift run resolves the same Endpoint
        Security templates repeatedly.
    .PARAMETER Policy
        The parsed Catalog policy payload.
    .PARAMETER TenantFilter
        The tenant to resolve setting availability against.
    .EXAMPLE
        $Template = Select-CIPPIntuneAvailableSetting -Policy $Template -TenantFilter $TenantFilter
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $TemplateId = $Policy.templateReference.templateId
    if (-not $TemplateId) {
        return $Policy
    }

    if (-not $script:CIPPIntuneSettingTemplateCache) {
        $script:CIPPIntuneSettingTemplateCache = @{}
    }

    $CacheKey = '{0}|{1}' -f $TenantFilter, $TemplateId
    $Cached = $script:CIPPIntuneSettingTemplateCache[$CacheKey]

    if ($Cached -and $Cached.Expires -gt [datetime]::UtcNow) {
        $AvailableSettings = $Cached.Settings
    } else {
        Write-Information "Checking configuration policy template $TemplateId for $($Policy.name)"
        $AvailableSettings = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates('$TemplateId')/settingTemplates?`$expand=settingDefinitions&`$top=1000" -tenantid $TenantFilter
        $script:CIPPIntuneSettingTemplateCache[$CacheKey] = @{
            Settings = $AvailableSettings
            Expires  = [datetime]::UtcNow.AddMinutes(30)
        }
    }

    # An empty result means the lookup told us nothing useful. Filtering on it would strip every
    # setting, so leave the policy alone.
    if (-not $AvailableSettings) {
        return $Policy
    }

    Write-Information "Available settings for template $TemplateId : $(@($AvailableSettings).Count)"
    $FilteredSettings = [System.Collections.Generic.List[psobject]]::new()

    foreach ($setting in $Policy.settings) {
        if ($setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId -in $AvailableSettings.settingInstanceTemplate.settingInstanceTemplateId) {
            $AvailableSetting = $AvailableSettings | Where-Object { $_.settingInstanceTemplate.settingInstanceTemplateId -eq $setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId }

            if ($AvailableSetting.settingInstanceTemplate.settingInstanceTemplateId -cnotmatch $setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId) {
                # update casing
                Write-Information "Fixing casing for setting instance template $($AvailableSetting.settingInstanceTemplate.settingInstanceTemplateId)"
                $setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId = $AvailableSetting.settingInstanceTemplate.settingInstanceTemplateId
            }

            if ($AvailableSetting.settingInstanceTemplate.choiceSettingValueTemplate -cnotmatch $setting.settingInstance.choiceSettingValue.settingValueTemplateReference.settingValueTemplateId) {
                # update choice setting value template
                Write-Information "Fixing casing for choice setting value template $($AvailableSetting.settingInstanceTemplate.choiceSettingValueTemplate.settingValueTemplateId)"
                $setting.settingInstance.choiceSettingValue.settingValueTemplateReference.settingValueTemplateId = $AvailableSetting.settingInstanceTemplate.choiceSettingValueTemplate.settingValueTemplateId
            }

            $FilteredSettings.Add($setting)
        }
    }

    $Policy.settings = $FilteredSettings
    return $Policy
}
