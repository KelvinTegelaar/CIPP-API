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

    try {
        # Get all standard templates
        $TemplateTable = Get-CippTable -tablename 'templates'
        $TemplateFilter = "PartitionKey eq 'StandardsTemplateV2'"

        $Templates = (Get-CIPPAzDataTableEntity @TemplateTable -Filter $TemplateFilter) | ForEach-Object {
            $JSON = $_.JSON -replace '"Action":', '"action":'
            try {
                $RowKey = $_.RowKey
                $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
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
        $StandardsTable = Get-CIPPTable -TableName 'CippStandardsReports'
        $AllStandards = Get-CIPPAzDataTableEntity @StandardsTable -Filter "PartitionKey ne 'StandardReport'"

        # Filter by tenant if specified
        $Standards = if ($TenantFilter) {
            $AllStandards | Where-Object { $_.PartitionKey -eq $TenantFilter }
        } else {
            $AllStandards
        }

        # Build tenant standards data structure
        $TenantStandards = @{}
        foreach ($Standard in $Standards) {
            $FieldName = $Standard.RowKey
            $FieldValue = $Standard.Value
            $Tenant = $Standard.PartitionKey

            # Process field value
            if ($FieldValue -is [System.Boolean]) {
                $FieldValue = [bool]$FieldValue
            } elseif ($FieldValue -like '*{*') {
                $FieldValue = ConvertFrom-Json -Depth 100 -InputObject $FieldValue -ErrorAction SilentlyContinue
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
                $TenantValues = $Template.tenantFilter | ForEach-Object {
                    if ($_.type -eq 'group') {
                        (Get-TenantGroups -GroupId $_.value).members.defaultDomainName
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
            $ReportingEnabledStandards = ($StandardsData | Where-Object { $_.ReportingEnabled }).StandardId
            $ReportingDisabledStandards = ($StandardsData | Where-Object { -not $_.ReportingEnabled }).StandardId

            foreach ($TenantName in $TenantStandards.Keys) {
                if (-not $AppliestoAllTenants -and $TenantName -notin $TemplateAssignedTenants) {
                    continue
                }

                $AllCount = $AllStandards.Count
                $LatestDataCollection = $null

                $ComparisonTable = foreach ($StandardKey in $AllStandards) {
                    $IsReportingDisabled = $ReportingDisabledStandards -contains $StandardKey

                    if ($TenantStandards[$TenantName].ContainsKey($StandardKey)) {
                        $StandardObject = $TenantStandards[$TenantName][$StandardKey]
                        $Value = $StandardObject.Value

                        if ($StandardObject.LastRefresh) {
                            $RefreshTime = [DateTime]::Parse($StandardObject.LastRefresh)
                            if (-not $LatestDataCollection -or $RefreshTime -gt $LatestDataCollection) {
                                $LatestDataCollection = $RefreshTime
                            }
                        }

                        $IsCompliant = ($Value -eq $true)
                        $IsLicenseMissing = ($Value -is [string] -and $Value -like 'License Missing:*')

                        if ($IsReportingDisabled) {
                            $ComplianceStatus = 'Reporting Disabled'
                        } elseif ($IsCompliant) {
                            $ComplianceStatus = 'Compliant'
                        } elseif ($IsLicenseMissing) {
                            $ComplianceStatus = 'License Missing'
                        } else {
                            $ComplianceStatus = 'Non-Compliant'
                        }

                        [PSCustomObject]@{
                            StandardName      = $StandardKey
                            Compliant         = $IsCompliant
                            StandardValue     = ($Value | ConvertTo-Json -Compress)
                            ComplianceStatus  = $ComplianceStatus
                            ReportingDisabled = $IsReportingDisabled
                        }
                    } else {
                        if ($IsReportingDisabled) {
                            $ComplianceStatus = 'Reporting Disabled'
                        } else {
                            $ComplianceStatus = 'Non-Compliant'
                        }

                        [PSCustomObject]@{
                            StandardName      = $StandardKey
                            Compliant         = $false
                            StandardValue     = 'NOT FOUND'
                            ComplianceStatus  = $ComplianceStatus
                            ReportingDisabled = $IsReportingDisabled
                        }
                    }
                }

                $CompliantStandards = ($ComparisonTable | Where-Object { $_.ComplianceStatus -eq 'Compliant' }).Count
                $NonCompliantStandards = ($ComparisonTable | Where-Object { $_.ComplianceStatus -eq 'Non-Compliant' }).Count
                $LicenseMissingStandards = ($ComparisonTable | Where-Object { $_.ComplianceStatus -eq 'License Missing' }).Count
                $ReportingDisabledStandardsCount = ($ComparisonTable | Where-Object { $_.ReportingDisabled }).Count

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
                    AlignmentScore           = $AlignmentPercentage
                    LicenseMissingPercentage = $LicenseMissingPercentage
                    CombinedScore            = $AlignmentPercentage + $LicenseMissingPercentage
                    CompliantStandards       = $CompliantStandards
                    NonCompliantStandards    = $NonCompliantStandards
                    LicenseMissingStandards  = $LicenseMissingStandards
                    TotalStandards           = $AllCount
                    ReportingDisabledCount   = $ReportingDisabledStandardsCount
                    LatestDataCollection     = if ($LatestDataCollection) { $LatestDataCollection } else { $null }
                    ComparisonDetails        = $ComparisonTable
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
