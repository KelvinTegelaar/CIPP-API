function Invoke-CIPPStandardDeployCheckChromeExtension {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DeployCheckChromeExtension
    .SYNOPSIS
        (Label) Deploy Check by CyberDrain Browser Extension
    .DESCRIPTION
        (Helptext) Deploys the Check by CyberDrain browser extension via a Win32 script app in Intune for both Chrome and Edge browsers with configurable settings. Chrome ID: benimdeioplgkhanklclahllklceahbe, Edge ID: knepjpocdagponkonnbggpcnhnaikajg
        (DocsDescription) Creates an Intune Win32 script application that writes registry keys to install and configure the Check by CyberDrain browser extension on managed devices for both Google Chrome and Microsoft Edge browsers. Uses a PowerShell detection script to enforce configuration drift — when settings change in CIPP the app is automatically redeployed.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Automatically deploys the Check by CyberDrain browser extension across all company devices with configurable security and branding settings, ensuring consistent security monitoring and compliance capabilities. This extension provides enhanced security features and monitoring tools that help protect against threats while maintaining user productivity.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.DeployCheckChromeExtension.showNotifications","label":"Show notifications","defaultValue":true}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enableValidPageBadge","label":"Enable valid page badge","defaultValue":false}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enablePageBlocking","label":"Enable page blocking","defaultValue":true}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.forceToolbarPin","label":"Force pin extension to toolbar","defaultValue":false}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enableCippReporting","label":"Enable CIPP reporting","defaultValue":true}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.customRulesUrl","label":"Custom Rules URL","placeholder":"https://YOUR-CIPP-SERVER-URL/rules.json","helperText":"Enter the URL for custom rules if you have them. This should point to a JSON file with the same structure as the rules.json used for CIPP reporting.","required":false}
            {"type":"number","name":"standards.DeployCheckChromeExtension.updateInterval","label":"Update interval (hours)","defaultValue":24}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enableDebugLogging","label":"Enable debug logging","defaultValue":false}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.enableGenericWebhook","label":"Enable generic webhook","defaultValue":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.webhookUrl","label":"Webhook URL","placeholder":"https://webhook.example.com/endpoint","required":false}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.DeployCheckChromeExtension.webhookEvents","label":"Webhook Events","placeholder":"e.g. pageBlocked, pageAllowed"}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"freeSolo":true,"name":"standards.DeployCheckChromeExtension.urlAllowlist","label":"URL Allowlist","placeholder":"e.g. https://example.com/*","helperText":"Enter URLs to allowlist in the extension. Press enter to add each URL. Wildcards are allowed. This should be used for sites that are being blocked by the extension but are known to be safe."}
            {"type":"switch","name":"standards.DeployCheckChromeExtension.domainSquattingEnabled","label":"Enable domain squatting detection","defaultValue":true}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.companyName","label":"Company Name","placeholder":"YOUR-COMPANY","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.companyURL","label":"Company URL","placeholder":"https://yourcompany.com","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.productName","label":"Product Name","placeholder":"YOUR-PRODUCT-NAME","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.supportEmail","label":"Support Email","placeholder":"support@yourcompany.com","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.supportUrl","label":"Support URL","placeholder":"https://support.yourcompany.com","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.privacyPolicyUrl","label":"Privacy Policy URL","placeholder":"https://yourcompany.com/privacy","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.aboutUrl","label":"About URL","placeholder":"https://yourcompany.com/about","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.primaryColor","label":"Primary Color","placeholder":"#F77F00","required":false}
            {"type":"textField","name":"standards.DeployCheckChromeExtension.logoUrl","label":"Logo URL","placeholder":"https://yourcompany.com/logo.png","required":false}
            {"name":"AssignTo","label":"Who should this app be assigned to?","type":"radio","options":[{"label":"Do not assign","value":"On"},{"label":"Assign to all users","value":"allLicensedUsers"},{"label":"Assign to all devices","value":"AllDevices"},{"label":"Assign to all users and devices","value":"AllDevicesAndUsers"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","required":false,"name":"customGroup","label":"Enter the custom group name if you selected 'Assign to Custom Group'. Wildcards are allowed."}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-09-18
        POWERSHELLEQUIVALENT
            Add-CIPPW32ScriptApplication
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "INTUNE_A"
            "MDM_Services"
            "EMS"
            "SCCM"
            "MICROSOFTINTUNEPLAN1"
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

    Write-Information "Running Check by CyberDrain standard for tenant $($Tenant)."

    ##########################################################################
    # Configuration values
    ##########################################################################
    $ChromeExtensionId = 'benimdeioplgkhanklclahllklceahbe'
    $EdgeExtensionId = 'knepjpocdagponkonnbggpcnhnaikajg'
    $AppDisplayName = 'Check by CyberDrain - Browser Extension'

    # CIPP Url
    $CippConfigTable = Get-CippTable -tablename Config
    $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
    $CIPPURL = 'https://{0}' -f $CippConfig.Value

    # Settings with defaults
    $ShowNotifications = [int][bool]($Settings.showNotifications ?? $true)
    $EnableValidPageBadge = [int][bool]($Settings.enableValidPageBadge ?? $false)
    $EnablePageBlocking = [int][bool]($Settings.enablePageBlocking ?? $true)
    $ForceToolbarPin = [int][bool]($Settings.forceToolbarPin ?? $true)
    $EnableCippReporting = [int][bool]($Settings.enableCippReporting ?? $false)
    $CippServerUrl = $CIPPURL
    $CippTenantId = $Tenant
    $CustomRulesUrl = $Settings.customRulesUrl ?? ''
    $UpdateInterval = [int]($Settings.updateInterval ?? 24)
    $EnableDebugLogging = [int][bool]($Settings.enableDebugLogging ?? $false)
    $EnableGenericWebhook = [int][bool]($Settings.enableGenericWebhook ?? $false)
    $WebhookUrl = $Settings.webhookUrl ?? ''
    $WebhookEvents = @($Settings.webhookEvents | ForEach-Object { $_.value ?? $_ } | Where-Object { $_ })
    $UrlAllowlist = @($Settings.urlAllowlist | ForEach-Object { $_.value ?? $_ } | Where-Object { $_ })
    $DomainSquattingEnabled = [int][bool]($Settings.domainSquattingEnabled ?? $true)
    $CompanyName = $Settings.companyName ?? ''
    $ProductName = $Settings.productName ?? ''
    $SupportEmail = $Settings.supportEmail ?? ''
    $SupportUrl = $Settings.supportUrl ?? ''
    $PrivacyPolicyUrl = $Settings.privacyPolicyUrl ?? ''
    $AboutUrl = $Settings.aboutUrl ?? ''
    $PrimaryColor = if ($Settings.primaryColor) { $Settings.primaryColor } else { '#F77F00' }
    $LogoUrl = $Settings.logoUrl ?? ''

    ##########################################################################
    # Build the install script (writes registry keys - matches upstream Deploy-Windows-Chrome-and-Edge.ps1)
    ##########################################################################
    $InstallScript = @"
# Check Chrome Extension - Install Script (generated by CIPP)
`$chromeExtensionId = '$ChromeExtensionId'
`$edgeExtensionId = '$EdgeExtensionId'

# Extension settings per browser
`$browsers = @(
    @{
        ExtensionId        = `$chromeExtensionId
        UpdateUrl          = 'https://clients2.google.com/service/update2/crx'
        ManagedStorageKey  = "HKLM:\SOFTWARE\Policies\Google\Chrome\3rdparty\extensions\`$chromeExtensionId\policy"
        ExtSettingsKey     = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionSettings\`$chromeExtensionId"
        ToolbarProp        = 'toolbar_pin'
        ToolbarPinned      = 'force_pinned'
        ToolbarUnpinned    = 'default_unpinned'
    },
    @{
        ExtensionId        = `$edgeExtensionId
        UpdateUrl          = 'https://edge.microsoft.com/extensionwebstorebase/v1/crx'
        ManagedStorageKey  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\3rdparty\extensions\`$edgeExtensionId\policy"
        ExtSettingsKey     = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionSettings\`$edgeExtensionId"
        ToolbarProp        = 'toolbar_state'
        ToolbarPinned      = 'force_shown'
        ToolbarUnpinned    = 'hidden'
    }
)

foreach (`$b in `$browsers) {
    # Managed storage - core settings
    if (!(Test-Path `$b.ManagedStorageKey)) { New-Item -Path `$b.ManagedStorageKey -Force | Out-Null }
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'showNotifications'    -PropertyType DWord  -Value $ShowNotifications    -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'enableValidPageBadge' -PropertyType DWord  -Value $EnableValidPageBadge -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'enablePageBlocking'   -PropertyType DWord  -Value $EnablePageBlocking   -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'enableCippReporting'  -PropertyType DWord  -Value $EnableCippReporting  -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'cippServerUrl'        -PropertyType String -Value '$CippServerUrl'      -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'cippTenantId'         -PropertyType String -Value '$CippTenantId'       -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'customRulesUrl'       -PropertyType String -Value '$CustomRulesUrl'     -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'updateInterval'       -PropertyType DWord  -Value $UpdateInterval       -Force | Out-Null
    New-ItemProperty -Path `$b.ManagedStorageKey -Name 'enableDebugLogging'   -PropertyType DWord  -Value $EnableDebugLogging   -Force | Out-Null

    # Managed storage - domainSquatting subkey
    `$domainSquattingKey = "`$(`$b.ManagedStorageKey)\domainSquatting"
    if (!(Test-Path `$domainSquattingKey)) { New-Item -Path `$domainSquattingKey -Force | Out-Null }
    New-ItemProperty -Path `$domainSquattingKey -Name 'enabled' -PropertyType DWord -Value $DomainSquattingEnabled -Force | Out-Null

    # Managed storage - customBranding subkey
    `$brandingKey = "`$(`$b.ManagedStorageKey)\customBranding"
    if (!(Test-Path `$brandingKey)) { New-Item -Path `$brandingKey -Force | Out-Null }
    New-ItemProperty -Path `$brandingKey -Name 'companyName'   -PropertyType String -Value '$($CompanyName -replace "'", "''")'   -Force | Out-Null

    New-ItemProperty -Path `$brandingKey -Name 'productName'   -PropertyType String -Value '$($ProductName -replace "'", "''")'   -Force | Out-Null
    New-ItemProperty -Path `$brandingKey -Name 'supportEmail'  -PropertyType String -Value '$($SupportEmail -replace "'", "''")' -Force | Out-Null
    New-ItemProperty -Path `$brandingKey -Name 'supportUrl'    -PropertyType String -Value '$($SupportUrl -replace "'", "''")'  -Force | Out-Null
    New-ItemProperty -Path `$brandingKey -Name 'privacyPolicyUrl' -PropertyType String -Value '$($PrivacyPolicyUrl -replace "'", "''")'  -Force | Out-Null
    New-ItemProperty -Path `$brandingKey -Name 'aboutUrl'      -PropertyType String -Value '$($AboutUrl -replace "'", "''")'  -Force | Out-Null
    New-ItemProperty -Path `$brandingKey -Name 'primaryColor'  -PropertyType String -Value '$PrimaryColor'  -Force | Out-Null
    New-ItemProperty -Path `$brandingKey -Name 'logoUrl'       -PropertyType String -Value '$($LogoUrl -replace "'", "''")'       -Force | Out-Null

    # Managed storage - genericWebhook subkey
    `$webhookKey = "`$(`$b.ManagedStorageKey)\genericWebhook"
    if (!(Test-Path `$webhookKey)) { New-Item -Path `$webhookKey -Force | Out-Null }
    New-ItemProperty -Path `$webhookKey -Name 'enabled' -PropertyType DWord  -Value $EnableGenericWebhook -Force | Out-Null
    New-ItemProperty -Path `$webhookKey -Name 'url'     -PropertyType String -Value '$($WebhookUrl -replace "'", "''")'     -Force | Out-Null

    # Managed storage - genericWebhook\events subkey
    `$webhookEventsKey = "`$(`$b.ManagedStorageKey)\genericWebhook\events"
    if (Test-Path `$webhookEventsKey) { Remove-Item -Path `$webhookEventsKey -Recurse -Force | Out-Null }
$(if ($WebhookEvents.Count -gt 0) {
    "    if (!(Test-Path `$webhookEventsKey)) { New-Item -Path `$webhookEventsKey -Force | Out-Null }`n"
    $i = 1
    foreach ($evt in $WebhookEvents) {
        "    New-ItemProperty -Path `$webhookEventsKey -Name '$i' -PropertyType String -Value '$($evt -replace "'", "''")' -Force | Out-Null`n"
        $i++
    }
})
    # Managed storage - urlAllowlist subkey
    `$allowlistKey = "`$(`$b.ManagedStorageKey)\urlAllowlist"
    if (Test-Path `$allowlistKey) { Remove-Item -Path `$allowlistKey -Recurse -Force | Out-Null }
$(if ($UrlAllowlist.Count -gt 0) {
    "    if (!(Test-Path `$allowlistKey)) { New-Item -Path `$allowlistKey -Force | Out-Null }`n"
    $i = 1
    foreach ($url in $UrlAllowlist) {
        "    New-ItemProperty -Path `$allowlistKey -Name '$i' -PropertyType String -Value '$($url -replace "'", "''")' -Force | Out-Null`n"
        $i++
    }
})
    # Extension settings (installation + toolbar)
    if (!(Test-Path `$b.ExtSettingsKey)) { New-Item -Path `$b.ExtSettingsKey -Force | Out-Null }
    New-ItemProperty -Path `$b.ExtSettingsKey -Name 'installation_mode' -PropertyType String -Value 'force_installed' -Force | Out-Null
    New-ItemProperty -Path `$b.ExtSettingsKey -Name 'update_url'        -PropertyType String -Value `$b.UpdateUrl     -Force | Out-Null
    if ($ForceToolbarPin -eq 1) {
        New-ItemProperty -Path `$b.ExtSettingsKey -Name `$b.ToolbarProp -PropertyType String -Value `$b.ToolbarPinned -Force | Out-Null
    } else {
        New-ItemProperty -Path `$b.ExtSettingsKey -Name `$b.ToolbarProp -PropertyType String -Value `$b.ToolbarUnpinned -Force | Out-Null
    }
}

Write-Output 'Check Chrome Extension registry keys configured successfully.'
"@

    ##########################################################################
    # Build the uninstall script (removes registry keys - matches upstream Remove-Windows-Chrome-and-Edge.ps1)
    ##########################################################################
    $UninstallScript = @"
# Check Chrome Extension - Uninstall Script (generated by CIPP)
`$chromeExtensionId = '$ChromeExtensionId'
`$edgeExtensionId = '$EdgeExtensionId'

`$keysToRemove = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome\3rdparty\extensions\`$chromeExtensionId",
    "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionSettings\`$chromeExtensionId",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge\3rdparty\extensions\`$edgeExtensionId",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionSettings\`$edgeExtensionId"
)

foreach (`$key in `$keysToRemove) {
    if (Test-Path `$key) {
        Remove-Item -Path `$key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Removed: `$key"
    }
}

Write-Output 'Check Chrome Extension registry keys removed.'
"@

    ##########################################################################
    # Build the detection script
    # Checks that critical DWORD values match expected config. When settings
    # change in CIPP the detection script body changes, so Intune sees a new
    # app version and redeploys automatically.
    ##########################################################################
    $DetectionScript = @"
# Check Chrome Extension - Detection Script (generated by CIPP)
`$chromeKey = 'HKLM:\SOFTWARE\Policies\Google\Chrome\3rdparty\extensions\$ChromeExtensionId\policy'
`$edgeKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\3rdparty\extensions\$EdgeExtensionId\policy'

# Verify both managed storage keys exist
if (!(Test-Path `$chromeKey) -or !(Test-Path `$edgeKey)) { exit 1 }

# Helper to check a registry value matches expected
function Test-RegValue(`$Path, `$Name, `$Expected) {
    `$val = (Get-ItemProperty -Path `$Path -Name `$Name -ErrorAction SilentlyContinue).`$Name
    return (`$null -ne `$val -and `$val -eq `$Expected)
}

foreach (`$key in @(`$chromeKey, `$edgeKey)) {
    # Core DWORD settings
    if (!(Test-RegValue `$key 'showNotifications'    $ShowNotifications))    { exit 1 }
    if (!(Test-RegValue `$key 'enableValidPageBadge' $EnableValidPageBadge)) { exit 1 }
    if (!(Test-RegValue `$key 'enablePageBlocking'   $EnablePageBlocking))   { exit 1 }
    if (!(Test-RegValue `$key 'enableCippReporting'  $EnableCippReporting))  { exit 1 }
    if (!(Test-RegValue `$key 'updateInterval'       $UpdateInterval))       { exit 1 }
    if (!(Test-RegValue `$key 'enableDebugLogging'   $EnableDebugLogging))   { exit 1 }

    # Core string settings
    if (!(Test-RegValue `$key 'cippServerUrl'  '$CippServerUrl'))  { exit 1 }
    if (!(Test-RegValue `$key 'cippTenantId'   '$CippTenantId'))   { exit 1 }
    if (!(Test-RegValue `$key 'customRulesUrl' '$CustomRulesUrl')) { exit 1 }

    # domainSquatting subkey
    `$domainSquattingKey = "`$key\domainSquatting"
    if (!(Test-Path `$domainSquattingKey)) { exit 1 }
    if (!(Test-RegValue `$domainSquattingKey 'enabled' $DomainSquattingEnabled)) { exit 1 }

    # customBranding subkey
    `$brandingKey = "`$key\customBranding"
    if (!(Test-Path `$brandingKey)) { exit 1 }
    if (!(Test-RegValue `$brandingKey 'companyName'  '$($CompanyName -replace "'", "''")'))  { exit 1 }

    if (!(Test-RegValue `$brandingKey 'productName'  '$($ProductName -replace "'", "''")'))  { exit 1 }
    if (!(Test-RegValue `$brandingKey 'supportEmail'    '$($SupportEmail -replace "'", "''")'))    { exit 1 }
    if (!(Test-RegValue `$brandingKey 'supportUrl'       '$($SupportUrl -replace "'", "''")'))       { exit 1 }
    if (!(Test-RegValue `$brandingKey 'privacyPolicyUrl' '$($PrivacyPolicyUrl -replace "'", "''")')) { exit 1 }
    if (!(Test-RegValue `$brandingKey 'aboutUrl'         '$($AboutUrl -replace "'", "''")'))         { exit 1 }
    if (!(Test-RegValue `$brandingKey 'primaryColor' '$PrimaryColor')) { exit 1 }
    if (!(Test-RegValue `$brandingKey 'logoUrl'      '$($LogoUrl -replace "'", "''")'))      { exit 1 }

    # genericWebhook subkey
    `$webhookKey = "`$key\genericWebhook"
    if (!(Test-Path `$webhookKey)) { exit 1 }
    if (!(Test-RegValue `$webhookKey 'enabled' $EnableGenericWebhook)) { exit 1 }
    if (!(Test-RegValue `$webhookKey 'url'     '$($WebhookUrl -replace "'", "''")'))     { exit 1 }

    # genericWebhook\events subkey — verify exact count and values
    `$eventsKey = "`$key\genericWebhook\events"
$(if ($WebhookEvents.Count -gt 0) {
    "    if (!(Test-Path `$eventsKey)) { exit 1 }`n"
    $i = 1
    foreach ($evt in $WebhookEvents) {
        "    if (!(Test-RegValue `$eventsKey '$i' '$($evt -replace "'", "''")')) { exit 1 }`n"
        $i++
    }
    "    `$eventsCount = (Get-Item `$eventsKey).Property.Count`n"
    "    if (`$eventsCount -ne $($WebhookEvents.Count)) { exit 1 }`n"
} else {
    "    if (Test-Path `$eventsKey) {`n"
    "        `$eventsCount = (Get-Item `$eventsKey).Property.Count`n"
    "        if (`$eventsCount -gt 0) { exit 1 }`n"
    "    }`n"
})
    # urlAllowlist subkey — verify exact count and values
    `$allowlistKey = "`$key\urlAllowlist"
$(if ($UrlAllowlist.Count -gt 0) {
    "    if (!(Test-Path `$allowlistKey)) { exit 1 }`n"
    $i = 1
    foreach ($url in $UrlAllowlist) {
        "    if (!(Test-RegValue `$allowlistKey '$i' '$($url -replace "'", "''")')) { exit 1 }`n"
        $i++
    }
    "    `$allowlistCount = (Get-Item `$allowlistKey).Property.Count`n"
    "    if (`$allowlistCount -ne $($UrlAllowlist.Count)) { exit 1 }`n"
} else {
    "    if (Test-Path `$allowlistKey) {`n"
    "        `$allowlistCount = (Get-Item `$allowlistKey).Property.Count`n"
    "        if (`$allowlistCount -gt 0) { exit 1 }`n"
    "    }`n"
})
}

# Verify extension settings keys exist
`$chromeExtSettings = 'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionSettings\$ChromeExtensionId'
`$edgeExtSettings   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionSettings\$EdgeExtensionId'
if (!(Test-Path `$chromeExtSettings) -or !(Test-Path `$edgeExtSettings)) { exit 1 }

Write-Output 'Check Chrome Extension is correctly configured.'
exit 0
"@

    ##########################################################################
    # Compute a settings fingerprint from the install script so we can skip
    # redeploy when nothing has changed.
    ##########################################################################
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    $SettingsHash = ([System.BitConverter]::ToString(
            $Sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($InstallScript))
        ) -replace '-', '').Substring(0, 16)
    $AppDescription = "Deploys and configures the Check by CyberDrain phishing protection extension for Chrome and Edge browsers. Managed by CIPP. [cfg:$SettingsHash]"

    ##########################################################################
    # Legacy OMA-URI policy cleanup
    ##########################################################################
    $LegacyPolicyNames = @(
        'Deploy Check Chrome Extension (Chrome)',
        'Deploy Check Chrome Extension (Edge)'
    )

    try {
        ##########################################################################
        # Check for existing Win32 app
        ##########################################################################
        $Baseuri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
        $ExistingApps = New-GraphGetRequest -Uri "$Baseuri`?`$filter=displayName eq '$AppDisplayName'&`$select=id,displayName,description" -tenantid $Tenant | Where-Object {
            $_.'@odata.type' -eq '#microsoft.graph.win32LobApp'
        }
        $AppExists = ($null -ne $ExistingApps -and @($ExistingApps).Count -gt 0)

        if ($Settings.remediate -eq $true) {
            $AssignTo = $Settings.AssignTo ?? 'AllDevices'
            if ($Settings.customGroup) { $AssignTo = $Settings.customGroup }

            # Clean up legacy OMA-URI configuration policies from the old approach
            $LegacyPolicies = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?$select=id,displayName' -tenantid $Tenant | Where-Object {
                $_.displayName -in $LegacyPolicyNames
            }
            if ($LegacyPolicies) {
                $DeleteRequests = @($LegacyPolicies | ForEach-Object {
                        @{
                            id     = "delete-$($_.id)"
                            method = 'DELETE'
                            url    = "deviceManagement/deviceConfigurations/$($_.id)"
                        }
                    })
                $BulkResults = New-GraphBulkRequest -tenantid $Tenant -Requests $DeleteRequests
                foreach ($Policy in $LegacyPolicies) {
                    $Result = $BulkResults | Where-Object { $_.id -eq "delete-$($Policy.id)" }
                    if ($Result.status -match '^2') {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Removed legacy OMA-URI policy: $($Policy.displayName)" -sev Info
                    } else {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to remove legacy OMA-URI policy: $($Policy.displayName) - $($Result.body.error.message)" -sev Warning
                    }
                }
            }

            if ($AppExists) {
                # Check if the settings hash matches — skip redeploy if nothing changed
                $ExistingHash = $null
                $ExistingApp = @($ExistingApps)[0]
                if ($ExistingApp.description -match '\[cfg:([0-9A-Fa-f]{16})\]') {
                    $ExistingHash = $Matches[1]
                }

                if ($ExistingHash -eq $SettingsHash) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "$AppDisplayName settings unchanged — skipping redeploy" -sev Info
                } else {
                    foreach ($App in @($ExistingApps)) {
                        $null = New-GraphPostRequest -Uri "$Baseuri/$($App.id)" -Type DELETE -tenantid $Tenant
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Removed existing $AppDisplayName app to redeploy with updated settings" -sev Info
                    }
                    Start-Sleep -Seconds 2

                    # Deploy the Win32 script app
                    $AppProperties = [PSCustomObject]@{
                        displayName           = $AppDisplayName
                        description           = $AppDescription
                        publisher             = 'CIPP'
                        installScript         = $InstallScript
                        uninstallScript       = $UninstallScript
                        detectionScript       = $DetectionScript
                        runAsAccount          = 'system'
                        deviceRestartBehavior = 'suppress'
                    }

                    $NewApp = Add-CIPPW32ScriptApplication -TenantFilter $Tenant -Properties $AppProperties

                    if ($NewApp -and $AssignTo -ne 'On') {
                        Start-Sleep -Milliseconds 500
                        Set-CIPPAssignedApplication -ApplicationId $NewApp.Id -TenantFilter $Tenant -GroupName $AssignTo -Intent 'Required' -AppType 'Win32Lob' -APIName 'Standards'
                    }

                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully deployed $AppDisplayName" -sev Info
                }
            } else {
                # App doesn't exist yet — deploy it
                $AppProperties = [PSCustomObject]@{
                    displayName           = $AppDisplayName
                    description           = $AppDescription
                    publisher             = 'CIPP'
                    installScript         = $InstallScript
                    uninstallScript       = $UninstallScript
                    detectionScript       = $DetectionScript
                    runAsAccount          = 'system'
                    deviceRestartBehavior = 'suppress'
                }

                $NewApp = Add-CIPPW32ScriptApplication -TenantFilter $Tenant -Properties $AppProperties

                if ($NewApp -and $AssignTo -ne 'On') {
                    Start-Sleep -Milliseconds 500
                    Set-CIPPAssignedApplication -ApplicationId $NewApp.Id -TenantFilter $Tenant -GroupName $AssignTo -Intent 'Required' -AppType 'Win32Lob' -APIName 'Standards'
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully deployed $AppDisplayName" -sev Info
            }
        }

        if ($Settings.alert -eq $true) {
            if ($AppExists) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "$AppDisplayName is deployed" -sev Info
            } else {
                Write-StandardsAlert -message "$AppDisplayName is not deployed" -object @{ AppName = $AppDisplayName } -tenant $Tenant -standardName 'DeployCheckChromeExtension' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "$AppDisplayName is not deployed" -sev Alert
            }
        }

        if ($Settings.report -eq $true) {
            $StateIsCorrect = $AppExists
            $ExpectedValue = [PSCustomObject]@{
                AppDeployed = $true
            }
            $CurrentValue = [PSCustomObject]@{
                AppDeployed = [bool]$AppExists
            }
            Set-CIPPStandardsCompareField -FieldName 'standards.DeployCheckChromeExtension' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
            Add-CIPPBPAField -FieldName 'DeployCheckChromeExtension' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        }

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy $AppDisplayName. Error: $ErrorMessage" -sev Error

        if ($Settings.alert -eq $true) {
            Write-StandardsAlert -message "Failed to deploy ${AppDisplayName}: $ErrorMessage" -object @{ 'Error' = $ErrorMessage } -tenant $Tenant -standardName 'DeployCheckChromeExtension' -standardId $Settings.standardId
        }

        if ($Settings.report -eq $true) {
            Set-CIPPStandardsCompareField -FieldName 'standards.DeployCheckChromeExtension' -FieldValue @{ 'Error' = $ErrorMessage } -TenantFilter $Tenant
            Add-CIPPBPAField -FieldName 'DeployCheckChromeExtension' -FieldValue $false -StoreAs bool -Tenant $Tenant
        }
    }
}
