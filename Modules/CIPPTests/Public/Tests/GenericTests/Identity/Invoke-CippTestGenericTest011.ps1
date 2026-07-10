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

        # Load standards.json for friendly name and compliance-tag resolution
        $StandardsLabelMap = @{}
        $StandardsTagMap = @{}
        $StandardsJsonPath = Join-Path $env:CIPPRootPath 'Config\standards.json'
        if (Test-Path $StandardsJsonPath) {
            $StandardsJson = Get-Content $StandardsJsonPath -Raw | ConvertFrom-Json
            foreach ($Std in $StandardsJson) {
                if ($Std.name -and $Std.label) {
                    $StandardsLabelMap[$Std.name] = $Std.label
                }
                if ($Std.name -and $Std.tag) {
                    # Keep human-readable compliance-framework references (CIS, NIST, etc. - they
                    # contain spaces) and drop internal single-token tags like 'mip_search_auditlog'.
                    $FrameworkTags = @($Std.tag | Where-Object { $_ -is [string] -and $_ -match '\s' })
                    if ($FrameworkTags.Count -gt 0) {
                        $StandardsTagMap[$Std.name] = ($FrameworkTags -join ', ')
                    }
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
        $Result = [System.Text.StringBuilder]::new()

        # Helper: resolve a standard name to a friendly display name
        # Mirrors the resolution chain from Get-CIPPDrift.ps1 and the frontend drift.js
        $ResolveDisplayName = {
            param($StandardName, $TemplateSettings)

            if ([string]::IsNullOrWhiteSpace($StandardName)) { return $null }

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

        # Helper: resolve a standard's compliance-framework tags (CIS/NIST/etc.). Template-based
        # standards (Intune/CA/Quarantine) have no standards.json entry, so they return empty.
        $ResolveTags = {
            param($StandardName)
            if ([string]::IsNullOrWhiteSpace($StandardName)) { return '' }
            if ($StandardsTagMap.ContainsKey($StandardName)) { return $StandardsTagMap[$StandardName] }
            return ''
        }

        # Helper: render a stored CurrentValue/ExpectedValue (plain string, bool, or compact JSON)
        # safely inside a markdown table cell - escape pipes, collapse newlines, and truncate blobs.
        $FormatValue = {
            param($Value)
            if ($null -eq $Value -or "$Value" -eq '') { return '' }
            $Text = [string]$Value
            $Text = $Text -replace '\|', '\|' -replace '\r?\n', ' '
            if ($Text.Length -gt 300) { $Text = $Text.Substring(0, 297) + '...' }
            return $Text
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

            $null = $Result.Append("### $TemplateName`n`n")
            $null = $Result.Append("**Alignment Score:** $ScoreIcon $Score% | **Compliant:** $Compliant / $Total")
            if ($LicenseMissing -gt 0) { $null = $Result.Append(" | **License Missing:** $LicenseMissing") }
            if ($ReportingDisabled -gt 0) { $null = $Result.Append(" | **Reporting Disabled:** $ReportingDisabled") }
            if ($Template.LatestDataCollection) {
                $CollectionDate = ([datetime]$Template.LatestDataCollection).ToString('yyyy-MM-dd HH:mm')
                $null = $Result.Append(" | **Last Checked:** $CollectionDate")
            }
            $null = $Result.Append("`n`n")

            $Details = $Template.ComparisonDetails
            if (-not $Details) {
                $null = $Result.Append("No comparison details available for this template.`n`n")
                continue
            }

            $ByStatus = $Details | Group-Object ComplianceStatus -AsHashTable -AsString
            $CompliantItems = @($ByStatus['Compliant'])
            $NonCompliantItems = @($ByStatus['Non-Compliant'])
            $LicenseMissingItems = @($ByStatus['License Missing'])
            $ReportingDisabledItems = @($ByStatus['Reporting Disabled'])

            # Helper to resolve and skip unresolvable template items
            $TemplateSettings = $Template.standardSettings

            # Compliant items
            if ($CompliantItems.Count -gt 0) {
                $null = $Result.Append("#### Compliant Standards`n`n")
                $null = $Result.Append("| Standard | Tags | Status |`n")
                $null = $Result.Append("|----------|------|--------|`n")
                foreach ($Item in $CompliantItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Tags = & $ResolveTags $Item.StandardName
                    $null = $Result.Append("| $FriendlyName | $Tags | ✅ Compliant |`n")
                }
                $null = $Result.Append("`n")
            }

            # Non-compliant items — include the compliance tags and the reason for failure
            # (expected value from the standard vs. the current config on the tenant).
            if ($NonCompliantItems.Count -gt 0) {
                $null = $Result.Append("#### Non-Compliant Standards`n`n")
                $null = $Result.Append("| Standard | Tags | Expected Value | Current Value (on tenant) |`n")
                $null = $Result.Append("|----------|------|----------------|---------------------------|`n")
                foreach ($Item in $NonCompliantItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Tags = & $ResolveTags $Item.StandardName
                    $Expected = & $FormatValue $Item.ExpectedValue
                    $Current = & $FormatValue $Item.CurrentValue
                    if (-not $Current) { $Current = '_Not configured / no data_' }
                    $null = $Result.Append("| $FriendlyName | $Tags | $Expected | $Current |`n")
                }
                $null = $Result.Append("`n")
            }

            # License missing items
            if ($LicenseMissingItems.Count -gt 0) {
                $null = $Result.Append("#### Standards Not Applied Due to Missing Licenses`n`n")
                $null = $Result.Append("These items are part of this baseline, but your environment does not meet the minimum required licenses for them to be applied.`n`n")
                $null = $Result.Append("| Standard | Tags | Status |`n")
                $null = $Result.Append("|----------|------|--------|`n")
                foreach ($Item in $LicenseMissingItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Tags = & $ResolveTags $Item.StandardName
                    $null = $Result.Append("| $FriendlyName | $Tags | ⚠️ License Missing |`n")
                }
                $null = $Result.Append("`n")
            }

            # Reporting disabled items
            if ($ReportingDisabledItems.Count -gt 0) {
                $null = $Result.Append("#### Standards With Reporting Disabled`n`n")
                $null = $Result.Append("| Standard | Tags | Status |`n")
                $null = $Result.Append("|----------|------|--------|`n")
                foreach ($Item in $ReportingDisabledItems) {
                    $FriendlyName = & $ResolveDisplayName $Item.StandardName $TemplateSettings
                    if (-not $FriendlyName) { continue }
                    $Tags = & $ResolveTags $Item.StandardName
                    $null = $Result.Append("| $FriendlyName | $Tags | ⏸️ Reporting Disabled |`n")
                }
                $null = $Result.Append("`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest011' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Standard Alignment Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest011: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest011' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Standard Alignment Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
