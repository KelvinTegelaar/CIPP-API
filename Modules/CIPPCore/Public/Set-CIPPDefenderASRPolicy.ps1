function Set-CIPPDefenderASRPolicy {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        $ASR,
        $Headers,
        [string]$APIName,
        [switch]$TemplateOnly
    )

    # Fallback to block mode
    $Mode = $ASR.Mode ?? 'block'

    # Lookup table: ASR input property name -> Graph settingDefinitionId suffix
    $ASRRuleMap = [ordered]@{
        BlockObfuscatedScripts  = 'blockexecutionofpotentiallyobfuscatedscripts'
        BlockAdobeChild         = 'blockadobereaderfromcreatingchildprocesses'
        BlockWin32Macro         = 'blockwin32apicallsfromofficemacros'
        BlockCredentialStealing = 'blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem'
        BlockPSExec             = 'blockprocesscreationsfrompsexecandwmicommands'
        WMIPersistence          = 'blockpersistencethroughwmieventsubscription'
        BlockOfficeExes         = 'blockofficeapplicationsfromcreatingexecutablecontent'
        BlockOfficeApps         = 'blockofficeapplicationsfrominjectingcodeintootherprocesses'
        BlockYoungExe           = 'blockexecutablefilesrunningunlesstheymeetprevalenceagetrustedlistcriterion'
        blockJSVB               = 'blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent'
        BlockWebshellForServers = 'blockwebshellcreationforservers'
        blockOfficeComChild     = 'blockofficecommunicationappfromcreatingchildprocesses'
        BlockSystemTools        = 'blockuseofcopiedorimpersonatedsystemtools'
        blockOfficeChild        = 'blockallofficeapplicationsfromcreatingchildprocesses'
        BlockUntrustedUSB       = 'blockuntrustedunsignedprocessesthatrunfromusb'
        EnableRansomwareVac     = 'useadvancedprotectionagainstransomware'
        BlockExesMail           = 'blockexecutablecontentfromemailclientandwebmail'
        BlockUnsignedDrivers    = 'blockabuseofexploitedvulnerablesigneddrivers'
        BlockSafeMode           = 'blockrebootingmachineinsafemode'
    }

    $ASRPrefix = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
    $ASRSettings = foreach ($Rule in $ASRRuleMap.GetEnumerator()) {
        if ($ASR.($Rule.Key)) {
            $DefinitionId = "${ASRPrefix}_$($Rule.Value)"
            @{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId = $DefinitionId
                choiceSettingValue  = @{
                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                    value         = "${DefinitionId}_${Mode}"
                }
            }
        }
    }

    $ASRBodyObj = @{
        name              = 'ASR Default rules'
        description       = ''
        platforms         = 'windows10'
        technologies      = 'mdm,microsoftSense'
        roleScopeTagIds   = @('0')
        templateReference = @{templateId = 'e8c053d6-9f95-42b1-a7f1-ebfd71c67a4b_1' }
        settings          = @(@{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                    settingDefinitionId              = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
                    groupSettingCollectionValue      = @(@{children = $ASRSettings })
                    settingInstanceTemplateReference = @{settingInstanceTemplateId = '19600663-e264-4c02-8f55-f2983216d6d7' }
                }
            })
    }

    if ($TemplateOnly) { return $ASRBodyObj }

    $ASRbody = ConvertTo-Json -Depth 15 -Compress -InputObject $ASRBodyObj
    $CheckExistingASR = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter
    if ('ASR Default rules' -in $CheckExistingASR.Name) {
        "$($TenantFilter): ASR Policy already exists. Skipping"
    } else {
        Write-Host $ASRbody
        if (($ASRSettings | Measure-Object).Count -gt 0) {
            $ASRRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter -type POST -body $ASRbody
            Write-Host ($ASRRequest.id)
            if ($ASR.AssignTo -and $ASR.AssignTo -ne 'none') {
                $AssignBody = if ($ASR.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($ASR.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ASRRequest.id)')/assign" -tenantid $TenantFilter -type POST -body $AssignBody
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned policy $($DisplayName) to $($ASR.AssignTo)" -Sev 'Info'
            }
            "$($TenantFilter): Successfully added ASR Settings"
        }
    }
}
