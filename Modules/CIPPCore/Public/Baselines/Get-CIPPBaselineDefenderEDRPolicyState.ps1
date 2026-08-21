function Get-CIPPBaselineDefenderEDRPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for DefenderEDRPolicy: the 'EDR Configuration' settings catalog policy.
    .DESCRIPTION
        Two settings grade, exactly as the classic read them: sample sharing (enabled = _1
        suffix) and the configuration type, which is correct only when it is
        auto-from-connector.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')) {
        return @{ Current = $null }
    }
    $Policy = @($Policies | Where-Object { "$($_.name)" -eq 'EDR Configuration' }) | Select-Object -First 1

    $CurrentConfig = $false
    $CurrentSampleSharing = $false
    foreach ($Setting in @($Policy.settings)) {
        $Instance = $Setting.settingInstance
        switch ("$($Instance.settingDefinitionId)") {
            'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing' {
                $CurrentSampleSharing = "$($Instance.choiceSettingValue.value)" -like '*_1'
            }
            'device_vendor_msft_windowsadvancedthreatprotection_configurationtype' {
                $CurrentConfig = "$($Instance.choiceSettingValue.value)" -like '*_autofromconnector'
            }
        }
    }

    $Current = [PSCustomObject]@{
        policyExists  = ($null -ne $Policy)
        config        = [bool]$CurrentConfig
        sampleSharing = [bool]$CurrentSampleSharing
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'policyId' -NotePropertyValue "$($Policy.id)"

    @{
        Expected = [PSCustomObject]@{
            policyExists  = $true
            config        = [bool]$Item.Variables.Config
            sampleSharing = [bool]$Item.Variables.SampleSharing
        }
        Current  = $Current
    }
}
