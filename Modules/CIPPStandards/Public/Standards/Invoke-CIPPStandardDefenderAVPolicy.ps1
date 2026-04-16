function Invoke-CIPPStandardDefenderAVPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefenderAVPolicy
    .SYNOPSIS
        (Label) Defender Antivirus Policy
    .DESCRIPTION
        (Helptext) Deploys and enforces a Microsoft Defender Antivirus configuration policy via Intune. Controls scanning behaviour, real-time protection, cloud protection, network protection, signature updates, CPU priority, and threat remediation actions.
        (DocsDescription) Deploys a standardised Microsoft Defender Antivirus policy through Intune configuration policies. This standard manages all AV settings including archive scanning, behaviour monitoring, cloud protection levels, email scanning, real-time monitoring, script scanning, network protection mode, signature update intervals, CPU load limits, cloud extended timeout, submit samples consent, threat severity remediation actions, and policy assignment scope. The policy is created if it does not exist and settings drift is monitored.
    .NOTES
        CAT
            Defender Standards
        TAG
            "defender_antivirus"
            "defender_av_policy"
            "intune_endpoint_protection"
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.DefenderAVPolicy.ScanArchives","label":"Archive Scanning","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowBehavior","label":"Behavior Monitoring","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowCloudProtection","label":"Cloud Protection","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowEmailScanning","label":"Email Scanning","defaultValue":false}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowFullScanNetwork","label":"Full Scan on Network Drives","defaultValue":false}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowFullScanRemovable","label":"Full Scan on Removable Drives","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowScriptScan","label":"Script Scanning","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowDownloadable","label":"Downloads Scanning (IOAV Protection)","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowRealTime","label":"Real-time Monitoring","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowNetwork","label":"Network Files Scanning","defaultValue":false}
            {"type":"switch","name":"standards.DefenderAVPolicy.AllowUI","label":"User UI Access","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.CheckSigs","label":"Check Signatures Before Scan","defaultValue":false}
            {"type":"switch","name":"standards.DefenderAVPolicy.DisableCatchupFullScan","label":"Disable Catchup Full Scan","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.DisableCatchupQuickScan","label":"Disable Catchup Quick Scan","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.LowCPU","label":"Low CPU Priority","defaultValue":true}
            {"type":"switch","name":"standards.DefenderAVPolicy.MeteredConnectionUpdates","label":"Metered Connection Updates","defaultValue":false}
            {"type":"switch","name":"standards.DefenderAVPolicy.DisableLocalAdminMerge","label":"Disable Local Admin Merge","defaultValue":true}
            {"type":"number","name":"standards.DefenderAVPolicy.AvgCPULoadFactor","label":"Avg CPU Load Factor (%) (0-100)","defaultValue":50}
            {"type":"number","name":"standards.DefenderAVPolicy.SignatureUpdateInterval","label":"Signature Update Interval (hours) (0-24)","defaultValue":8}
            {"type":"number","name":"standards.DefenderAVPolicy.CloudExtendedTimeout","label":"Cloud Extended Timeout (seconds) (0-50)","defaultValue":0}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.AllowOnAccessProtection","label":"Allow On Access Protection","options":[{"label":"Not Allowed","value":"0"},{"label":"Allowed (Default)","value":"1"}]}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.SubmitSamplesConsent","label":"Submit Samples Consent","options":[{"label":"Always prompt","value":"0"},{"label":"Send safe samples automatically (Default)","value":"1"},{"label":"Never send","value":"2"},{"label":"Send all samples automatically","value":"3"}]}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.EnableNetworkProtection","label":"Network Protection","options":[{"label":"Disabled (Default)","value":"0"},{"label":"Block mode","value":"1"},{"label":"Audit mode","value":"2"}]}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.CloudBlockLevel","label":"Cloud Block Level","options":[{"label":"Default","value":"0"},{"label":"High","value":"2"},{"label":"High Plus","value":"4"},{"label":"Zero Tolerance","value":"6"}]}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.RemediationLow","label":"Threat Remediation - Low Severity","options":[{"label":"Clean","value":"clean"},{"label":"Quarantine","value":"quarantine"},{"label":"Remove","value":"remove"},{"label":"Allow","value":"allow"},{"label":"User Defined","value":"userDefined"},{"label":"Block","value":"block"}]}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.RemediationModerate","label":"Threat Remediation - Moderate Severity","options":[{"label":"Clean","value":"clean"},{"label":"Quarantine","value":"quarantine"},{"label":"Remove","value":"remove"},{"label":"Allow","value":"allow"},{"label":"User Defined","value":"userDefined"},{"label":"Block","value":"block"}]}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.RemediationHigh","label":"Threat Remediation - High Severity","options":[{"label":"Clean","value":"clean"},{"label":"Quarantine","value":"quarantine"},{"label":"Remove","value":"remove"},{"label":"Allow","value":"allow"},{"label":"User Defined","value":"userDefined"},{"label":"Block","value":"block"}]}
            {"type":"select","multiple":false,"name":"standards.DefenderAVPolicy.RemediationSevere","label":"Threat Remediation - Severe","options":[{"label":"Clean","value":"clean"},{"label":"Quarantine","value":"quarantine"},{"label":"Remove","value":"remove"},{"label":"Allow","value":"allow"},{"label":"User Defined","value":"userDefined"},{"label":"Block","value":"block"}]}
            {"type":"radio","name":"standards.DefenderAVPolicy.AssignTo","label":"Policy Assignment","options":[{"label":"Do not assign","value":"none"},{"label":"All users","value":"allLicensedUsers"},{"label":"All devices","value":"AllDevices"},{"label":"All users and devices","value":"AllDevicesAndUsers"}]}
        IMPACT
            High Impact
        ADDEDDATE
            2026-04-02
        POWERSHELLEQUIVALENT
            Graph API - deviceManagement/configurationPolicies
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    # The policy name used by the deployment helper
    $PolicyName = 'Default AV Policy'

    # Mapping: settingDefinitionId -> property name for boolean choice settings (enabled = _1 suffix)
    $DP = 'device_vendor_msft_policy_config_defender'
    $DA = 'device_vendor_msft_defender_configuration'
    $BoolDefIdMap = @{
        "${DP}_allowarchivescanning"               = 'ScanArchives'
        "${DP}_allowbehaviormonitoring"             = 'AllowBehavior'
        "${DP}_allowcloudprotection"                = 'AllowCloudProtection'
        "${DP}_allowemailscanning"                  = 'AllowEmailScanning'
        "${DP}_allowfullscanonmappednetworkdrives"  = 'AllowFullScanNetwork'
        "${DP}_allowfullscanremovabledrivescanning" = 'AllowFullScanRemovable'
        "${DP}_allowioavprotection"                 = 'AllowDownloadable'
        "${DP}_allowrealtimemonitoring"             = 'AllowRealTime'
        "${DP}_allowscanningnetworkfiles"           = 'AllowNetwork'
        "${DP}_allowscriptscanning"                 = 'AllowScriptScan'
        "${DP}_allowuseruiaccess"                   = 'AllowUI'
        "${DP}_checkforsignaturesbeforerunningscan" = 'CheckSigs'
        "${DP}_disablecatchupfullscan"              = 'DisableCatchupFullScan'
        "${DP}_disablecatchupquickscan"             = 'DisableCatchupQuickScan'
        "${DP}_enablelowcpupriority"                = 'LowCPU'
        "${DA}_meteredconnectionupdates"            = 'MeteredConnectionUpdates'
        "${DA}_disablelocaladminmerge"              = 'DisableLocalAdminMerge'
    }
    $ChoiceDefIdMap = @{
        "${DP}_enablenetworkprotection" = 'EnableNetworkProtection'
        "${DP}_cloudblocklevel"         = 'CloudBlockLevel'
        "${DP}_allowonaccessprotection" = 'AllowOnAccessProtection'
        "${DP}_submitsamplesconsent"    = 'SubmitSamplesConsent'
    }
    $IntegerDefIdMap = @{
        "${DP}_avgcpuloadfactor"        = 'AvgCPULoadFactor'
        "${DP}_cloudextendedtimeout"    = 'CloudExtendedTimeout'
        "${DP}_signatureupdateinterval" = 'SignatureUpdateInterval'
    }
    $RemediationPrefix = "${DP}_threatseveritydefaultaction"

    # Build expected values from settings
    $ExpectedValue = [PSCustomObject]@{
        PolicyExists         = $true
        ScanArchives         = [bool]$Settings.ScanArchives
        AllowBehavior        = [bool]$Settings.AllowBehavior
        AllowCloudProtection = [bool]$Settings.AllowCloudProtection
        AllowEmailScanning   = [bool]$Settings.AllowEmailScanning
        AllowFullScanNetwork = [bool]$Settings.AllowFullScanNetwork
        AllowFullScanRemovable = [bool]$Settings.AllowFullScanRemovable
        AllowScriptScan      = [bool]$Settings.AllowScriptScan
        AllowDownloadable    = [bool]$Settings.AllowDownloadable
        AllowRealTime        = [bool]$Settings.AllowRealTime
        AllowNetwork         = [bool]$Settings.AllowNetwork
        AllowUI              = [bool]$Settings.AllowUI
        CheckSigs            = [bool]$Settings.CheckSigs
        DisableCatchupFullScan  = [bool]$Settings.DisableCatchupFullScan
        DisableCatchupQuickScan = [bool]$Settings.DisableCatchupQuickScan
        LowCPU               = [bool]$Settings.LowCPU
        MeteredConnectionUpdates = [bool]$Settings.MeteredConnectionUpdates
        DisableLocalAdminMerge = [bool]$Settings.DisableLocalAdminMerge
        EnableNetworkProtection = [string]($Settings.EnableNetworkProtection.value ?? $Settings.EnableNetworkProtection ?? '0')
        CloudBlockLevel      = [string]($Settings.CloudBlockLevel.value ?? $Settings.CloudBlockLevel ?? '0')
        AllowOnAccessProtection = [string]($Settings.AllowOnAccessProtection.value ?? $Settings.AllowOnAccessProtection ?? '1')
        SubmitSamplesConsent = [string]($Settings.SubmitSamplesConsent.value ?? $Settings.SubmitSamplesConsent ?? '1')
        AvgCPULoadFactor     = [int]($Settings.AvgCPULoadFactor ?? 50)
        SignatureUpdateInterval = [int]($Settings.SignatureUpdateInterval ?? 8)
        CloudExtendedTimeout = [int]($Settings.CloudExtendedTimeout ?? 0)
        RemediationLow       = [string]($Settings.RemediationLow.value ?? $Settings.RemediationLow ?? '')
        RemediationModerate  = [string]($Settings.RemediationModerate.value ?? $Settings.RemediationModerate ?? '')
        RemediationHigh      = [string]($Settings.RemediationHigh.value ?? $Settings.RemediationHigh ?? '')
        RemediationSevere    = [string]($Settings.RemediationSevere.value ?? $Settings.RemediationSevere ?? '')
    }

    # Check existing policies
    try {
        $ExistingPolicies = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve configuration policies: $ErrorMessage" -sev Error
        return
    }

    $ExistingPolicy = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName } | Select-Object -First 1
    $PolicyExists = $null -ne $ExistingPolicy

    # Parse current settings from the policy if it exists
    $CurrentParsed = @{}
    if ($PolicyExists) {
        try {
            $PolicyDetail = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')?`$expand=settings" -tenantid $Tenant
            foreach ($setting in $PolicyDetail.settings) {
                $instance = $setting.settingInstance
                $defId = $instance.settingDefinitionId

                if ($BoolDefIdMap.ContainsKey($defId)) {
                    $CurrentParsed[$BoolDefIdMap[$defId]] = $instance.choiceSettingValue.value -like '*_1'
                } elseif ($ChoiceDefIdMap.ContainsKey($defId)) {
                    $CurrentParsed[$ChoiceDefIdMap[$defId]] = [string](($instance.choiceSettingValue.value -split '_')[-1])
                } elseif ($IntegerDefIdMap.ContainsKey($defId)) {
                    $CurrentParsed[$IntegerDefIdMap[$defId]] = [int]$instance.simpleSettingValue.value
                } elseif ($defId -eq $RemediationPrefix) {
                    foreach ($child in $instance.groupSettingCollectionValue[0].children) {
                        $childSuffix = ($child.choiceSettingValue.value -split '_')[-1]
                        switch -Wildcard ($child.settingDefinitionId) {
                            '*_lowseveritythreats' { $CurrentParsed['RemediationLow'] = $childSuffix }
                            '*_moderateseveritythreats' { $CurrentParsed['RemediationModerate'] = $childSuffix }
                            '*_highseveritythreats' { $CurrentParsed['RemediationHigh'] = $childSuffix }
                            '*_severethreats' { $CurrentParsed['RemediationSevere'] = $childSuffix }
                        }
                    }
                }
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to read AV Policy settings: $($_.Exception.Message)" -sev Warning
        }
    }

    $CurrentValue = [PSCustomObject]@{
        PolicyExists            = $PolicyExists
        ScanArchives            = [bool]($CurrentParsed.ScanArchives)
        AllowBehavior           = [bool]($CurrentParsed.AllowBehavior)
        AllowCloudProtection    = [bool]($CurrentParsed.AllowCloudProtection)
        AllowEmailScanning      = [bool]($CurrentParsed.AllowEmailScanning)
        AllowFullScanNetwork    = [bool]($CurrentParsed.AllowFullScanNetwork)
        AllowFullScanRemovable  = [bool]($CurrentParsed.AllowFullScanRemovable)
        AllowScriptScan         = [bool]($CurrentParsed.AllowScriptScan)
        AllowDownloadable       = [bool]($CurrentParsed.AllowDownloadable)
        AllowRealTime           = [bool]($CurrentParsed.AllowRealTime)
        AllowNetwork            = [bool]($CurrentParsed.AllowNetwork)
        AllowUI                 = [bool]($CurrentParsed.AllowUI)
        CheckSigs               = [bool]($CurrentParsed.CheckSigs)
        DisableCatchupFullScan  = [bool]($CurrentParsed.DisableCatchupFullScan)
        DisableCatchupQuickScan = [bool]($CurrentParsed.DisableCatchupQuickScan)
        LowCPU                  = [bool]($CurrentParsed.LowCPU)
        MeteredConnectionUpdates = [bool]($CurrentParsed.MeteredConnectionUpdates)
        DisableLocalAdminMerge  = [bool]($CurrentParsed.DisableLocalAdminMerge)
        EnableNetworkProtection = [string]($CurrentParsed.EnableNetworkProtection ?? '')
        CloudBlockLevel         = [string]($CurrentParsed.CloudBlockLevel ?? '')
        AllowOnAccessProtection = [string]($CurrentParsed.AllowOnAccessProtection ?? '')
        SubmitSamplesConsent    = [string]($CurrentParsed.SubmitSamplesConsent ?? '')
        AvgCPULoadFactor        = [int]($CurrentParsed.AvgCPULoadFactor ?? 0)
        SignatureUpdateInterval = [int]($CurrentParsed.SignatureUpdateInterval ?? 0)
        CloudExtendedTimeout    = [int]($CurrentParsed.CloudExtendedTimeout ?? 0)
        RemediationLow          = [string]($CurrentParsed.RemediationLow ?? '')
        RemediationModerate     = [string]($CurrentParsed.RemediationModerate ?? '')
        RemediationHigh         = [string]($CurrentParsed.RemediationHigh ?? '')
        RemediationSevere       = [string]($CurrentParsed.RemediationSevere ?? '')
    }

    # Field-by-field comparison
    $StateIsCorrect = $PolicyExists
    if ($PolicyExists) {
        $PropertiesToCompare = @('ScanArchives', 'AllowBehavior', 'AllowCloudProtection', 'AllowEmailScanning',
            'AllowFullScanNetwork', 'AllowFullScanRemovable', 'AllowScriptScan', 'AllowDownloadable',
            'AllowRealTime', 'AllowNetwork', 'AllowUI', 'CheckSigs', 'DisableCatchupFullScan',
            'DisableCatchupQuickScan', 'LowCPU', 'MeteredConnectionUpdates', 'DisableLocalAdminMerge',
            'EnableNetworkProtection', 'CloudBlockLevel', 'AllowOnAccessProtection', 'SubmitSamplesConsent',
            'AvgCPULoadFactor', 'SignatureUpdateInterval', 'CloudExtendedTimeout')

        foreach ($prop in $PropertiesToCompare) {
            if ($CurrentValue.$prop -ne $ExpectedValue.$prop) {
                $StateIsCorrect = $false
                break
            }
        }

        # Compare remediation if user specified values
        if ($StateIsCorrect -and $ExpectedValue.RemediationLow) {
            if ($CurrentValue.RemediationLow -ne $ExpectedValue.RemediationLow) { $StateIsCorrect = $false }
        }
        if ($StateIsCorrect -and $ExpectedValue.RemediationModerate) {
            if ($CurrentValue.RemediationModerate -ne $ExpectedValue.RemediationModerate) { $StateIsCorrect = $false }
        }
        if ($StateIsCorrect -and $ExpectedValue.RemediationHigh) {
            if ($CurrentValue.RemediationHigh -ne $ExpectedValue.RemediationHigh) { $StateIsCorrect = $false }
        }
        if ($StateIsCorrect -and $ExpectedValue.RemediationSevere) {
            if ($CurrentValue.RemediationSevere -ne $ExpectedValue.RemediationSevere) { $StateIsCorrect = $false }
        }
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender AV Policy already correctly configured' -sev Info
        } else {
            try {
                # If policy exists with wrong settings, delete it first so the helper can recreate
                if ($PolicyExists) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')" -tenantid $Tenant -type DELETE
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Deleted drifted Defender AV Policy for recreation' -sev Info
                }

                # Build the PolicySettings object expected by Set-CIPPDefenderAVPolicy
                $PolicySettings = @{
                    ScanArchives             = [bool]$Settings.ScanArchives
                    AllowBehavior            = [bool]$Settings.AllowBehavior
                    AllowCloudProtection     = [bool]$Settings.AllowCloudProtection
                    AllowEmailScanning       = [bool]$Settings.AllowEmailScanning
                    AllowFullScanNetwork     = [bool]$Settings.AllowFullScanNetwork
                    AllowFullScanRemovable   = [bool]$Settings.AllowFullScanRemovable
                    AllowScriptScan          = [bool]$Settings.AllowScriptScan
                    AllowDownloadable        = [bool]$Settings.AllowDownloadable
                    AllowRealTime            = [bool]$Settings.AllowRealTime
                    AllowNetwork             = [bool]$Settings.AllowNetwork
                    AllowUI                  = [bool]$Settings.AllowUI
                    CheckSigs                = [bool]$Settings.CheckSigs
                    DisableCatchupFullScan   = [bool]$Settings.DisableCatchupFullScan
                    DisableCatchupQuickScan  = [bool]$Settings.DisableCatchupQuickScan
                    LowCPU                   = [bool]$Settings.LowCPU
                    MeteredConnectionUpdates = [bool]$Settings.MeteredConnectionUpdates
                    DisableLocalAdminMerge   = [bool]$Settings.DisableLocalAdminMerge
                    AvgCPULoadFactor         = [int]($Settings.AvgCPULoadFactor ?? 50)
                    SignatureUpdateInterval  = [int]($Settings.SignatureUpdateInterval ?? 8)
                    CloudExtendedTimeout     = [int]($Settings.CloudExtendedTimeout ?? 0)
                    AssignTo                 = $Settings.AssignTo ?? 'none'
                }

                if ($Settings.AllowOnAccessProtection) {
                    $PolicySettings['AllowOnAccessProtection'] = @{ value = ($Settings.AllowOnAccessProtection.value ?? $Settings.AllowOnAccessProtection ?? '1') }
                }
                if ($Settings.SubmitSamplesConsent) {
                    $PolicySettings['SubmitSamplesConsent'] = @{ value = ($Settings.SubmitSamplesConsent.value ?? $Settings.SubmitSamplesConsent ?? '1') }
                }
                if ($Settings.EnableNetworkProtection) {
                    $PolicySettings['EnableNetworkProtection'] = @{ value = ($Settings.EnableNetworkProtection.value ?? $Settings.EnableNetworkProtection ?? '0') }
                }
                if ($Settings.CloudBlockLevel) {
                    $PolicySettings['CloudBlockLevel'] = @{ value = ($Settings.CloudBlockLevel.value ?? $Settings.CloudBlockLevel ?? '0') }
                }

                $Remediation = @{}
                if ($Settings.RemediationLow) { $Remediation['Low'] = @{ value = ($Settings.RemediationLow.value ?? $Settings.RemediationLow ?? 'quarantine') } }
                if ($Settings.RemediationModerate) { $Remediation['Moderate'] = @{ value = ($Settings.RemediationModerate.value ?? $Settings.RemediationModerate ?? 'quarantine') } }
                if ($Settings.RemediationHigh) { $Remediation['High'] = @{ value = ($Settings.RemediationHigh.value ?? $Settings.RemediationHigh ?? 'quarantine') } }
                if ($Settings.RemediationSevere) { $Remediation['Severe'] = @{ value = ($Settings.RemediationSevere.value ?? $Settings.RemediationSevere ?? 'quarantine') } }
                if ($Remediation.Count -gt 0) { $PolicySettings['Remediation'] = $Remediation }

                $Result = Set-CIPPDefenderAVPolicy -TenantFilter $Tenant -PolicySettings $PolicySettings -APIName 'Standards'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Defender AV Policy: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender AV Policy is correctly configured' -sev Info
        } else {
            Write-StandardsAlert -message 'Defender AV Policy is not correctly configured' -object $CurrentValue -tenant $Tenant -standardName 'DefenderAVPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender AV Policy is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DefenderAVPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DefenderAVPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
