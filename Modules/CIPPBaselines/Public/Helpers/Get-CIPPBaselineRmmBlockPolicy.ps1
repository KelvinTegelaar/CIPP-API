function Get-CIPPBaselineRmmBlockPolicy {
    <#
    .SYNOPSIS
        Builds the Intune policy that blocks RMM and remote access tools on one platform, from
        Config/RmmBlockList.json.
    .DESCRIPTION
        Windows gets an App Control for Business deny policy that matches each tool's file names and
        folders. macOS gets a settings catalog policy that denies each tool's code signature.

        A tool in AllowedTools is left out. A rule shared by several tools is left out when any of
        them is allowed, otherwise the allowed tool would still be blocked. A name that is not in the
        list throws, so a tool that was renamed in the list cannot silently become blocked.

        The fingerprint covers the rules and the assignment and is written into the policy
        description, which is how a later run sees that the deployed policy is out of date.

        Returns nothing when no rule is left for the platform.

        The tool list and the approach come from RMM Guard (https://rmmguard.com) by Lewis Barry and
        Roy Klooster, https://github.com/Lewis-Barry/RMM-Blocker
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows', 'macOS')]
        [string]$Platform,
        [string[]]$AllowedTools = @(),
        [string]$AssignmentKey = '',
        [string]$ListPath = (Join-Path $env:CIPPRootPath 'Config\RmmBlockList.json')
    )

    $List = Get-Content -Path $ListPath -Raw -ErrorAction Stop | ConvertFrom-Json
    $Products = @($List.products.PSObject.Properties)

    $Allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Known = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Products.Name), [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Tool in $AllowedTools) {
        if ([string]::IsNullOrWhiteSpace($Tool)) { continue }
        if (-not $Known.Contains($Tool.Trim())) {
            throw [System.ArgumentException]::new("'$($Tool.Trim())' is not in the RMM block list (version $($List.version)). Pick the tool again in the baseline.")
        }
        $null = $Allowed.Add($Tool.Trim())
    }

    # One entry per rule, with every tool that owns it.
    $Rules = [ordered]@{}
    foreach ($Product in $Products) {
        $Sources = if ($Platform -eq 'Windows') { $Product.Value.paths } else { $Product.Value.macos.rules }
        foreach ($Source in @($Sources)) {
            if (-not $Source) { continue }
            $Key = if ($Platform -eq 'Windows') { "$Source".ToLowerInvariant() } else { "$($Source.teamId) $($Source.signingId)" }
            if (-not $Rules.Contains($Key)) {
                $Rules[$Key] = if ($Platform -eq 'Windows') {
                    [PSCustomObject]@{ Key = $Key; Path = "$Source"; Owners = [System.Collections.Generic.List[string]]::new() }
                } else {
                    [PSCustomObject]@{ Key = $Key; TeamId = "$($Source.teamId)"; SigningId = "$($Source.signingId)"; Owners = [System.Collections.Generic.List[string]]::new() }
                }
            }
            $Rules[$Key].Owners.Add($Product.Name)
        }
    }
    $Kept = @(foreach ($Rule in $Rules.Values) { if ($Rule.Owners.Where({ $Allowed.Contains($_) }, 'First').Count -eq 0) { $Rule } })
    if ($Kept.Count -eq 0) { return }


    if ($Platform -eq 'Windows') {
        $Deny = [System.Text.StringBuilder]::new()
        $Refs = [System.Text.StringBuilder]::new()
        foreach ($Rule in $Kept) {
            if (-not $Rule.Path.StartsWith('*\')) { throw "RMM block list: path must start with *\: $($Rule.Path)" }
            $Id = 'ID_DENY_A_{0}' -f [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Rule.Key))).Substring(0, 32)
            $null = $Deny.Append(('    <Deny ID="{0}" FriendlyName="{1}" FilePath="{2}" />' -f $Id, [System.Security.SecurityElement]::Escape(($Rule.Owners -join '; ')), [System.Security.SecurityElement]::Escape($Rule.Path))).Append("`n")
            $null = $Refs.Append(('          <FileRuleRef RuleID="{0}" />' -f $Id)).Append("`n")
        }
        # Enforced, unsigned, user mode only. Script enforcement is off so PowerShell stays out of
        # Constrained Language Mode, and the two allow-all rules make this a deny list, not an allow list.
        $Content = @"
<?xml version="1.0" encoding="utf-8"?>
<SiPolicy PolicyType="Base Policy" xmlns="urn:schemas-microsoft-com:sipolicy">
  <VersionEx>$($List.version)</VersionEx>
  <PolicyID>{C1BB0B10-52A4-4C7E-9D3B-6E0F2A7C41D5}</PolicyID>
  <BasePolicyID>{C1BB0B10-52A4-4C7E-9D3B-6E0F2A7C41D5}</BasePolicyID>
  <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID>
  <Rules>
    <Rule>
      <Option>Enabled:UMCI</Option>
    </Rule>
    <Rule>
      <Option>Enabled:Unsigned System Integrity Policy</Option>
    </Rule>
    <Rule>
      <Option>Disabled:Script Enforcement</Option>
    </Rule>
    <Rule>
      <Option>Enabled:Update Policy No Reboot</Option>
    </Rule>
  </Rules>
  <FileRules>
    <Allow ID="ID_ALLOW_A_CIPP_USERMODE" FileName="*" />
    <Allow ID="ID_ALLOW_A_CIPP_KERNEL" FileName="*" />
$($Deny.ToString())  </FileRules>
  <SigningScenarios>
    <SigningScenario Value="12" ID="ID_SIGNINGSCENARIO_WINDOWS" FriendlyName="User Mode Code Integrity">
      <ProductSigners>
        <FileRulesRef>
          <FileRuleRef RuleID="ID_ALLOW_A_CIPP_USERMODE" />
$($Refs.ToString())        </FileRulesRef>
      </ProductSigners>
    </SigningScenario>
    <SigningScenario Value="131" ID="ID_SIGNINGSCENARIO_DRIVERS_1" FriendlyName="Kernel Mode Code Integrity">
      <ProductSigners>
        <FileRulesRef>
          <FileRuleRef RuleID="ID_ALLOW_A_CIPP_KERNEL" />
        </FileRulesRef>
      </ProductSigners>
    </SigningScenario>
  </SigningScenarios>
  <Settings>
    <Setting Provider="AllHostIds" Key="AllKeys" ValueName="EnterpriseDefinedClsId">
      <Value>
        <Boolean>true</Boolean>
      </Value>
    </Setting>
    <Setting Provider="PolicyInfo" Key="Information" ValueName="Name">
      <Value>
        <String>CIPP - Block unapproved RMM tools</String>
      </Value>
    </Setting>
    <Setting Provider="PolicyInfo" Key="Information" ValueName="Id">
      <Value>
        <String>$($List.version)</String>
      </Value>
    </Setting>
  </Settings>
</SiPolicy>
"@ -replace "`r`n", "`n"
    } else {
        # These vendors sign everyday software too, so a rule without a signing id would stop Edge,
        # Chrome or Acrobat on every Mac.
        $BroadTeamIds = @('UBF8T346G9', 'EQHXZ8M8AV', 'JQ525L2MZD', '2BUA8C4S2C', '68WVV388M8')
        foreach ($Rule in $Kept) {
            if ($Rule.TeamId -cnotmatch '^[A-Z0-9]{10}$') { throw "RMM block list: invalid macOS Team ID '$($Rule.TeamId)' ($($Rule.Owners -join '; '))" }
            if ($Rule.TeamId -in $BroadTeamIds -and -not $Rule.SigningId) { throw "RMM block list: Team ID $($Rule.TeamId) signs unrelated software and needs a signing id ($($Rule.Owners -join '; '))" }
        }
        $Content = ($Kept | ForEach-Object { $_.Key }) -join "`n"
    }

    $Fingerprint = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$Content`n$AssignmentKey"))).Substring(0, 16)
    $Description = if ($Platform -eq 'Windows') {
        "Blocks $($Kept.Count) file and folder rules of unapproved RMM and remote access tools with App Control for Business. Needs Windows 11 24H2 or newer. Tool list $($List.version) from RMM Guard by Lewis Barry and Roy Klooster. Managed by CIPP. [cfg:$Fingerprint]"
    } else {
        "Denies $($Kept.Count) code signatures of unapproved RMM and remote access tools. Needs macOS 27 or newer on a supervised Mac. Tool list $($List.version) from RMM Guard by Lewis Barry and Roy Klooster. Managed by CIPP. [cfg:$Fingerprint]"
    }

    $String = {
        param($Id, $Value, $InstanceTemplate, $ValueTemplate)
        $Instance = [ordered]@{
            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
            settingDefinitionId = $Id
            simpleSettingValue  = [ordered]@{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'; value = $Value }
        }
        if ($InstanceTemplate) {
            $Instance['settingInstanceTemplateReference'] = @{ settingInstanceTemplateId = $InstanceTemplate }
            $Instance.simpleSettingValue['settingValueTemplateReference'] = @{ settingValueTemplateId = $ValueTemplate }
        }
        $Instance
    }
    $Group = {
        param($Id, [object[]]$Values)
        [ordered]@{
            '@odata.type'               = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
            settingDefinitionId         = $Id
            groupSettingCollectionValue = @($Values)
        }
    }

    if ($Platform -eq 'Windows') {
        $Name = 'CIPP - Block unapproved RMM tools (Windows)'
        # The Endpoint security > App Control for Business template, with the XML upload option.
        $Policy = [ordered]@{
            name              = $Name
            description       = $Description
            platforms         = 'windows10'
            technologies      = 'mdm'
            settings          = @(
                [ordered]@{
                    '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                    settingInstance = [ordered]@{
                        '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                        settingDefinitionId              = 'device_vendor_msft_policy_config_applicationcontrol_policies_{policyguid}_policiesoptions'
                        settingInstanceTemplateReference = @{ settingInstanceTemplateId = '1de98212-6949-42dc-a89c-e0ff6e5da04b' }
                        choiceSettingValue               = [ordered]@{
                            '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                            value                         = 'device_vendor_msft_policy_config_applicationcontrol_configure_xml_selected'
                            settingValueTemplateReference = @{ settingValueTemplateId = 'b28c7dc4-c7b2-4ce2-8f51-6ebfd3ea69d3' }
                            children                      = @(
                                & $String 'device_vendor_msft_policy_config_applicationcontrol_policies_{policyguid}_xml' $Content '4d709667-63d7-42f2-8e1b-b780f6c3c9c7' '88f6f096-dedb-4cf1-ac2f-4b41e303adb5'
                            )
                        }
                    }
                }
            )
            templateReference = @{ templateId = '4321b946-b76b-4450-8afd-769c08b16ffc_1' }
        }
    } else {
        $Name = 'CIPP - Block unapproved RMM tools (macOS)'
        $Denied = @(foreach ($Rule in $Kept) {
                $Children = [System.Collections.Generic.List[object]]::new()
                $Children.Add((& $String 'app_allowed_deniedbinaries_item_teamid' $Rule.TeamId))
                if ($Rule.SigningId) { $Children.Add((& $String 'app_allowed_deniedbinaries_item_signingid' $Rule.SigningId)) }
                @{ children = @($Children) }
            })
        # Apple declarative device management, App Settings > Allowed > Denied Binaries.
        $Policy = [ordered]@{
            name            = $Name
            description     = $Description
            platforms       = 'macOS'
            technologies    = 'appleRemoteManagement'
            roleScopeTagIds = @('0')
            settings        = @(
                [ordered]@{
                    '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                    settingInstance = & $Group 'app_app' @(
                        @{ children = @(& $Group 'app_allowed' @(@{ children = @(& $Group 'app_allowed_deniedbinaries' $Denied) })) }
                    )
                }
            )
        }
    }

    [PSCustomObject]@{
        Name        = $Name
        ListVersion = "$($List.version)"
        RuleCount   = $Kept.Count
        Fingerprint = $Fingerprint
        RawJSON     = ConvertTo-Json -InputObject $Policy -Depth 30 -Compress
    }
}
