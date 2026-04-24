function Invoke-CIPPStandardDefenderASRPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefenderASRPolicy
    .SYNOPSIS
        (Label) Defender Attack Surface Reduction Rules
    .DESCRIPTION
        (Helptext) Deploys and enforces Microsoft Defender Attack Surface Reduction (ASR) rules via Intune. Controls 20 individual ASR rules that protect against common attack vectors including obfuscated scripts, Office macro abuse, credential theft, ransomware, and more.
        (DocsDescription) Deploys a standardised set of Attack Surface Reduction rules through Intune configuration policies. ASR rules reduce the attack surface of your applications by preventing the actions that malware often abuses. Rules can be set to Block, Audit, or Warn mode. Individual rules cover script obfuscation, Adobe child processes, Office macro exploitation, credential stealing from LSASS, PSExec/WMI abuse, WMI persistence, unsafe executables, webshell creation, and many more attack vectors.
    .NOTES
        CAT
            Defender Standards
        TAG
            "defender_asr"
            "defender_attack_surface_reduction"
            "intune_endpoint_protection"
        ADDEDCOMPONENT
            {"type":"radio","name":"standards.DefenderASRPolicy.Mode","label":"ASR Rules Mode","options":[{"label":"Block","value":"block"},{"label":"Audit","value":"audit"},{"label":"Warn","value":"warn"}]}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockObfuscatedScripts","label":"Block execution of obfuscated scripts","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockAdobeChild","label":"Block Adobe Reader from creating child processes","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockWin32Macro","label":"Block Win32 API calls from Office macros","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockCredentialStealing","label":"Block credential stealing from LSASS","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockPSExec","label":"Block process creations from PSExec and WMI","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.WMIPersistence","label":"Block persistence through WMI event subscription","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockSystemTools","label":"Block use of copied or impersonated system tools","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockOfficeExes","label":"Block Office apps from creating executable content","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockOfficeApps","label":"Block Office apps from injecting code into other processes","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockSafeMode","label":"Block rebooting machine in safe mode","defaultValue":false}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockYoungExe","label":"Block executables that do not meet prevalence/age/trusted list criteria","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.blockJSVB","label":"Block JavaScript or VBScript from launching downloads","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockWebshellForServers","label":"Block webshell creation for servers","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.blockOfficeComChild","label":"Block Office Communication app child processes","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.blockOfficeChild","label":"Block all Office apps from creating child processes","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockUntrustedUSB","label":"Block untrusted/unsigned processes from USB","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.EnableRansomwareVac","label":"Use advanced protection against ransomware","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockExesMail","label":"Block executable content from email client and webmail","defaultValue":true}
            {"type":"switch","name":"standards.DefenderASRPolicy.BlockUnsignedDrivers","label":"Block abuse of exploited vulnerable signed drivers","defaultValue":true}
            {"type":"radio","name":"standards.DefenderASRPolicy.AssignTo","label":"Policy Assignment","options":[{"label":"Do not assign","value":"none"},{"label":"All users","value":"allLicensedUsers"},{"label":"All devices","value":"AllDevices"},{"label":"All users and devices","value":"AllDevicesAndUsers"}]}
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

    $PolicyName = 'ASR Default rules'

    # Reverse mapping: settingDefinitionId suffix -> property name
    $ASRPrefix = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
    $ASRRuleDefMap = @{
        'blockexecutionofpotentiallyobfuscatedscripts'                               = 'BlockObfuscatedScripts'
        'blockadobereaderfromcreatingchildprocesses'                                 = 'BlockAdobeChild'
        'blockwin32apicallsfromofficemacros'                                         = 'BlockWin32Macro'
        'blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem'          = 'BlockCredentialStealing'
        'blockprocesscreationsfrompsexecandwmicommands'                              = 'BlockPSExec'
        'blockpersistencethroughwmieventsubscription'                                = 'WMIPersistence'
        'blockuseofcopiedorimpersonatedsystemtools'                                  = 'BlockSystemTools'
        'blockofficeapplicationsfromcreatingexecutablecontent'                       = 'BlockOfficeExes'
        'blockofficeapplicationsfrominjectingcodeintootherprocesses'                 = 'BlockOfficeApps'
        'blockrebootingmachineinsafemode'                                            = 'BlockSafeMode'
        'blockexecutablefilesrunningunlesstheymeetprevalenceagetrustedlistcriterion' = 'BlockYoungExe'
        'blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent'          = 'blockJSVB'
        'blockwebshellcreationforservers'                                            = 'BlockWebshellForServers'
        'blockofficecommunicationappfromcreatingchildprocesses'                      = 'blockOfficeComChild'
        'blockallofficeapplicationsfromcreatingchildprocesses'                       = 'blockOfficeChild'
        'blockuntrustedunsignedprocessesthatrunfromusb'                              = 'BlockUntrustedUSB'
        'useadvancedprotectionagainstransomware'                                     = 'EnableRansomwareVac'
        'blockexecutablecontentfromemailclientandwebmail'                            = 'BlockExesMail'
        'blockabuseofexploitedvulnerablesigneddrivers'                               = 'BlockUnsignedDrivers'
    }

    $ExpectedMode = $Settings.Mode ?? 'block'
    $AllRuleProps = @('BlockObfuscatedScripts', 'BlockAdobeChild', 'BlockWin32Macro', 'BlockCredentialStealing',
        'BlockPSExec', 'WMIPersistence', 'BlockSystemTools', 'BlockOfficeExes', 'BlockOfficeApps', 'BlockSafeMode',
        'BlockYoungExe', 'blockJSVB', 'BlockWebshellForServers', 'blockOfficeComChild', 'blockOfficeChild',
        'BlockUntrustedUSB', 'EnableRansomwareVac', 'BlockExesMail', 'BlockUnsignedDrivers')

    # Build expected values
    $ExpectedHash = [ordered]@{
        PolicyExists = $true
        Mode         = $ExpectedMode
    }
    foreach ($rule in $AllRuleProps) {
        $ExpectedHash[$rule] = [bool]$Settings.$rule
    }
    $ExpectedValue = [PSCustomObject]$ExpectedHash

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

    # Parse current ASR rules from the policy
    $CurrentRules = @{}
    $CurrentMode = ''
    if ($PolicyExists) {
        try {
            $PolicyDetail = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')?`$expand=settings" -tenantid $Tenant
            foreach ($setting in $PolicyDetail.settings) {
                $instance = $setting.settingInstance
                if ($instance.settingDefinitionId -eq $ASRPrefix -and $instance.groupSettingCollectionValue) {
                    foreach ($child in $instance.groupSettingCollectionValue[0].children) {
                        $childDefId = $child.settingDefinitionId
                        $ruleSuffix = $childDefId -replace "^${ASRPrefix}_", ''
                        $mode = ($child.choiceSettingValue.value -split '_')[-1]

                        if ($ASRRuleDefMap.ContainsKey($ruleSuffix)) {
                            $CurrentRules[$ASRRuleDefMap[$ruleSuffix]] = $true
                            if (-not $CurrentMode) { $CurrentMode = $mode }
                        }
                    }
                }
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to read ASR Policy settings: $($_.Exception.Message)" -sev Warning
        }
    }

    $CurrentHash = [ordered]@{
        PolicyExists = $PolicyExists
        Mode         = if ($CurrentMode) { $CurrentMode } else { '' }
    }
    foreach ($rule in $AllRuleProps) {
        $CurrentHash[$rule] = [bool]$CurrentRules[$rule]
    }
    $CurrentValue = [PSCustomObject]$CurrentHash

    # Field-by-field comparison
    $StateIsCorrect = $PolicyExists
    if ($PolicyExists) {
        if ($CurrentMode -ne $ExpectedMode) { $StateIsCorrect = $false }
        if ($StateIsCorrect) {
            foreach ($rule in $AllRuleProps) {
                if ([bool]$CurrentRules[$rule] -ne [bool]$Settings.$rule) {
                    $StateIsCorrect = $false
                    break
                }
            }
        }
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender ASR Policy already correctly configured' -sev Info
        } else {
            try {
                # Delete existing drifted policy so the helper can recreate
                if ($PolicyExists) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')" -tenantid $Tenant -type DELETE
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Deleted drifted Defender ASR Policy for recreation' -sev Info
                }

                $ASRSettings = @{
                    Mode                    = $ExpectedMode
                    BlockObfuscatedScripts  = [bool]$Settings.BlockObfuscatedScripts
                    BlockAdobeChild         = [bool]$Settings.BlockAdobeChild
                    BlockWin32Macro         = [bool]$Settings.BlockWin32Macro
                    BlockCredentialStealing = [bool]$Settings.BlockCredentialStealing
                    BlockPSExec             = [bool]$Settings.BlockPSExec
                    WMIPersistence          = [bool]$Settings.WMIPersistence
                    BlockSystemTools        = [bool]$Settings.BlockSystemTools
                    BlockOfficeExes         = [bool]$Settings.BlockOfficeExes
                    BlockOfficeApps         = [bool]$Settings.BlockOfficeApps
                    BlockSafeMode           = [bool]$Settings.BlockSafeMode
                    BlockYoungExe           = [bool]$Settings.BlockYoungExe
                    blockJSVB               = [bool]$Settings.blockJSVB
                    BlockWebshellForServers = [bool]$Settings.BlockWebshellForServers
                    blockOfficeComChild     = [bool]$Settings.blockOfficeComChild
                    blockOfficeChild        = [bool]$Settings.blockOfficeChild
                    BlockUntrustedUSB       = [bool]$Settings.BlockUntrustedUSB
                    EnableRansomwareVac     = [bool]$Settings.EnableRansomwareVac
                    BlockExesMail           = [bool]$Settings.BlockExesMail
                    BlockUnsignedDrivers    = [bool]$Settings.BlockUnsignedDrivers
                    AssignTo                = $Settings.AssignTo ?? 'none'
                }

                $Result = Set-CIPPDefenderASRPolicy -TenantFilter $Tenant -ASR $ASRSettings -APIName 'Standards'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Defender ASR Policy: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender ASR Policy is correctly configured' -sev Info
        } else {
            Write-StandardsAlert -message 'Defender ASR Policy is not correctly configured' -object $CurrentValue -tenant $Tenant -standardName 'DefenderASRPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender ASR Policy is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DefenderASRPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DefenderASRPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
