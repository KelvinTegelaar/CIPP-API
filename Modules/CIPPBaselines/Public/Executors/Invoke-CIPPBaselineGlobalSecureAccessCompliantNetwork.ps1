function Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork {
    <#
    .SYNOPSIS
        GlobalSecureAccessCompliantNetwork executor: onboards the tenant and enables the
        Microsoft 365 traffic profile, deploys the client through Intune, then creates the
        compliant-network Conditional Access policy. Client objects carry a [cfg:hash]
        fingerprint and are only redeployed when it changes.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)

    $DeployWindows = $Remediate.deployWindows -ne $false
    $DeployMacOS = $Remediate.deployMacOS -ne $false
    $PreferIPv4 = $Remediate.preferIPv4 -ne $false
    $LockDown = [int]($Remediate.lockDownClient -ne $false)
    $Enforce = $Remediate.enforce -eq $true
    $RoleIds = @($Remediate.excludeAdminRoles | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ } | Sort-Object -Unique)
    $UserRefs = @($Remediate.excludeUsers | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
    $GroupRefs = @($Remediate.excludeGroups | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
    $AssignTo = "$($Remediate.assignTo.value ?? $Remediate.assignTo)"
    if (-not $AssignTo) { $AssignTo = 'AllDevices' }
    if ("$($Remediate.customGroup)") { $AssignTo = "$($Remediate.customGroup)" }
    $PolicyAssignTo = if ($AssignTo -eq 'AllUsers') { 'allLicensedUsers' } else { $AssignTo }
    $ExcludeGroup = "$($Remediate.excludeGroup)"
    if (-not $DeployWindows -and -not $DeployMacOS) { throw 'Enable Windows, macOS or both; without the client no device can satisfy the compliant network check.' }

    $Graph = 'https://graph.microsoft.com/beta'
    $Changed = $false
    $Refresh = [System.Collections.Generic.List[string]]::new()
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    $Hash = { param($Text) ([System.BitConverter]::ToString($Sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').Substring(0, 16) }

    # --- tenant: onboard, Microsoft 365 profile for all users, signaling, named location
    $Status = New-GraphGetRequest -uri "$Graph/networkAccess/tenantStatus" -tenantid $TenantFilter -AsApp $true
    if ($Status.onboardingStatus -ne 'onboarded') {
        if ($Status.onboardingStatus -eq 'onboardingErrorOccurred') { throw "Global Secure Access onboarding failed earlier: $($Status.onboardingErrorMessage)" }
        if ($Status.onboardingStatus -ne 'onboardingInProgress') {
            $null = New-GraphPostRequest -uri "$Graph/networkAccess/microsoft.graph.networkaccess.onboard" -tenantid $TenantFilter -type POST -body '{}' -AsApp $true
        }
        $Attempts = 0
        do {
            Start-Sleep -Seconds 15
            $Attempts++
            $Status = New-GraphGetRequest -uri "$Graph/networkAccess/tenantStatus" -tenantid $TenantFilter -AsApp $true
        } while ($Status.onboardingStatus -eq 'onboardingInProgress' -and $Attempts -lt 12)
        if ($Status.onboardingStatus -ne 'onboarded') { throw "Global Secure Access onboarding is still '$($Status.onboardingStatus)'; run the standard again later." }
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Onboarded the tenant to Global Secure Access.' -Sev 'Info'
        $Changed = $true
        $Refresh.Add('NetworkAccess')
    }

    $Profiles = @(New-GraphGetRequest -uri "$Graph/networkAccess/forwardingProfiles?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true)
    $TrafficProfile = $Profiles | Where-Object { $_.trafficForwardingType -eq 'm365' -and $_.isCustomProfile -ne $true } | Select-Object -First 1
    if (-not $TrafficProfile) { throw 'The Microsoft 365 traffic forwarding profile was not found; run the standard again in a few minutes.' }
    if ($TrafficProfile.state -ne 'enabled') {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"enabled"}' -AsApp $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Enabled the Microsoft 365 traffic forwarding profile.' -Sev 'Info'
        $Changed = $true
        $Refresh.Add('NetworkAccess')
    }
    foreach ($Link in @($TrafficProfile.policies | Where-Object { $_.state -ne 'enabled' })) {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)/policies/$($Link.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"enabled"}' -AsApp $true
        $Changed = $true
        $Refresh.Add('NetworkAccess')
    }
    $SpId = $TrafficProfile.servicePrincipal.id
    if ($SpId) {
        $Sp = New-GraphGetRequest -uri "$Graph/servicePrincipals/$SpId`?`$select=id,appRoleAssignmentRequired" -tenantid $TenantFilter -AsApp $true
        if ($Sp.appRoleAssignmentRequired -ne $false) {
            $null = New-GraphPostRequest -uri "$Graph/servicePrincipals/$SpId" -tenantid $TenantFilter -type PATCH -body '{"appRoleAssignmentRequired":false}' -AsApp $true
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Assigned the Microsoft 365 traffic forwarding profile to all users.' -Sev 'Info'
            $Changed = $true
            $Refresh.Add('NetworkAccess')
        }
    }
    $Settings = New-GraphGetRequest -uri "$Graph/networkAccess/settings/conditionalAccess" -tenantid $TenantFilter -AsApp $true
    if ($Settings.signalingStatus -ne 'enabled') {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/settings/conditionalAccess" -tenantid $TenantFilter -type PATCH -body '{"signalingStatus":"enabled"}' -AsApp $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Enabled Global Secure Access signaling for Conditional Access.' -Sev 'Info'
        $Changed = $true
        $Refresh.Add('NetworkAccess')
    }
    # The settings PATCH does not create the named location; the admin center POSTs it separately.
    $Location = New-GraphGetRequest -uri "$Graph/identity/conditionalAccess/namedLocations" -tenantid $TenantFilter -AsApp $true | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.compliantNetworkNamedLocation' } | Select-Object -First 1
    if (-not $Location) {
        $Body = '{"@odata.type":"#microsoft.graph.compliantNetworkNamedLocation","displayName":"All Compliant Network Locations","compliantNetworkType":"allTenantCompliantNetworks","isTrusted":false}'
        $Location = New-GraphPostRequest -uri "$Graph/identity/conditionalAccess/namedLocations" -tenantid $TenantFilter -type POST -body $Body -AsApp $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Created the All Compliant Network Locations named location.' -Sev 'Info'
        $Changed = $true
        $Refresh.Add('ConditionalAccessPolicies')
    }

    # --- Windows: Win32 script app
    if ($DeployWindows) {
        $Install = @'
$ErrorActionPreference = 'Stop'
$WorkDir = Join-Path $env:ProgramData 'CIPPApps\GlobalSecureAccess'
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$ExitCode = 0
$ProgramFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$Url = if ($Arch -eq 'ARM64') { 'https://aka.ms/GlobalSecureAccess-WindowsOnArm' } else { 'https://aka.ms/GlobalSecureAccess-windows' }
if (-not (Test-Path (Join-Path $ProgramFiles 'Global Secure Access Client\TrayApp\GlobalSecureAccessClient.exe'))) {
    $Installer = Join-Path $WorkDir 'GlobalSecureAccessClient.exe'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
    $Process = Start-Process -FilePath $Installer -ArgumentList '/quiet /norestart' -Wait -PassThru
    if ($Process.ExitCode -eq 1618) { exit 1618 }
    if ($Process.ExitCode -eq 3010) { $ExitCode = 3010 } elseif ($Process.ExitCode -ne 0) { exit $Process.ExitCode }
}
$Key = 'HKLM:\SOFTWARE\Microsoft\Global Secure Access Client'
if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
foreach ($Name in 'HideDisableButton', 'HideSignOutButton', 'HideDisablePrivateAccessButton', 'RestrictNonPrivilegedUsers') {
    Set-ItemProperty -Path $Key -Name $Name -Value LOCKDOWN -Type DWord -Force
}
if (PREFERIPV4) {
    $Ipv6 = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    if ((Get-ItemProperty -Path $Ipv6 -Name DisabledComponents -ErrorAction SilentlyContinue).DisabledComponents -ne 0x20) {
        Set-ItemProperty -Path $Ipv6 -Name DisabledComponents -Value 0x20 -Type DWord -Force
        $ExitCode = 3010
    }
}
exit $ExitCode
'@
        $Uninstall = @'
$Installer = Join-Path $env:ProgramData 'CIPPApps\GlobalSecureAccess\GlobalSecureAccessClient.exe'
if (-not (Test-Path $Installer)) {
    $Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $Url = if ($Arch -eq 'ARM64') { 'https://aka.ms/GlobalSecureAccess-WindowsOnArm' } else { 'https://aka.ms/GlobalSecureAccess-windows' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
}
$Process = Start-Process -FilePath $Installer -ArgumentList '/uninstall /quiet /norestart' -Wait -PassThru
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Global Secure Access Client' -Recurse -Force -ErrorAction SilentlyContinue
exit $Process.ExitCode
'@
        $Detection = @'
$ProgramFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
if (-not (Test-Path (Join-Path $ProgramFiles 'Global Secure Access Client\TrayApp\GlobalSecureAccessClient.exe'))) { exit 1 }
$Key = 'HKLM:\SOFTWARE\Microsoft\Global Secure Access Client'
foreach ($Name in 'HideDisableButton', 'HideSignOutButton', 'HideDisablePrivateAccessButton', 'RestrictNonPrivilegedUsers') {
    if ((Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue).$Name -ne LOCKDOWN) { exit 1 }
}
Write-Output 'Installed'
exit 0
'@
        $Install = $Install.Replace('LOCKDOWN', "$LockDown").Replace('PREFERIPV4', $(if ($PreferIPv4) { '$true' } else { '$false' }))
        $Detection = $Detection.Replace('LOCKDOWN', "$LockDown")
        $AppName = 'Global Secure Access Client (Windows)'
        $AppHash = & $Hash ($Install + $Detection)
        $Baseuri = "$Graph/deviceAppManagement/mobileApps"
        $Existing = @(New-GraphGetRequest -uri "$Baseuri`?`$filter=displayName eq '$AppName'&`$select=id,displayName,description" -tenantid $TenantFilter | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.win32LobApp' })
        if ($Existing.Count -eq 0 -or "$($Existing[0].description)" -notmatch "\[cfg:$AppHash\]") {
            foreach ($App in $Existing) { $null = New-GraphPostRequest -uri "$Baseuri/$($App.id)" -type DELETE -tenantid $TenantFilter }
            if ($Existing.Count -gt 0) { Start-Sleep -Seconds 2 }
            $NewApp = Add-CIPPW32ScriptApplication -TenantFilter $TenantFilter -Properties ([PSCustomObject]@{
                    displayName           = $AppName
                    description           = "Installs the Microsoft Global Secure Access client and its hardening settings. Managed by CIPP. [cfg:$AppHash]"
                    publisher             = 'Microsoft'
                    installScript         = $Install
                    uninstallScript       = $Uninstall
                    detectionScript       = $Detection
                    runAsAccount          = 'system'
                    deviceRestartBehavior = 'basedOnReturnCode'
                })
            if ($NewApp -and $AssignTo -ne 'On') {
                Start-Sleep -Milliseconds 500
                $null = Set-CIPPAssignedApplication -ApplicationId $NewApp.Id -TenantFilter $TenantFilter -GroupName $AssignTo -ExcludeGroup $ExcludeGroup -Intent 'Required' -AppType 'Win32Lob' -APIName 'Baselines'
            }
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed $AppName." -Sev 'Info'
            $Changed = $true
            $Refresh.Add('IntuneMobileApps')
        }
    }

    # --- macOS: shell script plus the three profiles Microsoft requires
    if ($DeployMacOS) {
        $MacScript = @'
#!/bin/bash
MARKER="/Library/Application Support/CIPP/GlobalSecureAccess.cfg"
if [ -d "/Applications/GlobalSecureAccessClient" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "CONFIGHASH" ]; then exit 0; fi
curl -L --fail --silent --show-error -o /tmp/GlobalSecureAccessClient.pkg "https://aka.ms/GlobalSecureAccess-macOS" || exit 1
/usr/sbin/installer -pkg /tmp/GlobalSecureAccessClient.pkg -target / || { rm -f /tmp/GlobalSecureAccessClient.pkg; exit 1; }
rm -f /tmp/GlobalSecureAccessClient.pkg
mkdir -p "$(dirname "$MARKER")" && echo "CONFIGHASH" > "$MARKER"
exit 0
'@
        $ScriptHash = & $Hash $MacScript
        $MacScript = $MacScript.Replace('CONFIGHASH', $ScriptHash)
        $ScriptName = 'Global Secure Access Client (macOS)'
        $ExistingScript = New-GraphGetRequest -uri "$Graph/deviceManagement/deviceShellScripts?`$select=id,displayName,description&`$expand=assignments" -tenantid $TenantFilter | Where-Object { $_.displayName -eq $ScriptName } | Select-Object -First 1
        $Unassigned = @($ExistingScript.assignments | Where-Object { $_ }).Count -eq 0
        if (-not $ExistingScript -or "$($ExistingScript.description)" -notmatch "\[cfg:$ScriptHash\]" -or $Unassigned) {
            $Script = Add-CIPPMacOSShellScript -TenantFilter $TenantFilter -DisplayName $ScriptName -Description "Installs the Microsoft Global Secure Access client; re-runs daily. Managed by CIPP. [cfg:$ScriptHash]" -ScriptContent $MacScript -ExecutionFrequency 'P1D'
            if ($PolicyAssignTo -ne 'On' -and $Unassigned) {
                $null = Set-CIPPAssignedPolicy -PolicyId $Script.id -Type 'deviceShellScripts' -GroupName $PolicyAssignTo -ExcludeGroup $ExcludeGroup -TenantFilter $TenantFilter -AssignmentMode 'replace' -APIName 'Baselines'
            }
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed $ScriptName." -Sev 'Info'
            $Changed = $true
            $Refresh.Add('IntuneScripts')
        }

        $Str = { param($Value) @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'; value = $Value } }
        $Extensions = @{
            name            = 'Global Secure Access - macOS System Extensions'
            description     = ''
            platforms       = 'macOS'
            technologies    = 'mdm'
            roleScopeTagIds = @('0')
            settings        = @(@{
                    '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                    settingInstance = @{
                        '@odata.type'               = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                        settingDefinitionId         = 'com.apple.system-extension-policy_allowedsystemextensions'
                        groupSettingCollectionValue = @(@{
                                '@odata.type' = '#microsoft.graph.deviceManagementConfigurationGroupSettingValue'
                                children      = @(
                                    @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'; settingDefinitionId = 'com.apple.system-extension-policy_allowedsystemextensions_generickey_keytobereplaced'; simpleSettingValue = (& $Str 'UBF8T346G9') }
                                    @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'; settingDefinitionId = 'com.apple.system-extension-policy_allowedsystemextensions_generickey'; simpleSettingCollectionValue = @((& $Str 'com.microsoft.globalsecureaccess.tunnel'), (& $Str 'com.microsoft.globalsecureaccess')) }
                                )
                            })
                    }
                })
        }
        $ProxyPlist = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>PayloadUUID</key><string>87cbb424-6af7-4748-9d43-f1c5dda7a0a6</string>
<key>PayloadType</key><string>Configuration</string>
<key>PayloadOrganization</key><string>Microsoft Corporation</string>
<key>PayloadIdentifier</key><string>com.microsoft.globalsecureaccess</string>
<key>PayloadDisplayName</key><string>Global Secure Access Proxy Configuration</string>
<key>PayloadVersion</key><integer>1</integer>
<key>PayloadEnabled</key><true/>
<key>PayloadRemovalDisallowed</key><true/>
<key>PayloadScope</key><string>System</string>
<key>PayloadContent</key><array><dict>
<key>PayloadUUID</key><string>04e13063-2bb8-4b72-b1ed-45290f91af68</string>
<key>PayloadType</key><string>com.apple.vpn.managed</string>
<key>PayloadOrganization</key><string>Microsoft Corporation</string>
<key>PayloadIdentifier</key><string>com.microsoft.globalsecureaccess</string>
<key>PayloadDisplayName</key><string>Global Secure Access Proxy Configuration</string>
<key>PayloadVersion</key><integer>1</integer>
<key>TransparentProxy</key><dict>
<key>AuthenticationMethod</key><string>Password</string>
<key>Order</key><integer>1</integer>
<key>ProviderBundleIdentifier</key><string>com.microsoft.globalsecureaccess.tunnel</string>
<key>ProviderDesignatedRequirement</key><string>identifier "com.microsoft.globalsecureaccess.tunnel" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = UBF8T346G9</string>
<key>ProviderType</key><string>app-proxy</string>
<key>RemoteAddress</key><string>100.64.0.0</string>
</dict>
<key>UserDefinedName</key><string>Global Secure Access Proxy Configuration</string>
<key>VPNSubType</key><string>com.microsoft.globalsecureaccess</string>
<key>VPNType</key><string>TransparentProxy</string>
</dict></array></dict></plist>
'@
        $Bool = if ($LockDown) { '<true/>' } else { '<false/>' }
        $SettingsPlist = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<!DOCTYPE plist PUBLIC `"-//Apple//DTD PLIST 1.0//EN`" `"http://www.apple.com/DTDs/PropertyList-1.0.dtd`">`n<plist version=`"1.0`"><dict><key>HideDisableButton</key>$Bool<key>HidePauseButton</key>$Bool<key>HideDisablePrivateAccessButton</key>$Bool<key>HideQuitButton</key><true/></dict></plist>"
        $MacProfiles = @(
            @{ Type = 'Catalog'; Name = 'Global Secure Access - macOS System Extensions'; Body = $Extensions }
            @{ Type = 'Device'; Name = 'Global Secure Access - macOS Transparent Proxy'; Body = @{ '@odata.type' = '#microsoft.graph.macOSCustomConfiguration'; displayName = 'Global Secure Access - macOS Transparent Proxy'; payloadName = 'Global Secure Access Proxy Configuration'; payloadFileName = 'GlobalSecureAccessProxy.mobileconfig'; payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ProxyPlist)); deploymentChannel = 'deviceChannel' } }
            @{ Type = 'Device'; Name = 'Global Secure Access - macOS Client Settings'; Body = @{ '@odata.type' = '#microsoft.graph.macOSCustomAppConfiguration'; displayName = 'Global Secure Access - macOS Client Settings'; bundleId = 'com.microsoft.globalsecureaccess'; fileName = 'com.microsoft.globalsecureaccess.plist'; configurationXml = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SettingsPlist)) } }
        )
        $LiveCatalog = @(New-GraphGetRequest -uri "$Graph/deviceManagement/configurationPolicies?`$select=id,name,description&`$top=1000" -tenantid $TenantFilter)
        $LiveConfigs = @(New-GraphGetRequest -uri "$Graph/deviceManagement/deviceConfigurations?`$select=id,displayName,description&`$top=999" -tenantid $TenantFilter)
        foreach ($MacProfile in $MacProfiles) {
            $Json = $MacProfile.Body | ConvertTo-Json -Depth 20 -Compress
            $ProfileHash = & $Hash $Json
            $Description = "Required for the Global Secure Access client on macOS. Managed by CIPP. [cfg:$ProfileHash]"
            $Live = if ($MacProfile.Type -eq 'Catalog') { $LiveCatalog | Where-Object { $_.name -eq $MacProfile.Name } } else { $LiveConfigs | Where-Object { $_.displayName -eq $MacProfile.Name } }
            if ($Live -and "$(@($Live)[0].description)" -match "\[cfg:$ProfileHash\]") { continue }
            if ($MacProfile.Type -eq 'Catalog') { $MacProfile.Body.description = $Description; $Json = $MacProfile.Body | ConvertTo-Json -Depth 20 -Compress }
            $Params = @{ TemplateType = $MacProfile.Type; DisplayName = $MacProfile.Name; Description = $Description; RawJSON = $Json; TenantFilter = $TenantFilter; APIName = 'Baselines'; AssignmentMode = 'replace' }
            if ($PolicyAssignTo -ne 'On') { $Params.AssignTo = $PolicyAssignTo; $Params.ExcludeGroup = $ExcludeGroup }
            $null = Set-CIPPIntunePolicy @Params
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed $($MacProfile.Name)." -Sev 'Info'
            $Changed = $true
            $Refresh.Add($(if ($MacProfile.Type -eq 'Catalog') { 'IntuneConfigurationPolicies' } else { 'IntunePolicies' }))
        }
    }

    # --- Conditional Access policy, written only when the hook saw drift on it
    if ($Current.policyDrift -ne $false) {
        $ExcludeUsers = [System.Collections.Generic.List[string]]::new()
        $ExcludeGroups = [System.Collections.Generic.List[string]]::new()
        if ($UserRefs.Count -gt 0) {
            $Users = @(New-GraphGetRequest -uri "$Graph/users?`$select=id,displayName,userPrincipalName&`$top=999" -tenantid $TenantFilter -AsApp $true)
            foreach ($Ref in $UserRefs) {
                $Match = $Users | Where-Object { $_.id -eq $Ref -or $_.userPrincipalName -eq $Ref -or $_.displayName -eq $Ref } | Select-Object -First 1
                if ($Match) { $ExcludeUsers.Add($Match.id) } else { Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Break-glass account '$Ref' was not found and could not be excluded." -Sev 'Warning' }
            }
        }
        if ($GroupRefs.Count -gt 0) {
            $Groups = @(New-GraphGetRequest -uri "$Graph/groups?`$select=id,displayName&`$top=999" -tenantid $TenantFilter -AsApp $true)
            foreach ($Ref in $GroupRefs) {
                $Match = $Groups | Where-Object { $_.id -eq $Ref -or $_.displayName -eq $Ref } | Select-Object -First 1
                if ($Match) { $ExcludeGroups.Add($Match.id) } else { Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Group '$Ref' was not found and could not be excluded." -Sev 'Warning' }
            }
        }
        if ($Remediate.useDetectedBreakGlass -ne $false) {
            $Others = @(New-GraphGetRequest -uri "$Graph/identity/conditionalAccess/policies?`$top=999" -tenantid $TenantFilter -AsApp $true | Where-Object { $_.displayName -ne 'CIPP: Require compliant network (Global Secure Access)' })
            $Candidate = Get-CIPPCABreakGlassCandidate -Policies $Others
            if ($Candidate.id) {
                if ($Candidate.type -eq 'group') { if ($ExcludeGroups -notcontains $Candidate.id) { $ExcludeGroups.Add($Candidate.id) } }
                elseif ($ExcludeUsers -notcontains $Candidate.id) { $ExcludeUsers.Add($Candidate.id) }
            }
        }
        if ($Enforce -and $ExcludeUsers.Count -eq 0 -and $ExcludeGroups.Count -eq 0) {
            throw 'Refusing to enable the compliant network policy with no break-glass exclusion: it would lock out every account on a device without the client. Add a break-glass account or keep report-only mode.'
        }
        $ExcludeApps = [System.Collections.Generic.List[string]]@('d4ebce55-015a-49b5-a083-c84d1797ae8c', '0000000a-0000-0000-c000-000000000000')
        foreach ($Efp in @(New-GraphGetRequest -uri "$Graph/servicePrincipals?`$filter=displayName eq 'GSA-ExplicitForwardProxy'&`$select=appId" -tenantid $TenantFilter -AsApp $true)) { $ExcludeApps.Add($Efp.appId) }
        $State = if ($Enforce) { 'enabled' } else { 'enabledForReportingButNotEnforced' }
        $Policy = @{
            displayName   = 'CIPP: Require compliant network (Global Secure Access)'
            state         = $State
            conditions    = @{
                users          = @{ includeUsers = @('All'); excludeUsers = @($ExcludeUsers); includeGroups = @(); excludeGroups = @($ExcludeGroups); includeRoles = @(); excludeRoles = @($RoleIds) }
                applications   = @{ includeApplications = @('All'); excludeApplications = @($ExcludeApps); includeUserActions = @() }
                locations      = @{ includeLocations = @('All'); excludeLocations = @("$($Location.id)") }
                clientAppTypes = @('all')
            }
            grantControls = @{ operator = 'OR'; builtInControls = @('block') }
        } | ConvertTo-Json -Depth 10
        $null = New-CIPPCAPolicy -RawJSON $Policy -TenantFilter $TenantFilter -State $State -Overwrite $true -ReplacePattern 'none' -APIName 'Baselines'
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed the compliant network policy ($State) with $($ExcludeUsers.Count) excluded user(s), $($ExcludeGroups.Count) excluded group(s), $($RoleIds.Count) excluded role(s)." -Sev 'Info'
        $Changed = $true
        $Refresh.Add('ConditionalAccessPolicies')
    }

    # Refresh the caches this run wrote to, so the next compare does not read the old copies as drift.
    foreach ($CacheType in ($Refresh | Sort-Object -Unique)) {
        $Collector = Get-Command -Name "Set-CIPPDBCache$CacheType" -ErrorAction SilentlyContinue
        if ($Collector) {
            try { $null = & $Collector -TenantFilter $TenantFilter } catch { Write-Information "Baselines: $CacheType cache refresh on $TenantFilter failed: $($_.Exception.Message)" }
        }
    }

    if (-not $Changed) { return [PSCustomObject]@{ Changed = $false } }
}
