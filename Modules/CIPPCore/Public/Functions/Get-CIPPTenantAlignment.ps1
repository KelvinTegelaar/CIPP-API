function Get-CIPPTenantAlignment {
    <#
    .SYNOPSIS
        Gets tenant alignment data for standards compliance
    .DESCRIPTION
        This function calculates tenant alignment percentages against standards templates.
        It processes all standard templates and compares them against tenant standards data.
    .PARAMETER TenantFilter
        The tenant to get alignment data for. If not specified, processes all tenants.
    .PARAMETER TemplateId
        Optional specific template GUID to check alignment for. If not specified, processes all templates.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPTenantAlignment -TenantFilter "contoso.onmicrosoft.com"
    .EXAMPLE
        Get-CIPPTenantAlignment -TenantFilter "contoso.onmicrosoft.com" -TemplateId "12345-67890-abcdef"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$TemplateId
    )
    $TemplateTable = Get-CippTable -tablename 'templates'
    $TemplateFilter = "PartitionKey eq 'StandardsTemplateV2'"
    $TenantGroups = Get-TenantGroups

    try {
        # Get all standard templates
        $Templates = (Get-CIPPAzDataTableEntity @TemplateTable -Filter $TemplateFilter) | ForEach-Object {
            $JSON = $_.JSON
            try {
                $RowKey = $_.RowKey
                $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            } catch {
                Write-Warning "$($RowKey) standard could not be loaded: $($_.Exception.Message)"
                return
            }
            if ($Data) {
                $Data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
                $Data
            }
        }

        if (-not $Templates) {
            Write-Warning 'No templates found matching the criteria'
            return @()
        }

        # Get standards comparison data
        $StandardsTable = Get-CippTable -TableName 'CippStandardsReports'
        #this if statement is to bring down performance when running scheduled checks, we have to revisit this to a better query due to the extreme size this can get.
        if ($TenantFilter) {
            $filter = "PartitionKey eq '$TenantFilter'"
        } else {
            $filter = "PartitionKey ne 'StandardReport' and PartitionKey ne ''"
        }
        $AllStandards = Get-CIPPAzDataTableEntity @StandardsTable -Filter $filter

        # Filter by tenant if specified
        $Standards = if ($TenantFilter) {
            $AllStandards
        } else {
            $Tenants = Get-Tenants -IncludeErrors
            $AllStandards | Where-Object { $_.PartitionKey -in $Tenants.defaultDomainName }
        }
        $TagTemplates = Get-CIPPAzDataTableEntity @TemplateTable
        # Build tenant standards data structure
        $tenantData = @{}
        foreach ($Standard in $Standards) {
            $FieldName = $Standard.RowKey
            $FieldValue = $Standard.Value
            $Tenant = $Standard.PartitionKey

            # Process field value
            if ($FieldValue -is [System.Boolean]) {
                $FieldValue = [bool]$FieldValue
            } else {
                try {
                    $FieldValue = ConvertFrom-Json -Depth 5 -InputObject $FieldValue -ErrorAction Stop
                } catch {
                    $FieldValue = [string]$FieldValue
                }
            }

            if (-not $tenantData.ContainsKey($Tenant)) {
                $tenantData[$Tenant] = @{}
            }
            $tenantData[$Tenant][$FieldName] = @{
                Value       = $FieldValue
                LastRefresh = $Standard.TimeStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }
        $TenantStandards = $tenantData

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
                $TenantValues = $Template.tenantFilter | ForEach-Object {
                    if ($_.type -eq 'group') {
                        ($TenantGroups | Where-Object -Property GroupName -EQ $_.value).Members.defaultDomainName
                    } else {
                        $_.value
                    }
                }

                if ($TenantValues -contains 'AllTenants') {
                    $AppliestoAllTenants = $true
                } else {
                    $TemplateAssignedTenants = $TenantValues
                }
            } else {
                $AppliestoAllTenants = $true
            }

            $StandardsData = foreach ($StandardKey in $TemplateStandards.PSObject.Properties.Name) {
                $StandardConfig = $TemplateStandards.$StandardKey
                $StandardId = "standards.$StandardKey"

                $Actions = @()
                if ($StandardConfig.action) {
                    $Actions = $StandardConfig.action
                } elseif ($StandardConfig.Action) {
                    $Actions = $StandardConfig.Action
                } elseif ($StandardConfig.PSObject.Properties['action']) {
                    $Actions = $StandardConfig.PSObject.Properties['action'].Value
                }

                $ReportingEnabled = $false
                if ($Actions -and $Actions.Count -gt 0) {
                    $ReportingEnabled = ($Actions | Where-Object { $_.value -and ($_.value.ToLower() -eq 'report' -or $_.value.ToLower() -eq 'remediate') }).Count -gt 0
                }

                # Handle Intune templates specially
                if ($StandardKey -eq 'IntuneTemplate' -and $StandardConfig -is [array]) {
                    foreach ($IntuneTemplate in $StandardConfig) {
                        if ($IntuneTemplate.TemplateList.value) {
                            $IntuneStandardId = "standards.IntuneTemplate.$($IntuneTemplate.TemplateList.value)"
                            $IntuneActions = if ($IntuneTemplate.action) { $IntuneTemplate.action } else { @() }
                            $IntuneReportingEnabled = ($IntuneActions | Where-Object { $_.value -and ($_.value.ToLower() -eq 'report' -or $_.value.ToLower() -eq 'remediate') }).Count -gt 0
                            [PSCustomObject]@{
                                StandardId       = $IntuneStandardId
                                ReportingEnabled = $IntuneReportingEnabled
                            }
                        }

                        if ($IntuneTemplate.'TemplateList-Tags') {
                            foreach ($Tag in $IntuneTemplate.'TemplateList-Tags') {
                                Write-Host "Processing Intune Tag: $($Tag.value)"
                                $IntuneActions = if ($IntuneTemplate.action) { $IntuneTemplate.action } else { @() }
                                $IntuneReportingEnabled = ($IntuneActions | Where-Object { $_.value -and ($_.value.ToLower() -eq 'report' -or $_.value.ToLower() -eq 'remediate') }).Count -gt 0
                                $TagTemplate = $TagTemplates | Where-Object -Property package -EQ $Tag.value
                                $TagTemplates | ForEach-Object {
                                    $TagStandardId = "standards.IntuneTemplate.$($_.GUID)"
                                    [PSCustomObject]@{
                                        StandardId       = $TagStandardId
                                        ReportingEnabled = $IntuneReportingEnabled
                                    }
                                }
                            }
                        }
                    }
                }
                # Handle Conditional Access templates specially
                elseif ($StandardKey -eq 'ConditionalAccessTemplate' -and $StandardConfig -is [array]) {
                    foreach ($CATemplate in $StandardConfig) {
                        if ($CATemplate.TemplateList.value) {
                            $CAStandardId = "standards.ConditionalAccessTemplate.$($CATemplate.TemplateList.value)"
                            $CAActions = if ($CATemplate.action) { $CATemplate.action } else { @() }
                            $CAReportingEnabled = ($CAActions | Where-Object { $_.value -and ($_.value.ToLower() -eq 'report' -or $_.value.ToLower() -eq 'remediate') }).Count -gt 0

                            [PSCustomObject]@{
                                StandardId       = $CAStandardId
                                ReportingEnabled = $CAReportingEnabled
                            }
                        }
                    }
                } else {
                    [PSCustomObject]@{
                        StandardId       = $StandardId
                        ReportingEnabled = $ReportingEnabled
                    }
                }
            }

            $AllStandards = $StandardsData.StandardId
            $AllStandardsArray = @($AllStandards)
            $ReportingDisabledStandards = ($StandardsData | Where-Object { -not $_.ReportingEnabled }).StandardId
            $ReportingDisabledSet = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($item in $ReportingDisabledStandards) { [void]$ReportingDisabledSet.Add($item) }
            $TemplateAssignedTenantsSet = if ($TemplateAssignedTenants.Count -gt 0) {
                $set = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($item in $TemplateAssignedTenants) { [void]$set.Add($item) }
                $set
            } else { $null }

            foreach ($TenantName in $TenantStandards.Keys) {
                # Check tenant scope with HashSet and cache tenant data
                if (-not $AppliestoAllTenants) {
                    if ($TemplateAssignedTenantsSet -and -not $TemplateAssignedTenantsSet.Contains($TenantName)) {
                        continue
                    }
                }

                $AllCount = $AllStandards.Count
                $LatestDataCollection = $null
                # Cache hashtable lookup
                $CurrentTenantStandards = $TenantStandards[$TenantName]

                # Pre-allocate list with capacity
                $ComparisonResults = [System.Collections.Generic.List[object]]::new($AllStandardsArray.Count)

                # Use for loop instead of foreach
                for ($i = 0; $i -lt $AllStandardsArray.Count; $i++) {
                    $StandardKey = $AllStandardsArray[$i]

                    # Use HashSet for Contains
                    $IsReportingDisabled = $ReportingDisabledSet.Contains($StandardKey)
                    # Use cached tenant data
                    $HasStandard = $CurrentTenantStandards.ContainsKey($StandardKey)

                    if ($HasStandard) {
                        $StandardObject = $CurrentTenantStandards[$StandardKey]
                        $Value = $StandardObject.Value

                        if ($StandardObject.LastRefresh) {
                            $RefreshTime = [DateTime]::Parse($StandardObject.LastRefresh)
                            if (-not $LatestDataCollection -or $RefreshTime -gt $LatestDataCollection) {
                                $LatestDataCollection = $RefreshTime
                            }
                        }

                        $IsCompliant = ($Value -eq $true)
                        $IsLicenseMissing = ($Value -is [string] -and $Value -like 'License Missing:*')

                        $ComplianceStatus = if ($IsReportingDisabled) {
                            'Reporting Disabled'
                        } elseif ($IsCompliant) {
                            'Compliant'
                        } elseif ($IsLicenseMissing) {
                            'License Missing'
                        } else {
                            'Non-Compliant'
                        }

                        $StandardValueJson = $Value | ConvertTo-Json -Depth 5 -Compress

                        $ComparisonResults.Add([PSCustomObject]@{
                                StandardName      = $StandardKey
                                Compliant         = $IsCompliant
                                StandardValue     = $StandardValueJson
                                ComplianceStatus  = $ComplianceStatus
                                ReportingDisabled = $IsReportingDisabled
                            })
                    } else {
                        $ComplianceStatus = if ($IsReportingDisabled) {
                            'Reporting Disabled'
                        } else {
                            'Non-Compliant'
                        }

                        $ComparisonResults.Add([PSCustomObject]@{
                                StandardName      = $StandardKey
                                Compliant         = $false
                                StandardValue     = 'NOT FOUND'
                                ComplianceStatus  = $ComplianceStatus
                                ReportingDisabled = $IsReportingDisabled
                            })
                    }
                }

                # Replace Where-Object with direct counting
                $CompliantStandards = 0
                $NonCompliantStandards = 0
                $LicenseMissingStandards = 0
                $ReportingDisabledStandardsCount = 0

                foreach ($item in $ComparisonResults) {
                    if ($item.ComplianceStatus -eq 'Compliant') { $CompliantStandards++ }
                    elseif ($item.ComplianceStatus -eq 'Non-Compliant') { $NonCompliantStandards++ }
                    elseif ($item.ComplianceStatus -eq 'License Missing') { $LicenseMissingStandards++ }
                    if ($item.ReportingDisabled) { $ReportingDisabledStandardsCount++ }
                }

                $AlignmentPercentage = if (($AllCount - $ReportingDisabledStandardsCount) -gt 0) {
                    [Math]::Round(($CompliantStandards / ($AllCount - $ReportingDisabledStandardsCount)) * 100)
                } else {
                    0
                }

                $LicenseMissingPercentage = if ($AllCount -gt 0) {
                    [Math]::Round(($LicenseMissingStandards / $AllCount) * 100)
                } else {
                    0
                }

                $Result = [PSCustomObject]@{
                    TenantFilter             = $TenantName
                    StandardName             = $Template.templateName
                    StandardId               = $Template.GUID
                    standardType             = $Template.type
                    standardSettings         = $Template.Standards
                    driftAlertEmail          = $Template.driftAlertEmail
                    driftAlertWebhook        = $Template.driftAlertWebhook
                    driftAlertDisableEmail   = $Template.driftAlertDisableEmail
                    AlignmentScore           = $AlignmentPercentage
                    LicenseMissingPercentage = $LicenseMissingPercentage
                    CombinedScore            = $AlignmentPercentage + $LicenseMissingPercentage
                    CompliantStandards       = $CompliantStandards
                    NonCompliantStandards    = $NonCompliantStandards
                    LicenseMissingStandards  = $LicenseMissingStandards
                    TotalStandards           = $AllCount
                    ReportingDisabledCount   = $ReportingDisabledStandardsCount
                    LatestDataCollection     = if ($LatestDataCollection) { $LatestDataCollection } else { $null }
                    ComparisonDetails        = $ComparisonResults
                }

                $Results.Add($Result)
            }
        }

        return $Results
    } catch {
        Write-Error "Error getting tenant alignment data: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        throw
    }
}
