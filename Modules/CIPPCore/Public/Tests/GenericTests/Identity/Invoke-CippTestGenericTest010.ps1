function Invoke-CippTestGenericTest010 {
    <#
    .SYNOPSIS
    Tenant Capabilities Report — list of all service plans and features available in the tenant
    #>
    param($Tenant)

    try {
        # Try to get capabilities from cache first, fall back to live query
        $Capabilities = Get-CIPPTenantCapabilities -TenantFilter $Tenant

        if (-not $Capabilities) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest010' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No tenant capability data could be retrieved. The tenant may not be accessible or licenses may not be synced.' -Risk 'Informational' -Name 'Tenant Capabilities Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $CapabilityProperties = $Capabilities.PSObject.Properties | Where-Object { $_.Value -eq $true }

        if (-not $CapabilityProperties -or $CapabilityProperties.Count -eq 0) {
            $Result = "No active service plans were found for this tenant. This is unusual and may indicate a licensing issue."
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest010' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Tenant Capabilities Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        # Load the ConversionTable for friendly names
        $ModuleBase = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
        $FriendlyNameMap = @{}
        if ($ModuleBase) {
            $CsvPath = Join-Path $ModuleBase 'lib\data\ConversionTable.csv'
            if (Test-Path $CsvPath) {
                $ConvertTable = Import-Csv $CsvPath
                foreach ($Row in $ConvertTable) {
                    if ($Row.Service_Plan_Name -and $Row.Service_Plans_Included_Friendly_Names) {
                        if (-not $FriendlyNameMap.ContainsKey($Row.Service_Plan_Name)) {
                            $FriendlyNameMap[$Row.Service_Plan_Name] = $Row.Service_Plans_Included_Friendly_Names
                        }
                    }
                }
            }
        }

        $Result = "**Total Active Capabilities:** $($CapabilityProperties.Count)`n`n"

        # Categorize capabilities into logical groups
        $Categories = [ordered]@{
            'Email & Communication'     = @('EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD', 'EXCHANGE_S_FOUNDATION', 'MCOSTANDARD', 'MCOEV', 'TEAMS1', 'MICROSOFTBOOKINGS', 'YAMMER_ENTERPRISE')
            'Office & Productivity'     = @('OFFICESUBSCRIPTION', 'SHAREPOINTENTERPRISE', 'SHAREPOINTWAC', 'SWAY', 'FORMS_PLAN_E5', 'FORMS_PLAN_E3', 'PROJECTWORKMANAGEMENT', 'MICROSOFT_LOOP', 'CLIPCHAMP', 'MESH_IMMERSIVE_FOR_TEAMS', 'MESH_AVATARS_FOR_TEAMS', 'MESH_AVATARS_ADDITIONAL_FOR_TEAMS', 'WHITEBOARD_PLAN3', 'BPOS_S_TODO_3')
            'Power Platform'            = @('POWERAPPS_O365_P3', 'POWERAPPS_O365_P2', 'FLOW_O365_P3', 'FLOW_O365_P2', 'BI_AZURE_P2', 'BI_AZURE_P1', 'POWER_VIRTUAL_AGENTS_O365_P3', 'CDS_O365_P3', 'DYN365_CDS_O365_P3', 'PROJECT_O365_P3')
            'Security & Identity'       = @('AAD_PREMIUM', 'AAD_PREMIUM_P2', 'MFA_PREMIUM', 'RMS_S_ENTERPRISE', 'RMS_S_PREMIUM', 'RMS_S_PREMIUM2', 'ATA', 'ADALLOM_S_STANDALONE', 'ADALLOM_S_O365', 'MTP', 'ATP_ENTERPRISE', 'THREAT_INTELLIGENCE', 'SAFEDOCS', 'COMMON_DEFENDER_PLATFORM_FOR_OFFICE')
            'Compliance & Governance'   = @('MIP_S_CLP1', 'MIP_S_CLP2', 'MIP_S_Exchange', 'LOCKBOX_ENTERPRISE', 'CustomerLockboxA_Enterprise', 'CUSTOMER_KEY', 'RECORDS_MANAGEMENT', 'INFO_GOVERNANCE', 'ML_CLASSIFICATION', 'EQUIVIO_ANALYTICS', 'INSIDER_RISK', 'INSIDER_RISK_MANAGEMENT', 'COMMUNICATIONS_COMPLIANCE', 'COMMUNICATIONS_DLP', 'MICROSOFT_COMMUNICATION_COMPLIANCE', 'DATA_INVESTIGATIONS', 'M365_ADVANCED_AUDITING', 'M365_AUDIT_PLATFORM', 'PAM_ENTERPRISE', 'Content_Explorer', 'PURVIEW_DISCOVERY')
            'Device Management'         = @('INTUNE_A', 'INTUNE_O365')
            'Analytics & Insights'      = @('EXCHANGE_ANALYTICS', 'MICROSOFT_MYANALYTICS_FULL', 'INSIGHTS_BY_MYANALYTICS', 'VIVA_LEARNING_SEEDED', 'PEOPLE_SKILLS_FOUNDATION', 'MICROSOFT_SEARCH', 'Bing_Chat_Enterprise', 'GRAPH_CONNECTORS_SEARCH_INDEX')
            'Collaboration & Storage'   = @('STREAM_O365_E5', 'Nucleus', 'Deskless', 'EXCEL_PREMIUM', 'PLACES_CORE', 'M365_LIGHTHOUSE_CUSTOMER_PLAN1')
        }

        $CategorizedPlanNames = $Categories.Values | ForEach-Object { $_ }
        $AllPlanNames = @($CapabilityProperties | Select-Object -ExpandProperty Name)

        foreach ($CategoryName in $Categories.Keys) {
            $CategoryPlans = @($AllPlanNames | Where-Object { $_ -in $Categories[$CategoryName] })
            if ($CategoryPlans.Count -eq 0) { continue }

            $Result += "### $CategoryName`n`n"
            $Result += "| Capability | Service Plan |`n"
            $Result += "|------------|-------------|`n"

            foreach ($Plan in ($CategoryPlans | Sort-Object)) {
                $FriendlyName = if ($FriendlyNameMap.ContainsKey($Plan)) {
                    $FriendlyNameMap[$Plan]
                } else {
                    # Convert raw plan name to readable format
                    $Plan -replace '_', ' ' -replace '([a-z])([A-Z])', '$1 $2' -replace ' S ', ' ' -replace ' O365 ', ' ' -replace ' P\d$', '' -replace ' ENTERPRISE', '' -replace ' PREMIUM', ' Premium' -replace ' STANDARD', ''
                }
                $Result += "| $FriendlyName | $Plan |`n"
            }
            $Result += "`n"
        }

        # Any uncategorized plans
        $Uncategorized = @($AllPlanNames | Where-Object { $_ -notin $CategorizedPlanNames })
        if ($Uncategorized.Count -gt 0) {
            $Result += "### Other Capabilities`n`n"
            $Result += "| Capability | Service Plan |`n"
            $Result += "|------------|-------------|`n"

            foreach ($Plan in ($Uncategorized | Sort-Object)) {
                $FriendlyName = if ($FriendlyNameMap.ContainsKey($Plan)) {
                    $FriendlyNameMap[$Plan]
                } else {
                    $Plan -replace '_', ' ' -replace '([a-z])([A-Z])', '$1 $2' -replace ' S ', ' ' -replace ' O365 ', ' ' -replace ' P\d$', '' -replace ' ENTERPRISE', '' -replace ' PREMIUM', ' Premium' -replace ' STANDARD', ''
                }
                $Result += "| $FriendlyName | $Plan |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest010' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Tenant Capabilities Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest010: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest010' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Tenant Capabilities Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
