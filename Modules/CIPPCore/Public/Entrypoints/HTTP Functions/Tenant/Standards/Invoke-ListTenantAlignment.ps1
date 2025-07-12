using namespace System.Net

function Invoke-ListTenantAlignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Get all standard templates
    $TemplateTable = Get-CippTable -tablename 'templates'
    $TemplateFilter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @TemplateTable -Filter $TemplateFilter) | ForEach-Object {
        $JSON = $_.JSON -replace '"Action":', '"action":'
        try {
            $RowKey = $_.RowKey
            $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
        } catch {
            Write-Host "$($RowKey) standard could not be loaded: $($_.Exception.Message)"
            return
        }
        if ($Data) {
            $Data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
            $Data
        }
    }

    # Get standards comparison data using the same pattern as ListStandardsCompare
    $StandardsTable = Get-CIPPTable -TableName 'CippStandardsReports'
    $Standards = Get-CIPPAzDataTableEntity @StandardsTable

    # Build tenant standards data structure like in ListStandardsCompare
    $TenantStandards = @{}
    foreach ($Standard in $Standards) {
        $FieldName = $Standard.RowKey
        $FieldValue = $Standard.Value
        $Tenant = $Standard.PartitionKey

        # Process field value like in ListStandardsCompare
        if ($FieldValue -is [System.Boolean]) {
            $FieldValue = [bool]$FieldValue
        } elseif ($FieldValue -like '*{*') {
            $FieldValue = ConvertFrom-Json -InputObject $FieldValue -ErrorAction SilentlyContinue
        } else {
            $FieldValue = [string]$FieldValue
        }

        if (-not $TenantStandards.ContainsKey($Tenant)) {
            $TenantStandards[$Tenant] = @{}
        }
        $TenantStandards[$Tenant][$FieldName] = @{
            Value       = $FieldValue
            LastRefresh = $Standard.TimeStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
    }

    $Results = [System.Collections.Generic.List[object]]::new()

    # Process each template against all tenants
    foreach ($Template in $Templates) {
        $TemplateStandards = $Template.standards
        if (-not $TemplateStandards) {
            continue
        }

        # Check if template has tenant assignments (scope)
        $TemplateAssignedTenants = @()
        $AppliestoAllTenants = $false

        if ($Template.tenantFilter -and $Template.tenantFilter.Count -gt 0) {
            # Extract tenant values from the tenantFilter array
            $TenantValues = $Template.tenantFilter | ForEach-Object { $_.value }

            if ($TenantValues -contains "AllTenants") {
                $AppliestoAllTenants = $true
                Write-Host "Template '$($Template.templateName)' applies to all tenants (AllTenants)"
            } else {
                $TemplateAssignedTenants = $TenantValues
                Write-Host "Template '$($Template.templateName)' is assigned to specific tenants: $($TemplateAssignedTenants -join ', ')"
            }
        } else {
            $AppliestoAllTenants = $true
            Write-Host "Template '$($Template.templateName)' applies to all tenants (no tenantFilter)"
        }

        # Track all standards and their reporting status like the frontend does
        $AllStandards = [System.Collections.Generic.List[string]]::new()
        $ReportingEnabledStandards = [System.Collections.Generic.List[string]]::new()
        $ReportingDisabledStandards = [System.Collections.Generic.List[string]]::new()

        foreach ($StandardKey in $TemplateStandards.PSObject.Properties.Name) {
            $StandardConfig = $TemplateStandards.$StandardKey
            $StandardId = "standards.$StandardKey"

            # Check if reporting is enabled for this standard (same logic as frontend)
            # Try multiple possible action property locations
            $Actions = @()
            if ($StandardConfig.action) {
                $Actions = $StandardConfig.action
            } elseif ($StandardConfig.Action) {
                $Actions = $StandardConfig.Action
            } elseif ($StandardConfig.PSObject.Properties['action']) {
                $Actions = $StandardConfig.PSObject.Properties['action'].Value
            }

            # Frontend logic: actions.filter(action => action?.value.toLowerCase() === "report" || action?.value.toLowerCase() === "remediate").length > 0
            $ReportingEnabled = $false
            if ($Actions -and $Actions.Count -gt 0) {
                $ReportingEnabled = ($Actions | Where-Object { $_.value -and ($_.value.ToLower() -eq "report" -or $_.value.ToLower() -eq "remediate") }).Count -gt 0
            }

            # Add to all standards list
            $AllStandards.Add($StandardId)

            if ($ReportingEnabled) {
                $ReportingEnabledStandards.Add($StandardId)
            } else {
                $ReportingDisabledStandards.Add($StandardId)
            }

            # Handle IntuneTemplate arrays - don't count the base IntuneTemplate, only the specific instances
            if ($StandardKey -eq 'IntuneTemplate' -and $StandardConfig -is [array]) {
                # Remove the base IntuneTemplate standard since we'll add specific instances
                $AllStandards.Remove($StandardId)
                if ($ReportingEnabled) {
                    $ReportingEnabledStandards.Remove($StandardId)
                } else {
                    $ReportingDisabledStandards.Remove($StandardId)
                }

                foreach ($IntuneTemplate in $StandardConfig) {
                    if ($IntuneTemplate.TemplateList.value) {
                        $IntuneStandardId = "standards.IntuneTemplate.$($IntuneTemplate.TemplateList.value)"

                        # Check if reporting is enabled for this Intune template
                        $IntuneActions = if ($IntuneTemplate.action) { $IntuneTemplate.action } else { @() }
                        Write-Host "    Intune template $IntuneStandardId actions: $($IntuneActions | ForEach-Object { $_.value } | Join-String -Separator ', ')"
                        $IntuneReportingEnabled = ($IntuneActions | Where-Object { $_.value -and ($_.value.ToLower() -eq "report" -or $_.value.ToLower() -eq "remediate") }).Count -gt 0
                        Write-Host "    Intune template $IntuneStandardId reporting enabled: $IntuneReportingEnabled"

                        # Add to all standards list
                        $AllStandards.Add($IntuneStandardId)

                        if ($IntuneReportingEnabled) {
                            $ReportingEnabledStandards.Add($IntuneStandardId)
                            Write-Host "    Added $IntuneStandardId to reporting enabled"
                        } else {
                            $ReportingDisabledStandards.Add($IntuneStandardId)
                            Write-Host "    Added $IntuneStandardId to reporting disabled"
                        }
                    }
                }
            }
        }

        # Process each tenant against this template (but only if template applies to this tenant)
        foreach ($TenantName in $TenantStandards.Keys) {
            # Skip this tenant if template is assigned to specific tenants and this tenant is not in the list
            if (-not $AppliestoAllTenants -and $TenantName -notin $TemplateAssignedTenants) {
                Write-Host "Skipping tenant '$TenantName' for template '$($Template.templateName)' - not in assigned tenant list"
                continue
            }
            $AllCount = $AllStandards.Count

            # Check compliance for ALL standards (both reporting enabled and disabled)
            # But track them separately like the frontend does
            $CompliantStandards = 0
            $NonCompliantStandards = 0
            $ReportingDisabledStandardsCount = 0
            $LatestDataCollection = $null

            # Create a table to compare with frontend
            $ComparisonTable = @()

            foreach ($StandardKey in $AllStandards) {
                $IsReportingDisabled = $ReportingDisabledStandards -contains $StandardKey

                if ($TenantStandards[$TenantName].ContainsKey($StandardKey)) {
                    $StandardObject = $TenantStandards[$TenantName][$StandardKey]
                    $Value = $StandardObject.Value

                    # Track the latest data collection timestamp
                    if ($StandardObject.LastRefresh) {
                        $RefreshTime = [DateTime]::Parse($StandardObject.LastRefresh)
                        if (-not $LatestDataCollection -or $RefreshTime -gt $LatestDataCollection) {
                            $LatestDataCollection = $RefreshTime
                        }
                    }

                    # Use strict compliance logic - only explicit TRUE is compliant
                    $IsCompliant = ($Value -eq $true)

                    # Count based on reporting status like the frontend
                    if ($IsReportingDisabled) {
                        $ReportingDisabledStandardsCount++
                        $ComplianceStatus = "Reporting Disabled"
                    } elseif ($IsCompliant) {
                        $CompliantStandards++
                        $ComplianceStatus = "Compliant"
                    } else {
                        $NonCompliantStandards++
                        $ComplianceStatus = "Non-Compliant"
                    }

                    $ComparisonTable += [PSCustomObject]@{
                        StandardName = $StandardKey
                        Compliant = $IsCompliant
                        StandardValue = ($Value | ConvertTo-Json -Compress)
                        ComplianceStatus = $ComplianceStatus
                        ReportingDisabled = $IsReportingDisabled
                    }
                } else {
                    # If standard not found, count as non-compliant if reporting enabled, or reporting disabled if reporting disabled
                    if ($IsReportingDisabled) {
                        $ReportingDisabledStandardsCount++
                        $ComplianceStatus = "Reporting Disabled"
                    } else {
                        $NonCompliantStandards++
                        $ComplianceStatus = "Non-Compliant"
                    }

                    $ComparisonTable += [PSCustomObject]@{
                        StandardName = $StandardKey
                        Compliant = $false
                        StandardValue = "NOT FOUND"
                        ComplianceStatus = $ComplianceStatus
                        ReportingDisabled = $IsReportingDisabled
                    }
                }
            }

            # Calculate percentage using the exact same formula as the frontend
            # Frontend: Math.round((compliantCount / (allCount - reportingDisabledCount || 1)) * 100)
            $AlignmentPercentage = if (($AllCount - $ReportingDisabledStandardsCount) -gt 0) {
                [Math]::Round(($CompliantStandards / ($AllCount - $ReportingDisabledStandardsCount)) * 100)
            } else {
                0
            }

            # Output comparison table for debugging
            Write-Host "=== TENANT: $TenantName | TEMPLATE: $($Template.templateName) ==="
            Write-Host "TEMPLATE STANDARDS FOUND: $($AllStandards -join ', ')"
            Write-Host "TENANT STANDARDS AVAILABLE: $($TenantStandards[$TenantName].Keys | Sort-Object | Join-String -Separator ', ')"

            # Check for tenant standards that might be missing from template
            $TenantOnlyStandards = $TenantStandards[$TenantName].Keys | Where-Object { $_ -notin $AllStandards }
            Write-Host "TENANT-ONLY STANDARDS (not in template): $($TenantOnlyStandards -join ', ')"

            Write-Host "CALCULATION: $CompliantStandards compliant / ($AllCount total - $ReportingDisabledStandardsCount reporting disabled) = $AlignmentPercentage%"
            Write-Host ""
            Write-Host ($ComparisonTable | Format-Table -Property StandardName, Compliant, ComplianceStatus, ReportingDisabled, StandardValue -AutoSize | Out-String)

            $Result = [PSCustomObject]@{
                tenantFilter   = $TenantName
                standardName   = $Template.templateName
                standardId     = $Template.GUID
                alignmentScore = $AlignmentPercentage
                latestDataCollection = if ($LatestDataCollection) { $LatestDataCollection.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            }

            $Results.Add($Result)
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })
}
