function Get-CIPPBaselineDefenderAVPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for DefenderAVPolicy: the 'Default AV Policy' settings catalog policy.
    .DESCRIPTION
        Finds the fixed-name policy in the IntuneConfigurationPolicies cache and parses its
        settingInstance tree back into the classic's property set: boolean choice settings
        (enabled = _1 suffix), choice suffixes as strings, integers, and the threat severity
        remediation group. The four remediation actions grade only when the baseline
        configures them - the classic compared them conditionally for the same reason.
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
    $Policy = @($Policies | Where-Object { "$($_.name)" -eq 'Default AV Policy' }) | Select-Object -First 1

    $DP = 'device_vendor_msft_policy_config_defender'
    $DA = 'device_vendor_msft_defender_configuration'
    $BoolDefIdMap = @{
        "${DP}_allowarchivescanning"                = 'scanArchives'
        "${DP}_allowbehaviormonitoring"             = 'allowBehavior'
        "${DP}_allowcloudprotection"                = 'allowCloudProtection'
        "${DP}_allowemailscanning"                  = 'allowEmailScanning'
        "${DP}_allowfullscanonmappednetworkdrives"  = 'allowFullScanNetwork'
        "${DP}_allowfullscanremovabledrivescanning" = 'allowFullScanRemovable'
        "${DP}_allowioavprotection"                 = 'allowDownloadable'
        "${DP}_allowrealtimemonitoring"             = 'allowRealTime'
        "${DP}_allowscanningnetworkfiles"           = 'allowNetwork'
        "${DP}_allowscriptscanning"                 = 'allowScriptScan'
        "${DP}_allowuseruiaccess"                   = 'allowUI'
        "${DP}_checkforsignaturesbeforerunningscan" = 'checkSigs'
        "${DP}_disablecatchupfullscan"              = 'disableCatchupFullScan'
        "${DP}_disablecatchupquickscan"             = 'disableCatchupQuickScan'
        "${DP}_enablelowcpupriority"                = 'lowCPU'
        "${DA}_meteredconnectionupdates"            = 'meteredConnectionUpdates'
        "${DA}_disablelocaladminmerge"              = 'disableLocalAdminMerge'
    }
    $ChoiceDefIdMap = @{
        "${DP}_enablenetworkprotection" = 'enableNetworkProtection'
        "${DP}_cloudblocklevel"         = 'cloudBlockLevel'
        "${DP}_allowonaccessprotection" = 'allowOnAccessProtection'
        "${DP}_submitsamplesconsent"    = 'submitSamplesConsent'
    }
    $IntegerDefIdMap = @{
        "${DP}_avgcpuloadfactor"        = 'avgCPULoadFactor'
        "${DP}_cloudextendedtimeout"    = 'cloudExtendedTimeout'
        "${DP}_signatureupdateinterval" = 'signatureUpdateInterval'
    }
    $RemediationDefId = "${DP}_threatseveritydefaultaction"

    $Parsed = @{}
    foreach ($Setting in @($Policy.settings)) {
        $Instance = $Setting.settingInstance
        $DefId = "$($Instance.settingDefinitionId)"
        if ($BoolDefIdMap.ContainsKey($DefId)) {
            $Parsed[$BoolDefIdMap[$DefId]] = "$($Instance.choiceSettingValue.value)" -like '*_1'
        } elseif ($ChoiceDefIdMap.ContainsKey($DefId)) {
            $Parsed[$ChoiceDefIdMap[$DefId]] = [string]("$($Instance.choiceSettingValue.value)" -split '_')[-1]
        } elseif ($IntegerDefIdMap.ContainsKey($DefId)) {
            $Parsed[$IntegerDefIdMap[$DefId]] = [int]"$($Instance.simpleSettingValue.value)"
        } elseif ($DefId -eq $RemediationDefId) {
            foreach ($Child in @(@($Instance.groupSettingCollectionValue)[0].children)) {
                $Suffix = ("$($Child.choiceSettingValue.value)" -split '_')[-1]
                switch -Wildcard ("$($Child.settingDefinitionId)") {
                    '*_lowseveritythreats' { $Parsed['remediationLow'] = $Suffix }
                    '*_moderateseveritythreats' { $Parsed['remediationModerate'] = $Suffix }
                    '*_highseveritythreats' { $Parsed['remediationHigh'] = $Suffix }
                    '*_severethreats' { $Parsed['remediationSevere'] = $Suffix }
                }
            }
        }
    }

    $V = $Item.Variables
    $Pick = { param($Value, $Default) [string]($Value.value ?? $Value ?? $Default) }
    $Expected = [ordered]@{
        policyExists             = $true
        scanArchives             = [bool]$V.ScanArchives
        allowBehavior            = [bool]$V.AllowBehavior
        allowCloudProtection     = [bool]$V.AllowCloudProtection
        allowEmailScanning       = [bool]$V.AllowEmailScanning
        allowFullScanNetwork     = [bool]$V.AllowFullScanNetwork
        allowFullScanRemovable   = [bool]$V.AllowFullScanRemovable
        allowScriptScan          = [bool]$V.AllowScriptScan
        allowDownloadable        = [bool]$V.AllowDownloadable
        allowRealTime            = [bool]$V.AllowRealTime
        allowNetwork             = [bool]$V.AllowNetwork
        allowUI                  = [bool]$V.AllowUI
        checkSigs                = [bool]$V.CheckSigs
        disableCatchupFullScan   = [bool]$V.DisableCatchupFullScan
        disableCatchupQuickScan  = [bool]$V.DisableCatchupQuickScan
        lowCPU                   = [bool]$V.LowCPU
        meteredConnectionUpdates = [bool]$V.MeteredConnectionUpdates
        disableLocalAdminMerge   = [bool]$V.DisableLocalAdminMerge
        # Blank integers grade the executor's write-side defaults: '' survives ?? so a
        # plain null-coalesce would grade 0 while the recreate writes 50/8, drift no
        # remediation could ever clear.
        avgCPULoadFactor         = $(if ([string]::IsNullOrWhiteSpace("$($V.AvgCPULoadFactor)")) { 50 } else { [int]"$($V.AvgCPULoadFactor)" })
        signatureUpdateInterval  = $(if ([string]::IsNullOrWhiteSpace("$($V.SignatureUpdateInterval)")) { 8 } else { [int]"$($V.SignatureUpdateInterval)" })
        cloudExtendedTimeout     = $(if ([string]::IsNullOrWhiteSpace("$($V.CloudExtendedTimeout)")) { 0 } else { [int]"$($V.CloudExtendedTimeout)" })
    }
    $Current = [ordered]@{
        policyExists             = ($null -ne $Policy)
        scanArchives             = [bool]$Parsed.scanArchives
        allowBehavior            = [bool]$Parsed.allowBehavior
        allowCloudProtection     = [bool]$Parsed.allowCloudProtection
        allowEmailScanning       = [bool]$Parsed.allowEmailScanning
        allowFullScanNetwork     = [bool]$Parsed.allowFullScanNetwork
        allowFullScanRemovable   = [bool]$Parsed.allowFullScanRemovable
        allowScriptScan          = [bool]$Parsed.allowScriptScan
        allowDownloadable        = [bool]$Parsed.allowDownloadable
        allowRealTime            = [bool]$Parsed.allowRealTime
        allowNetwork             = [bool]$Parsed.allowNetwork
        allowUI                  = [bool]$Parsed.allowUI
        checkSigs                = [bool]$Parsed.checkSigs
        disableCatchupFullScan   = [bool]$Parsed.disableCatchupFullScan
        disableCatchupQuickScan  = [bool]$Parsed.disableCatchupQuickScan
        lowCPU                   = [bool]$Parsed.lowCPU
        meteredConnectionUpdates = [bool]$Parsed.meteredConnectionUpdates
        disableLocalAdminMerge   = [bool]$Parsed.disableLocalAdminMerge
        avgCPULoadFactor         = [int]($Parsed.avgCPULoadFactor ?? 0)
        signatureUpdateInterval  = [int]($Parsed.signatureUpdateInterval ?? 0)
        cloudExtendedTimeout     = [int]($Parsed.cloudExtendedTimeout ?? 0)
    }
    # The four choice settings only write when the baseline configures them - the
    # recreate omits blank ones entirely, so grading a default against a policy that
    # legitimately lacks the setting would be drift no write can ever clear.
    foreach ($Pair in @(@('enableNetworkProtection', 'EnableNetworkProtection'), @('cloudBlockLevel', 'CloudBlockLevel'), @('allowOnAccessProtection', 'AllowOnAccessProtection'), @('submitSamplesConsent', 'SubmitSamplesConsent'))) {
        $Configured = & $Pick $V.($Pair[1]) ''
        if (-not [string]::IsNullOrEmpty($Configured)) {
            $Expected[$Pair[0]] = $Configured
            $Current[$Pair[0]] = [string]($Parsed.($Pair[0]) ?? '')
        }
    }
    # The classic compared the four remediation actions only when configured.
    foreach ($Pair in @(@('remediationLow', 'RemediationLow'), @('remediationModerate', 'RemediationModerate'), @('remediationHigh', 'RemediationHigh'), @('remediationSevere', 'RemediationSevere'))) {
        $Configured = & $Pick $V.($Pair[1]) ''
        if (-not [string]::IsNullOrEmpty($Configured)) {
            $Expected[$Pair[0]] = $Configured
            $Current[$Pair[0]] = [string]($Parsed.($Pair[0]) ?? '')
        }
    }

    $CurrentObject = [PSCustomObject]$Current
    # Carried for the executor.
    $CurrentObject | Add-Member -NotePropertyName 'policyId' -NotePropertyValue "$($Policy.id)"

    @{
        Expected = [PSCustomObject]$Expected
        Current  = $CurrentObject
    }
}
