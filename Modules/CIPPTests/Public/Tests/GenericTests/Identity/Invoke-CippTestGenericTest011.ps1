function Invoke-CippTestGenericTest011 {
    <#
    .SYNOPSIS
    Standard Alignment Report — compliance status of applied standards templates
    #>
    param($Tenant)

    try {
        $AlignmentData = Get-CIPPTenantAlignment -TenantFilter $Tenant

        if (-not $AlignmentData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest011' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No standards alignment data found for this tenant. Ensure at least one standards template is assigned and data collection has run.' -Risk 'Informational' -Name 'Standard Alignment Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        # Load standards.json for friendly name resolution
        $StandardsLabelMap = @{}
        $StandardsJsonPath = Join-Path $env:CIPPRootPath 'Config\standards.json'
        if (Test-Path $StandardsJsonPath) {
            $StandardsJson = Get-Content $StandardsJsonPath -Raw | ConvertFrom-Json
            foreach ($Std in $StandardsJson) {
                if ($Std.name -and $Std.label) {
                    $StandardsLabelMap[$Std.name] = $Std.label
                }
            }
        }

        # Load Intune templates from table storage for display name resolution
        $TemplateTable = Get-CippTable -tablename 'templates'
        $AllIntuneTemplates = @()
        $AllCATemplates = @()
        try {
            $RawIntuneTemplates = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'IntuneTemplate'"
            $AllIntuneTemplates = @($RawIntuneTemplates | ForEach-Object {
                $JSONData = $_.JSON | ConvertFrom-Json -Depth 10
                $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 10
                $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
                $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
                $data
            })
        } catch { $AllIntuneTemplates = @() }

        # Load Conditional Access templates
        try {
            $RawCATemplates = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'CATemplate'"
            $AllCATemplates = @($RawCATemplates | ForEach-Object {
                $data = $_.JSON | ConvertFrom-Json -Depth 100
                $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
                $data
            })
        } catch { $AllCATemplates = @() }

        $AlignmentItems = @($AlignmentData)
        $Result = ''

        # Helper: resolve a standard name to a friendly display name
        # Mirrors the resolution chain from Get-CIPPDrift.ps1 and the frontend drift.js
        $ResolveDisplayName = {
            param($StandardName, $TemplateSettings)

            # 1. Regular standards — look up in standards.json
            if ($StandardsLabelMap.ContainsKey($StandardName)) {
                return $StandardsLabelMap[$StandardName]
            }

            # 2. IntuneTemplate — extract GUID, look up in template table, fall back to standardSettings
            if ($StandardName -like '*IntuneTemplate*') {
                $Parts = $StandardName.Split('.')
                $TemplateGuid = $Parts | Where-Object {
                    $_ -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                } | Select-Object -First 1

                if ($TemplateGuid) {
                    # Try template table first
                    $MatchedTemplate = $AllIntuneTemplates | Where-Object { $_.GUID -match "$TemplateGuid" }
                    if ($MatchedTemplate -and $MatchedTemplate.displayName) {
                        return "Intune - $($MatchedTemplate.displayName)"
                    }
                    # Fall back to standardSettings TemplateList.label
                    if ($TemplateSettings -and $TemplateSettings.IntuneTemplate) {
                        $IntuneTemplates = @($TemplateSettings.IntuneTemplate)
                        $Match = $IntuneTemplates | Where-Object { $_.TemplateList.value -eq $TemplateGuid }
                        if ($Match -and $Match.TemplateList.label) {
                            return "Intune - $($Match.TemplateList.label)"
                        }
                    }
                }
                return $null
            }

            # 3. ConditionalAccessTemplate — extract GUID, look up in template table
            if ($StandardName -like '*ConditionalAccessTemplate*') {
                $Parts = $StandardName.Split('.')
                $TemplateGuid = $Parts | Where-Object {
                    $_ -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                } | Select-Object -First 1

                if ($TemplateGuid) {
                    $MatchedTemplate = $AllCATemplates | Where-Object { $_.GUID -match "$TemplateGuid" }
                    if ($MatchedTemplate -and $MatchedTemplate.displayName) {
                        return "Conditional Access - $($MatchedTemplate.displayName)"
                    }
                    if ($TemplateSettings -and $TemplateSettings.ConditionalAccessTemplate) {
                        $CATemplates = @($TemplateSettings.ConditionalAccessTemplate)
                        $Match = $CATemplates | Where-Object { $_.TemplateList.value -eq $TemplateGuid }
                        if ($Match -and $Match.TemplateList.label) {
                            return "Conditional Access - $($Match.TemplateList.label)"
                        }
                    }
                }
                return $null
            }

            # 4. QuarantineTemplate — hex decode the policy display name
            if ($StandardName -like 'standards.QuarantineTemplate.*') {
                $HexEncodedName = $StandardName.Substring('standards.QuarantineTemplate.'.Length)
                if ($HexEncodedName) {
                    $Chars = [System.Collections.Generic.List[char]]::new()
                    for ($i = 0; $i -lt $HexEncodedName.Length; $i += 2) {
                        $Chars.Add([char][Convert]::ToInt32($HexEncodedName.Substring($i, 2), 16))
                    }
                    return "Quarantine Policy - $(-join $Chars)"
                }
                return $null
            }

            # 5. Not found in any source
            return $null
        }

        foreach ($Template in $AlignmentItems) {
            $TemplateName = $Template.StandardName
            $Score = $Template.AlignmentScore
            $Compliant = $Template.CompliantStandards
            $NonCompliant = $Template.NonCompliantStandards
            $LicenseMissing = $Template.LicenseMissingStandards
            $Total = $Template.TotalStandards
            $ReportingDisabled = $Template.ReportingDisabledCount

            $ScoreIcon = if ($Score -ge 80) { '✅' } elseif ($Score -ge 50) { '🟡' } else { '🔴' }

            $Result += "### $TemplateName`n`n"
            $Result += "**Alignment Score:** $ScoreIcon $Score% | **Compliant:** $Compliant / $Total"
            if ($LicenseMissing -gt 0) { $Result += " | **License Missing:** $LicenseMissing" }
            if ($ReportingDisabled -gt 0) { $Result += " | **Reporting Disabled:** $ReportingDisabled" }
            if ($Template.LatestDataCollection) {
                $CollectionDate = ([datetime]$Template.LatestDataCollection).ToString('yyyy-MM-dd HH:mm')
                $Result += " | **Last Checked:** $CollectionDate"
            }
            $Result += "`n`n"

            $Details = $Template.ComparisonDetails
            if (-not $Details) {
                $Result += "No comparison details available for this template.`n`n"
                continue
            }

            # Split into categories
            $CompliantItems = @($Details | Where-Object { $_.ComplianceStatus -eq 'Compliant' })
            $NonCompliantItems = @($Details | Where-Object { $_.ComplianceStatus -eq 'Non-Compliant' })
            $LicenseMissingItems = @($Details | Where-Object { $_.ComplianceStatus -eq 'License Missing' })
            $ReportingDisabledItems = @($Details | Where-Object { $_.ComplianceStatus -eq 'Reporting Disabled' })

            # Helper to resolve and skip unresolvable template items
            $TemplateSettings = $Template.standardSettings

            # Compliant items
            if ($CompliantItems.Count -gt 0) {
                $Result += "| Standard | Status |`n"
                $Result += "|----------|--------|`n"
                foreach ($Item in $CompliantItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Result += "| $FriendlyName | ✅ Compliant |`n"
                }
                $Result += "`n"
            }

            # Non-compliant items
            if ($NonCompliantItems.Count -gt 0) {
                $Result += "| Standard | Status |`n"
                $Result += "|----------|--------|`n"
                foreach ($Item in $NonCompliantItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Result += "| $FriendlyName | ❌ Non-Compliant |`n"
                }
                $Result += "`n"
            }

            # License missing items
            if ($LicenseMissingItems.Count -gt 0) {
                $Result += "#### Standards Not Applied Due to Missing Licenses`n`n"
                $Result += "These items are part of this baseline, but your environment does not meet the minimum required licenses for them to be applied.`n`n"
                $Result += "| Standard | Status |`n"
                $Result += "|----------|--------|`n"
                foreach ($Item in $LicenseMissingItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Result += "| $FriendlyName | ⚠️ License Missing |`n"
                }
                $Result += "`n"
            }

            # Reporting disabled items
            if ($ReportingDisabledItems.Count -gt 0) {
                $Result += "#### Standards With Reporting Disabled`n`n"
                $Result += "| Standard | Status |`n"
                $Result += "|----------|--------|`n"
                foreach ($Item in $ReportingDisabledItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Result += "| $FriendlyName | ⏸️ Reporting Disabled |`n"
                }
                $Result += "`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest011' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Standard Alignment Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest011: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest011' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Standard Alignment Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
