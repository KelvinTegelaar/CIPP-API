function Get-CIPPBaselineDefenderASRPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for DefenderASRPolicy: the 'ASR Default rules' settings catalog policy.
    .DESCRIPTION
        Parses the attack surface reduction rules group from the cached policy exactly as the
        classic did: a rule PRESENT in the group counts as enabled (its individual mode is not
        graded per rule), and the policy mode is the FIRST rule's mode. Rules the baseline
        turns off must be absent from the group or they grade as drift.
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
    $Policy = @($Policies | Where-Object { "$($_.name)" -eq 'ASR Default rules' }) | Select-Object -First 1

    $ASRPrefix = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
    $ASRRuleDefMap = @{
        'blockexecutionofpotentiallyobfuscatedscripts'                               = 'blockObfuscatedScripts'
        'blockadobereaderfromcreatingchildprocesses'                                 = 'blockAdobeChild'
        'blockwin32apicallsfromofficemacros'                                         = 'blockWin32Macro'
        'blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem'          = 'blockCredentialStealing'
        'blockprocesscreationsfrompsexecandwmicommands'                              = 'blockPSExec'
        'blockpersistencethroughwmieventsubscription'                                = 'wmiPersistence'
        'blockuseofcopiedorimpersonatedsystemtools'                                  = 'blockSystemTools'
        'blockofficeapplicationsfromcreatingexecutablecontent'                       = 'blockOfficeExes'
        'blockofficeapplicationsfrominjectingcodeintootherprocesses'                 = 'blockOfficeApps'
        'blockrebootingmachineinsafemode'                                            = 'blockSafeMode'
        'blockexecutablefilesrunningunlesstheymeetprevalenceagetrustedlistcriterion' = 'blockYoungExe'
        'blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent'          = 'blockJSVB'
        'blockwebshellcreationforservers'                                            = 'blockWebshellForServers'
        'blockofficecommunicationappfromcreatingchildprocesses'                      = 'blockOfficeComChild'
        'blockallofficeapplicationsfromcreatingchildprocesses'                       = 'blockOfficeChild'
        'blockuntrustedunsignedprocessesthatrunfromusb'                              = 'blockUntrustedUSB'
        'useadvancedprotectionagainstransomware'                                     = 'enableRansomwareVac'
        'blockexecutablecontentfromemailclientandwebmail'                            = 'blockExesMail'
        'blockabuseofexploitedvulnerablesigneddrivers'                               = 'blockUnsignedDrivers'
    }
    # Definition variable name (PascalCase-ish, as the classic declared them) per graded key.
    $VariableNameMap = @{
        blockObfuscatedScripts = 'BlockObfuscatedScripts'; blockAdobeChild = 'BlockAdobeChild'; blockWin32Macro = 'BlockWin32Macro'
        blockCredentialStealing = 'BlockCredentialStealing'; blockPSExec = 'BlockPSExec'; wmiPersistence = 'WMIPersistence'
        blockSystemTools = 'BlockSystemTools'; blockOfficeExes = 'BlockOfficeExes'; blockOfficeApps = 'BlockOfficeApps'
        blockSafeMode = 'BlockSafeMode'; blockYoungExe = 'BlockYoungExe'; blockJSVB = 'blockJSVB'
        blockWebshellForServers = 'BlockWebshellForServers'; blockOfficeComChild = 'blockOfficeComChild'; blockOfficeChild = 'blockOfficeChild'
        blockUntrustedUSB = 'BlockUntrustedUSB'; enableRansomwareVac = 'EnableRansomwareVac'; blockExesMail = 'BlockExesMail'
        blockUnsignedDrivers = 'BlockUnsignedDrivers'
    }

    $CurrentRules = @{}
    $CurrentMode = ''
    foreach ($Setting in @($Policy.settings)) {
        $Instance = $Setting.settingInstance
        if ("$($Instance.settingDefinitionId)" -eq $ASRPrefix -and $Instance.groupSettingCollectionValue) {
            foreach ($Child in @(@($Instance.groupSettingCollectionValue)[0].children)) {
                $RuleSuffix = "$($Child.settingDefinitionId)" -replace "^${ASRPrefix}_", ''
                if ($ASRRuleDefMap.ContainsKey($RuleSuffix)) {
                    $CurrentRules[$ASRRuleDefMap[$RuleSuffix]] = $true
                    if (-not $CurrentMode) { $CurrentMode = ("$($Child.choiceSettingValue.value)" -split '_')[-1] }
                }
            }
        }
    }

    $V = $Item.Variables
    $Expected = [ordered]@{
        policyExists = $true
        mode         = [string]($V.Mode.value ?? $V.Mode ?? 'block')
    }
    $Current = [ordered]@{
        policyExists = ($null -ne $Policy)
        mode         = [string]$CurrentMode
    }
    foreach ($Rule in $VariableNameMap.Keys | Sort-Object) {
        $Expected[$Rule] = [bool]$V.($VariableNameMap[$Rule])
        $Current[$Rule] = [bool]$CurrentRules[$Rule]
    }

    $CurrentObject = [PSCustomObject]$Current
    # Carried for the executor.
    $CurrentObject | Add-Member -NotePropertyName 'policyId' -NotePropertyValue "$($Policy.id)"

    @{
        Expected = [PSCustomObject]$Expected
        Current  = $CurrentObject
    }
}
