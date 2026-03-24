function Invoke-CIPPStandardDeployCheckChromeExtension {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DeployCheckChromeExtension
    .SYNOPSIS
        (Label) Deploy Check Chrome Extension
    .DESCRIPTION
        (Helptext) Deploys the Check Chrome extension via Intune OMA-URI custom policies for both Chrome and Edge browsers with configurable settings. Chrome ID: benimdeioplgkhanklclahllklceahbe, Edge ID: knepjpocdagponkonnbggpcnhnaikajg
        (DocsDescription) Creates Intune OMA-URI custom policies that automatically install and configure the Check Chrome extension on managed devices for both Google Chrome and Microsoft Edge browsers. This ensures the extension is deployed consistently across all corporate devices with customizable settings.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Automatically deploys the Check browser extension across all company devices with configurable security and branding settings, ensuring consistent security monitoring and compliance capabilities. This extension provides enhanced security features and monitoring tools that help protect against threats while maintaining user productivity.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enableValidPageBadge","label":"Enable valid page badge","defaultValue":true}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enablePageBlocking","label":"Enable page blocking","defaultValue":true}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enableCippReporting","label":"Enable CIPP reporting","defaultValue":true}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.cippServerUrl","label":"CIPP Server URL","placeholder":"https://YOUR-CIPP-SERVER-URL","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.customRulesUrl","label":"Custom Rules URL","placeholder":"https://YOUR-CIPP-SERVER-URL/rules.json","required":false}
            {"type":"number","name":"standards.DeployCheckChromeExtension.updateInterval","label":"Update interval (hours)","defaultValue":12}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enableDebugLogging","label":"Enable debug logging","defaultValue":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.companyName","label":"Company Name","placeholder":"YOUR-COMPANY","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.productName","label":"Product Name","placeholder":"YOUR-PRODUCT-NAME","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.supportEmail","label":"Support Email","placeholder":"support@yourcompany.com","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.primaryColor","label":"Primary Color","placeholder":"#0044CC","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.logoUrl","label":"Logo URL","placeholder":"https://yourcompany.com/logo.png","required":false}
            {"name":"AssignTo","label":"Who should this policy be assigned to?","type":"radio","options":[{"label":"Do not assign","value":"On"},{"label":"Assign to all users","value":"allLicensedUsers"},{"label":"Assign to all devices","value":"AllDevices"},{"label":"Assign to all users and devices","value":"AllDevicesAndUsers"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","required":false,"name":"customGroup","label":"Enter the custom group name if you selected 'Assign to Custom Group'. Wildcards are allowed."}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-09-18
        POWERSHELLEQUIVALENT
            New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    # Check for required Intune license
    $TestResult = Test-CIPPStandardLicense -StandardName 'DeployCheckChromeExtension' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DeployCheckChromeExtension' -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'This tenant does not have the required license for this standard.' -sev Error
        return $true
    }

    Write-Information "Running Deploy Check Chrome Extension standard for tenant $($Tenant)."

    # Chrome and Edge extension IDs for the Check extension
    $ChromeExtensionId = 'benimdeioplgkhanklclahllklceahbe'
    $EdgeExtensionId = 'knepjpocdagponkonnbggpcnhnaikajg'

    # Policy names
    $ChromePolicyName = 'Deploy Check Chrome Extension (Chrome)'
    $EdgePolicyName = 'Deploy Check Chrome Extension (Edge)'

    # CIPP Url
    $CippConfigTable = Get-CippTable -tablename Config
    $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
    $CIPPURL = 'https://{0}' -f $CippConfig.Value

    # Get configuration values with defaults
    $ShowNotifications = $Settings.showNotifications ?? $true
    $EnableValidPageBadge = $Settings.enableValidPageBadge ?? $true
    $EnablePageBlocking = $Settings.enablePageBlocking ?? $true
    $EnableCippReporting = $Settings.enableCippReporting ?? $true
    $CippServerUrl = $CIPPURL
    $CippTenantId = $Tenant
    $CustomRulesUrl = $Settings.customRulesUrl
    $UpdateInterval = $Settings.updateInterval ?? 24
    $EnableDebugLogging = $Settings.enableDebugLogging ?? $false
    $CompanyName = $Settings.companyName
    $ProductName = $Settings.productName
    $SupportEmail = $Settings.supportEmail
    $PrimaryColor = $Settings.primaryColor ?? '#F77F00'
    $LogoUrl = $Settings.logoUrl

    # Create extension settings JSON
    $ChromeExtensionSettings = @{
        $ChromeExtensionId = @{
            installation_mode = 'force_installed'
            update_url        = 'https://clients2.google.com/service/update2/crx'
            settings          = @{
                showNotifications    = $ShowNotifications
                enableValidPageBadge = $EnableValidPageBadge
                enablePageBlocking   = $EnablePageBlocking
                enableCippReporting  = $EnableCippReporting
                cippServerUrl        = $CippServerUrl
                cippTenantId         = $CippTenantId
                customRulesUrl       = $CustomRulesUrl
                updateInterval       = $UpdateInterval
                enableDebugLogging   = $EnableDebugLogging
                customBranding       = @{
                    companyName  = $CompanyName
                    productName  = $ProductName
                    supportEmail = $SupportEmail
                    primaryColor = $PrimaryColor
                    logoUrl      = $LogoUrl
                }
            }
        }
    } | ConvertTo-Json -Depth 10

    $EdgeExtensionSettings = @{
        $EdgeExtensionId = @{
            installation_mode = 'force_installed'
            update_url        = 'https://edge.microsoft.com/extensionwebstorebase/v1/crx'
            settings          = @{
                showNotifications    = $ShowNotifications
                enableValidPageBadge = $EnableValidPageBadge
                enablePageBlocking   = $EnablePageBlocking
                enableCippReporting  = $EnableCippReporting
                cippServerUrl        = $CippServerUrl
                cippTenantId         = $CippTenantId
                customRulesUrl       = $CustomRulesUrl
                updateInterval       = $UpdateInterval
                enableDebugLogging   = $EnableDebugLogging
                customBranding       = @{
                    companyName  = $CompanyName
                    productName  = $ProductName
                    supportEmail = $SupportEmail
                    primaryColor = $PrimaryColor
                    logoUrl      = $LogoUrl
                }
            }
        }
    } | ConvertTo-Json -Depth 10

    # Create Chrome OMA-URI policy JSON
    $ChromePolicyJSON = @{
        '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
        displayName   = $ChromePolicyName
        description   = 'Deploys and configures the Check Chrome extension for Google Chrome browsers'
        omaSettings   = @(
            @{
                '@odata.type' = '#microsoft.graph.omaSettingString'
                displayName   = 'Chrome Extension Settings'
                description   = 'Configure Check Chrome extension settings'
                omaUri        = './Device/Vendor/MSFT/Policy/Config/Chrome~Policy~googlechrome/ExtensionSettings'
                value         = $ChromeExtensionSettings
            }
        )
    } | ConvertTo-Json -Depth 20

    # Create Edge OMA-URI policy JSON
    $EdgePolicyJSON = @{
        '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
        displayName   = $EdgePolicyName
        description   = 'Deploys and configures the Check Chrome extension for Microsoft Edge browsers'
        omaSettings   = @(
            @{
                '@odata.type' = '#microsoft.graph.omaSettingString'
                displayName   = 'Edge Extension Settings'
                description   = 'Configure Check Chrome extension settings'
                omaUri        = './Device/Vendor/MSFT/Policy/Config/Edge/ExtensionSettings'
                value         = $EdgeExtensionSettings
            }
        )
    } | ConvertTo-Json -Depth 20

    # Compares OMA-URI settings between expected and existing policy.
    # The 'value' field of omaSettingString is itself a JSON string, so we parse it
    # before calling Compare-CIPPIntuneObject to avoid false positives from whitespace
    # or key-ordering differences introduced by Intune's API response serialization.
    function Compare-OMAURISettings {
        param(
            [Parameter(Mandatory = $true)]$ExpectedSettings,
            [Parameter(Mandatory = $true)]$ExistingConfig
        )
        $diffs = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($null -eq $ExistingConfig -or $null -eq $ExistingConfig.omaSettings) { return $diffs }

        foreach ($expectedSetting in $ExpectedSettings) {
            $existingSetting = $ExistingConfig.omaSettings | Where-Object { $_.omaUri -eq $expectedSetting.omaUri }
            if (-not $existingSetting) {
                $diffs.Add([PSCustomObject]@{ Property = $expectedSetting.omaUri; ExpectedValue = 'present'; ReceivedValue = 'missing' })
                continue
            }
            try {
                $expectedValue = $expectedSetting.value | ConvertFrom-Json -Depth 20
                $existingValue = $existingSetting.value | ConvertFrom-Json -Depth 20
                $valueDiffs = Compare-CIPPIntuneObject -ReferenceObject $expectedValue -DifferenceObject $existingValue -CompareType 'Device'
                foreach ($diff in $valueDiffs) {
                    $diffs.Add([PSCustomObject]@{ Property = "$($expectedSetting.omaUri).$($diff.Property)"; ExpectedValue = $diff.ExpectedValue; ReceivedValue = $diff.ReceivedValue })
                }
            } catch {
                # Fall back to string comparison if either value is not valid JSON
                if ($expectedSetting.value -ne $existingSetting.value) {
                    $diffs.Add([PSCustomObject]@{ Property = $expectedSetting.omaUri; ExpectedValue = '[expected value]'; ReceivedValue = '[current value differs]' })
                }
            }
        }
        return $diffs
    }

    try {
        # Fetch existing policies with full configuration details for OMA-URI drift detection
        $ExistingChromePolicy = Get-CIPPIntunePolicy -TemplateType 'Device' -DisplayName $ChromePolicyName -tenantFilter $Tenant
        $ExistingEdgePolicy = Get-CIPPIntunePolicy -TemplateType 'Device' -DisplayName $EdgePolicyName -tenantFilter $Tenant

        $ChromePolicyExists = $null -ne $ExistingChromePolicy
        $EdgePolicyExists = $null -ne $ExistingEdgePolicy

        # Build expected OMA-URI settings from the generated policy JSON for comparison
        $ExpectedChromeSettings = ($ChromePolicyJSON | ConvertFrom-Json).omaSettings
        $ExpectedEdgeSettings = ($EdgePolicyJSON | ConvertFrom-Json).omaSettings

        # Detect configuration drift in existing policies
        $ChromeDifferences = [System.Collections.Generic.List[PSCustomObject]]::new()
        $EdgeDifferences = [System.Collections.Generic.List[PSCustomObject]]::new()

        if ($ExistingChromePolicy) {
            # omaSettingString values are encrypted by Intune; decrypt before comparing
            $DecryptedChromePolicy = Get-CIPPOmaSettingDecryptedValue -DeviceConfiguration ($ExistingChromePolicy.cippconfiguration | ConvertFrom-Json) -DeviceConfigurationId $ExistingChromePolicy.id -TenantFilter $Tenant
            $ChromeDifferences = Compare-OMAURISettings -ExpectedSettings $ExpectedChromeSettings -ExistingConfig $DecryptedChromePolicy
        }

        if ($ExistingEdgePolicy) {
            # omaSettingString values are encrypted by Intune; decrypt before comparing
            $DecryptedEdgePolicy = Get-CIPPOmaSettingDecryptedValue -DeviceConfiguration ($ExistingEdgePolicy.cippconfiguration | ConvertFrom-Json) -DeviceConfigurationId $ExistingEdgePolicy.id -TenantFilter $Tenant
            $EdgeDifferences = Compare-OMAURISettings -ExpectedSettings $ExpectedEdgeSettings -ExistingConfig $DecryptedEdgePolicy
        }

        $ChromePolicyCompliant = $ChromePolicyExists -and ($ChromeDifferences.Count -eq 0)
        $EdgePolicyCompliant = $EdgePolicyExists -and ($EdgeDifferences.Count -eq 0)

        if ($Settings.remediate -eq $true) {
            # Handle assignment configuration
            $AssignTo = $Settings.AssignTo ?? 'AllDevices'
            $ExcludeGroup = $Settings.ExcludeGroup

            # Handle custom group assignment
            if ($Settings.customGroup) {
                $AssignTo = $Settings.customGroup
            }

            # Deploy or remediate Chrome policy (create if missing, update if drifted)
            if (-not $ChromePolicyExists) {
                $Result = Set-CIPPIntunePolicy -TemplateType 'Device' -Description 'Deploys and configures the Check Chrome extension for Google Chrome browsers' -DisplayName $ChromePolicyName -RawJSON $ChromePolicyJSON -AssignTo $AssignTo -ExcludeGroup $ExcludeGroup -tenantFilter $Tenant
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully created Check Chrome Extension policy for Chrome: $ChromePolicyName" -sev Info
            } elseif ($ChromeDifferences.Count -gt 0) {
                $Result = Set-CIPPIntunePolicy -TemplateType 'Device' -Description 'Deploys and configures the Check Chrome extension for Google Chrome browsers' -DisplayName $ChromePolicyName -RawJSON $ChromePolicyJSON -AssignTo $AssignTo -ExcludeGroup $ExcludeGroup -tenantFilter $Tenant
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully corrected $($ChromeDifferences.Count) drifted OMA-URI setting(s) in Check Chrome Extension policy for Chrome" -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Check Chrome Extension policy for Chrome is compliant, no changes needed' -sev Info
            }

            # Deploy or remediate Edge policy (create if missing, update if drifted)
            if (-not $EdgePolicyExists) {
                $Result = Set-CIPPIntunePolicy -TemplateType 'Device' -Description 'Deploys and configures the Check Chrome extension for Microsoft Edge browsers' -DisplayName $EdgePolicyName -RawJSON $EdgePolicyJSON -AssignTo $AssignTo -ExcludeGroup $ExcludeGroup -tenantFilter $Tenant
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully created Check Chrome Extension policy for Edge: $EdgePolicyName" -sev Info
            } elseif ($EdgeDifferences.Count -gt 0) {
                $Result = Set-CIPPIntunePolicy -TemplateType 'Device' -Description 'Deploys and configures the Check Chrome extension for Microsoft Edge browsers' -DisplayName $EdgePolicyName -RawJSON $EdgePolicyJSON -AssignTo $AssignTo -ExcludeGroup $ExcludeGroup -tenantFilter $Tenant
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully corrected $($EdgeDifferences.Count) drifted OMA-URI setting(s) in Check Chrome Extension policy for Edge" -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Check Chrome Extension policy for Edge is compliant, no changes needed' -sev Info
            }
        }

        if ($Settings.alert -eq $true) {
            if ($ChromePolicyCompliant -and $EdgePolicyCompliant) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Check Chrome Extension policies are deployed and correctly configured for both Chrome and Edge' -sev Info
            } else {
                $Issues = [System.Collections.Generic.List[string]]::new()
                if (-not $ChromePolicyExists) {
                    $Issues.Add('Chrome policy is missing')
                } elseif ($ChromeDifferences.Count -gt 0) {
                    $Issues.Add("Chrome policy OMA-URI settings differ ($($ChromeDifferences.Count) difference(s))")
                }
                if (-not $EdgePolicyExists) {
                    $Issues.Add('Edge policy is missing')
                } elseif ($EdgeDifferences.Count -gt 0) {
                    $Issues.Add("Edge policy OMA-URI settings differ ($($EdgeDifferences.Count) difference(s))")
                }
                Write-StandardsAlert -message "Check Chrome Extension issues: $($Issues -join '; ')" -object @{ Issues = ($Issues -join '; '); ChromeDifferences = $ChromeDifferences; EdgeDifferences = $EdgeDifferences } -tenant $Tenant -standardName 'DeployCheckChromeExtension' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Check Chrome Extension issues: $($Issues -join '; ')" -sev Alert
            }
        }

        if ($Settings.report -eq $true) {
            $StateIsCorrect = $ChromePolicyCompliant -and $EdgePolicyCompliant

            $ExpectedValue = [PSCustomObject]@{
                ChromePolicyDeployed  = $true
                ChromePolicyCompliant = $true
                EdgePolicyDeployed    = $true
                EdgePolicyCompliant   = $true
            }
            $CurrentValue = [PSCustomObject]@{
                ChromePolicyDeployed  = [bool]$ChromePolicyExists
                ChromePolicyCompliant = [bool]$ChromePolicyCompliant
                EdgePolicyDeployed    = [bool]$EdgePolicyExists
                EdgePolicyCompliant   = [bool]$EdgePolicyCompliant
            }
            Set-CIPPStandardsCompareField -FieldName 'standards.DeployCheckChromeExtension' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
            Add-CIPPBPAField -FieldName 'DeployCheckChromeExtension' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        }

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Check Chrome Extension policies. Error: $ErrorMessage" -sev Error

        if ($Settings.alert -eq $true) {
            Write-StandardsAlert -message "Failed to deploy Check Chrome Extension policies: $ErrorMessage" -object @{ 'Error' = $ErrorMessage } -tenant $Tenant -standardName 'DeployCheckChromeExtension' -standardId $Settings.standardId
        }

        if ($Settings.report -eq $true) {
            Set-CIPPStandardsCompareField -FieldName 'standards.DeployCheckChromeExtension' -FieldValue @{ 'Error' = $ErrorMessage } -TenantFilter $Tenant
            Add-CIPPBPAField -FieldName 'DeployCheckChromeExtension' -FieldValue $false -StoreAs bool -Tenant $Tenant
        }
    }
}
