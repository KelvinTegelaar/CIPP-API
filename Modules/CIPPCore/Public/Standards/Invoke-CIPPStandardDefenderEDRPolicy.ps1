function Invoke-CIPPStandardDefenderEDRPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefenderEDRPolicy
    .SYNOPSIS
        (Label) Defender EDR Configuration
    .DESCRIPTION
        (Helptext) Deploys and enforces a Microsoft Defender for Endpoint EDR (Endpoint Detection and Response) configuration policy via Intune. Controls auto-configuration from the MDE connector and sample sharing.
        (DocsDescription) Deploys an EDR configuration policy through Intune that enables Endpoint Detection and Response capabilities from Microsoft Defender for Endpoint. This standard controls whether the EDR configuration is automatically derived from the MDE connector and whether telemetry sample sharing is enabled. The policy ensures consistent EDR onboarding across managed Windows devices.
    .NOTES
        CAT
            Defender Standards
        TAG
            "defender_edr"
            "defender_endpoint_detection"
            "intune_endpoint_protection"
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.DefenderEDRPolicy.Config","label":"Auto-configure from MDE connector","defaultValue":true}
            {"type":"switch","name":"standards.DefenderEDRPolicy.SampleSharing","label":"Enable sample sharing","defaultValue":true}
            {"type":"radio","name":"standards.DefenderEDRPolicy.AssignTo","label":"Policy Assignment","options":[{"label":"Do not assign","value":"none"},{"label":"All users","value":"allLicensedUsers"},{"label":"All devices","value":"AllDevices"},{"label":"All users and devices","value":"AllDevicesAndUsers"}]}
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

    $PolicyName = 'EDR Configuration'

    # Setting definition IDs
    $SampleSharingDefId = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing'
    $ConfigTypeDefId = 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype'

    # Build expected values
    $ExpectedValue = [PSCustomObject]@{
        PolicyExists  = $true
        Config        = [bool]$Settings.Config
        SampleSharing = [bool]$Settings.SampleSharing
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

    # Parse current settings
    $CurrentConfig = $false
    $CurrentSampleSharing = $false
    if ($PolicyExists) {
        try {
            $PolicyDetail = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')?`$expand=settings" -tenantid $Tenant
            foreach ($setting in $PolicyDetail.settings) {
                $instance = $setting.settingInstance
                switch ($instance.settingDefinitionId) {
                    $SampleSharingDefId {
                        $CurrentSampleSharing = $instance.choiceSettingValue.value -like '*_1'
                    }
                    $ConfigTypeDefId {
                        $CurrentConfig = $instance.choiceSettingValue.value -like '*_autofromconnector'
                    }
                }
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to read EDR Policy settings: $($_.Exception.Message)" -sev Warning
        }
    }

    $CurrentValue = [PSCustomObject]@{
        PolicyExists  = $PolicyExists
        Config        = $CurrentConfig
        SampleSharing = $CurrentSampleSharing
    }

    # Field-by-field comparison
    $StateIsCorrect = $PolicyExists -and
                      ($CurrentConfig -eq [bool]$Settings.Config) -and
                      ($CurrentSampleSharing -eq [bool]$Settings.SampleSharing)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender EDR Policy already correctly configured' -sev Info
        } else {
            try {
                # Delete existing drifted policy so the helper can recreate
                if ($PolicyExists) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')" -tenantid $Tenant -type DELETE
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Deleted drifted Defender EDR Policy for recreation' -sev Info
                }

                $EDRSettings = @{
                    Config        = [bool]$Settings.Config
                    SampleSharing = [bool]$Settings.SampleSharing
                    AssignTo      = $Settings.AssignTo ?? 'none'
                }

                $Result = Set-CIPPDefenderEDRPolicy -TenantFilter $Tenant -EDR $EDRSettings -APIName 'Standards'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Defender EDR Policy: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender EDR Policy is correctly configured' -sev Info
        } else {
            Write-StandardsAlert -message 'Defender EDR Policy is not correctly configured' -object $CurrentValue -tenant $Tenant -standardName 'DefenderEDRPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender EDR Policy is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DefenderEDRPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DefenderEDRPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
