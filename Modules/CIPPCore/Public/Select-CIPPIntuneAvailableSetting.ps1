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
    .PARAMETER ThrowOnMissingRequired
        Deploy-only guard. Apple enrollment (ADE) policies mark every Setup Assistant option required
        and Graph rejects a create/update when any is absent, with an opaque "A required Setting in
        the template is not present in the policy" error. Microsoft keeps adding new required options
        (e.g. accessibility appearance, Liquid Glass), so a template captured before they existed can
        never deploy. When set, this throws an actionable error naming the missing settings instead.
        Scoped to the enrollment family only - Endpoint Security and generic Catalog policies deploy
        fine with a subset, so they are never validated. The comparison and drift paths never set it.
    .EXAMPLE
        $Template = Select-CIPPIntuneAvailableSetting -Policy $Template -TenantFilter $TenantFilter
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [switch]$ThrowOnMissingRequired
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

    if ($ThrowOnMissingRequired) {
        # Only the enrollment family (Apple ADE) marks every setting required and refuses a create
        # when one is missing. Endpoint Security and generic Catalog policies deploy fine as a subset,
        # so validating them here would block working deployments. Both the family and the technology
        # are read straight off the captured policy, so no extra Graph call is needed.
        $TemplateFamily = $Policy.templateReference.templateFamily
        if ($TemplateFamily -like 'enrollment*' -or $Policy.technologies -match 'enrollment') {
            $PresentIds = @($Policy.settings.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId | Where-Object { $_ })
            $MissingTemplates = @($AvailableSettings | Where-Object {
                    $_.settingInstanceTemplate.isRequired -eq $true -and
                    $_.settingInstanceTemplate.settingInstanceTemplateId -notin $PresentIds
                })
            if ($MissingTemplates.Count -gt 0) {
                $MissingNames = @($MissingTemplates | ForEach-Object {
                        $DefId = $_.settingInstanceTemplate.settingDefinitionId
                        $Friendly = ($_.settingDefinitions | Where-Object { $_.id -eq $DefId } | Select-Object -First 1).displayName
                        if ($Friendly) { $Friendly } else { $DefId }
                    })
                throw "This enrollment policy template is missing $($MissingTemplates.Count) setting(s) that Microsoft now requires: $($MissingNames -join ', '). Microsoft periodically adds new required Setup Assistant options to Apple enrollment policies, and a template captured before they existed can no longer be deployed. Re-create this template from a tenant where the policy is fully configured (open and save it in Intune so the new options are added), then deploy again."
            }
        }
    }

    $Policy.settings = $FilteredSettings
    return $Policy
}
