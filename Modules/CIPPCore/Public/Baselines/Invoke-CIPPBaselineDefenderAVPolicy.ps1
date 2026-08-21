function Invoke-CIPPBaselineDefenderAVPolicy {
    <#
    .SYNOPSIS
        DefenderAVPolicy executor: recreates the 'Default AV Policy' settings catalog policy.
    .DESCRIPTION
        The classic's write: a drifted policy is DELETED and recreated through the
        Set-CIPPDefenderAVPolicy helper - settings catalog policies are replaced whole, not
        patched. The helper owns the settingInstance tree and the assignment.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not [string]::IsNullOrWhiteSpace("$($Current.policyId)")) {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Current.policyId)')" -tenantid $TenantFilter -type DELETE
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Deleted the drifted Defender AV policy for recreation.' -Sev 'Info'
    }

    $Pick = { param($Value, $Default) [string]($Value.value ?? $Value ?? $Default) }
    $PolicySettings = @{
        ScanArchives             = [bool]$Remediate.scanArchives
        AllowBehavior            = [bool]$Remediate.allowBehavior
        AllowCloudProtection     = [bool]$Remediate.allowCloudProtection
        AllowEmailScanning       = [bool]$Remediate.allowEmailScanning
        AllowFullScanNetwork     = [bool]$Remediate.allowFullScanNetwork
        AllowFullScanRemovable   = [bool]$Remediate.allowFullScanRemovable
        AllowScriptScan          = [bool]$Remediate.allowScriptScan
        AllowDownloadable        = [bool]$Remediate.allowDownloadable
        AllowRealTime            = [bool]$Remediate.allowRealTime
        AllowNetwork             = [bool]$Remediate.allowNetwork
        AllowUI                  = [bool]$Remediate.allowUI
        CheckSigs                = [bool]$Remediate.checkSigs
        DisableCatchupFullScan   = [bool]$Remediate.disableCatchupFullScan
        DisableCatchupQuickScan  = [bool]$Remediate.disableCatchupQuickScan
        LowCPU                   = [bool]$Remediate.lowCPU
        MeteredConnectionUpdates = [bool]$Remediate.meteredConnectionUpdates
        DisableLocalAdminMerge   = [bool]$Remediate.disableLocalAdminMerge
        AvgCPULoadFactor         = [int]"$($Remediate.avgCPULoadFactor ?? 50)"
        SignatureUpdateInterval  = [int]"$($Remediate.signatureUpdateInterval ?? 8)"
        CloudExtendedTimeout     = [int]"$($Remediate.cloudExtendedTimeout ?? 0)"
        AssignTo                 = (& $Pick $Remediate.assignTo 'none')
    }
    if ($Remediate.allowOnAccessProtection) { $PolicySettings['AllowOnAccessProtection'] = @{ value = (& $Pick $Remediate.allowOnAccessProtection '1') } }
    if ($Remediate.submitSamplesConsent) { $PolicySettings['SubmitSamplesConsent'] = @{ value = (& $Pick $Remediate.submitSamplesConsent '1') } }
    if ($Remediate.enableNetworkProtection) { $PolicySettings['EnableNetworkProtection'] = @{ value = (& $Pick $Remediate.enableNetworkProtection '0') } }
    if ($Remediate.cloudBlockLevel) { $PolicySettings['CloudBlockLevel'] = @{ value = (& $Pick $Remediate.cloudBlockLevel '0') } }

    $RemediationActions = @{}
    if ($Remediate.remediationLow) { $RemediationActions['Low'] = @{ value = (& $Pick $Remediate.remediationLow 'quarantine') } }
    if ($Remediate.remediationModerate) { $RemediationActions['Moderate'] = @{ value = (& $Pick $Remediate.remediationModerate 'quarantine') } }
    if ($Remediate.remediationHigh) { $RemediationActions['High'] = @{ value = (& $Pick $Remediate.remediationHigh 'quarantine') } }
    if ($Remediate.remediationSevere) { $RemediationActions['Severe'] = @{ value = (& $Pick $Remediate.remediationSevere 'quarantine') } }
    if ($RemediationActions.Count -gt 0) { $PolicySettings['Remediation'] = $RemediationActions }

    $Result = Set-CIPPDefenderAVPolicy -TenantFilter $TenantFilter -PolicySettings $PolicySettings -APIName 'Baselines'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$Result" -Sev 'Info'
}
