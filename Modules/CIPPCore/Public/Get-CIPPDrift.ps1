function Get-CIPPDrift {
    <#
    .SYNOPSIS
        Gets comprehensive drift information for a tenant including standards compliance and policy deviations
    .DESCRIPTION
        This function collects drift information by executing Get-CIPPTenantAlignment and comparing
        tenant policies against standards templates. It identifies both standards deviations and
        extra policies not defined in templates.
    .PARAMETER TenantFilter
        The tenant to get drift data for
    .PARAMETER TemplateId
        Optional specific template GUID to check drift for. If not specified, processes all templates.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPDrift -TenantFilter "contoso.onmicrosoft.com"
    .EXAMPLE
        Get-CIPPDrift -TenantFilter "contoso.onmicrosoft.com" -TemplateId "12345-67890-abcdef"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$TemplateId,

        [Parameter(Mandatory = $false)]
        [switch]$AllTenants
    )

    $IntuneCapable = Test-CIPPStandardLicense -StandardName 'IntuneTemplate_general' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')
    $ConditionalAccessCapable = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_general' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2')
    $IntuneTable = Get-CippTable -tablename 'templates'

    # Always load templates for display name resolution, even if tenant doesn't have licenses
    $IntuneFilter = "PartitionKey eq 'IntuneTemplate'"
    $RawIntuneTemplates = (Get-CIPPAzDataTableEntity @IntuneTable -Filter $IntuneFilter)
    $AllIntuneTemplates = $RawIntuneTemplates | ForEach-Object {
        try {
            $JSONData = $_.JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
            $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
            $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
            $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $JSONData.Description -Force
            $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $JSONData.Type -Force
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
            $data
        } catch {
            # Skip invalid templates
        }
    } | Sort-Object -Property displayName

    # Load all CA templates
    $CAFilter = "PartitionKey eq 'CATemplate'"
    $RawCATemplates = (Get-CIPPAzDataTableEntity @IntuneTable -Filter $CAFilter)
    $AllCATemplates = $RawCATemplates | ForEach-Object {
        try {
            $data = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
            $data
        } catch {
            # Skip invalid templates
        }
    } | Sort-Object -Property displayName

    try {
        $AlignmentData = Get-CIPPTenantAlignment -TenantFilter $TenantFilter -TemplateId $TemplateId | Where-Object -Property standardType -EQ 'drift'

        if (-not $AlignmentData) {
            Write-Warning "No alignment data found for tenant $TenantFilter"
            return @()
        }

        # Get existing drift states from the tenantDrift table
        $DriftTable = Get-CippTable -tablename 'tenantDrift'
        $DriftFilter = "PartitionKey eq '$TenantFilter'"
        $ExistingDriftStates = @{}
        try {
            $DriftEntities = Get-CIPPAzDataTableEntity @DriftTable -Filter $DriftFilter
            foreach ($Entity in $DriftEntities) {
                $ExistingDriftStates[$Entity.StandardName] = $Entity
            }
        } catch {
            Write-Warning "Failed to get existing drift states: $($_.Exception.Message)"
        }

        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Alignment in $AlignmentData) {
            # Initialize deviation collections
            $StandardsDeviations = [System.Collections.Generic.List[object]]::new()
            $PolicyDeviations = [System.Collections.Generic.List[object]]::new()

            # Process standards compliance deviations
            if ($Alignment.ComparisonDetails) {
                foreach ($ComparisonItem in $Alignment.ComparisonDetails) {
                    if ($ComparisonItem.Compliant -ne $true) {
                        $Status = if ($ExistingDriftStates.ContainsKey($ComparisonItem.StandardName)) {
                            $ExistingDriftStates[$ComparisonItem.StandardName].Status
                        } else {
                            'New'
                        }
                        # Reset displayName and description for each deviation to prevent carryover from previous iterations
                        $displayName = $null
                        $standardDescription = $null
                        #if the $ComparisonItem.StandardName contains *IntuneTemplate*, then it's an Intune policy deviation, and we need to grab the correct displayname from the template table
                        if ($ComparisonItem.StandardName -like '*IntuneTemplate*') {
                            # Extract GUID from format like: standards.IntuneTemplate.{GUID}.IntuneTemplate.json
                            # Split by '.' and find the element that looks like a GUID (contains hyphens and is 36 chars)
                            $Parts = $ComparisonItem.StandardName.Split('.')
                            $CompareGuid = $Parts | Where-Object { $_ -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' } | Select-Object -First 1

                            if ($CompareGuid) {
                                Write-Verbose "Extracted Intune GUID: $CompareGuid from $($ComparisonItem.StandardName)"
                                $Template = $AllIntuneTemplates | Where-Object { $_.GUID -match "$CompareGuid" }
                                if ($Template) {
                                    $displayName = $Template.displayName
                                    $standardDescription = $Template.description
                                    Write-Verbose "Found Intune template: $displayName"
                                } else {
                                    Write-Warning "Intune template not found for GUID: $CompareGuid"
                                }
                            } else {
                                Write-Verbose "No valid GUID found in: $($ComparisonItem.StandardName)"
                            }
                        }
                        # Handle Conditional Access templates
                        if ($ComparisonItem.StandardName -like '*ConditionalAccessTemplate*') {
                            # Extract GUID from format like: standards.ConditionalAccessTemplate.{GUID}.CATemplate.json
                            # Split by '.' and find the element that looks like a GUID (contains hyphens and is 36 chars)
                            $Parts = $ComparisonItem.StandardName.Split('.')
                            $CompareGuid = $Parts | Where-Object { $_ -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' } | Select-Object -First 1

                            if ($CompareGuid) {
                                Write-Verbose "Extracted CA GUID: $CompareGuid from $($ComparisonItem.StandardName)"
                                $Template = $AllCATemplates | Where-Object { $_.GUID -match "$CompareGuid" }
                                if ($Template) {
                                    $displayName = $Template.displayName
                                    $standardDescription = $Template.description
                                    Write-Verbose "Found CA template: $displayName"
                                } else {
                                    Write-Warning "CA template not found for GUID: $CompareGuid"
                                }
                            } else {
                                Write-Verbose "No valid GUID found in: $($ComparisonItem.StandardName)"
                            }
                        }
                        $reason = if ($ExistingDriftStates.ContainsKey($ComparisonItem.StandardName)) { $ExistingDriftStates[$ComparisonItem.StandardName].Reason }
                        $User = if ($ExistingDriftStates.ContainsKey($ComparisonItem.StandardName)) { $ExistingDriftStates[$ComparisonItem.StandardName].User }
                        $StandardsDeviations.Add([PSCustomObject]@{
                                standardName        = $ComparisonItem.StandardName
                                standardDisplayName = $displayName
                                standardDescription = $standardDescription
                                receivedValue       = $ComparisonItem.StandardValue
                                state               = 'current'
                                Status              = $Status
                                Reason              = $reason
                                lastChangedByUser   = $User
                                LicenseAvailable    = $ComparisonItem.LicenseAvailable
                                CurrentValue        = $ComparisonItem.CurrentValue
                                ExpectedValue       = $ComparisonItem.ExpectedValue
                            })
                    }
                }
            }

            # Perform full policy collection
            if ($IntuneCapable) {
                # Always get live data when not in AllTenants mode
                $IntuneRequests = @(
                    @{
                        id     = 'deviceAppManagement/managedAppPolicies'
                        url    = 'deviceAppManagement/managedAppPolicies?$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/deviceCompliancePolicies'
                        url    = 'deviceManagement/deviceCompliancePolicies?$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/groupPolicyConfigurations'
                        url    = 'deviceManagement/groupPolicyConfigurations?$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/deviceConfigurations'
                        url    = 'deviceManagement/deviceConfigurations?$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/configurationPolicies'
                        url    = 'deviceManagement/configurationPolicies?$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/windowsDriverUpdateProfiles'
                        url    = 'deviceManagement/windowsDriverUpdateProfiles?$top=200'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/windowsFeatureUpdateProfiles'
                        url    = 'deviceManagement/windowsFeatureUpdateProfiles?$top=200'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/windowsQualityUpdatePolicies'
                        url    = 'deviceManagement/windowsQualityUpdatePolicies?$top=200'
                        method = 'GET'
                    }
                    @{
                        id     = 'deviceManagement/windowsQualityUpdateProfiles'
                        url    = 'deviceManagement/windowsQualityUpdateProfiles?$top=200'
                        method = 'GET'
                    }
                )

                $TenantIntunePolicies = [System.Collections.Generic.List[object]]::new()

                try {
                    $IntuneGraphRequest = New-GraphBulkRequest -Requests $IntuneRequests -tenantid $TenantFilter -asapp $true

                    foreach ($Request in $IntuneGraphRequest) {
                        if ($Request.body.value) {
                            foreach ($Policy in $Request.body.value) {
                                $TenantIntunePolicies.Add([PSCustomObject]@{
                                        Type   = $Request.id
                                        Policy = $Policy
                                    })
                            }
                        }
                    }
                } catch {
                    Write-Warning "Failed to get Intune policies: $($_.Exception.Message)"
                }
            }
            # Get Conditional Access policies
            if ($ConditionalAccessCapable) {
                try {
                    $CARequests = @(
                        @{
                            id     = 'policies'
                            url    = 'identity/conditionalAccess/policies?$top=999'
                            method = 'GET'
                        }
                    )
                    $CAGraphRequest = New-GraphBulkRequest -Requests $CARequests -tenantid $TenantFilter -asapp $true
                    $TenantCAPolicies = ($CAGraphRequest | Where-Object { $_.id -eq 'policies' }).body.value
                } catch {
                    Write-Warning "Failed to get Conditional Access policies: $($_.Exception.Message)"
                    $TenantCAPolicies = @()
                }
            }

            if ($Alignment.standardSettings) {
                if ($Alignment.standardSettings.IntuneTemplate) {
                    $IntuneTemplateIds = [System.Collections.Generic.List[string]]::new()
                    foreach ($Template in $Alignment.standardSettings.IntuneTemplate) {
                        if ($Template.TemplateList.value) {
                            $IntuneTemplateIds.Add($Template.TemplateList.value)
                        }
                        if ($Template.'TemplateList-Tags'.rawData.templates) {
                            foreach ($TagTemplate in $Template.'TemplateList-Tags'.rawData.templates) {
                                $IntuneTemplateIds.Add($TagTemplate.GUID)
                            }
                        }
                    }
                }
                if ($Alignment.standardSettings.ConditionalAccessTemplate) {
                    $CATemplateIds = $Alignment.standardSettings.ConditionalAccessTemplate.TemplateList | ForEach-Object { $_.value }
                }
            }

            # Get actual CA templates from templates table
            if ($CATemplateIds.Count -gt 0) {
                try {
                    $TemplateCATemplates = $AllCATemplates | Where-Object { $_.GUID -in $CATemplateIds }
                } catch {
                    Write-Warning "Failed to get CA templates: $($_.Exception.Message)"
                }
            }

            # Get actual Intune templates from templates table
            if ($IntuneTemplateIds.Count -gt 0) {
                try {

                    $TemplateIntuneTemplates = $AllIntuneTemplates | Where-Object { $_.GUID -in $IntuneTemplateIds }
                } catch {
                    Write-Warning "Failed to get Intune templates: $($_.Exception.Message)"
                }
            }

            # Check for extra Intune policies not in template
            foreach ($TenantPolicy in $TenantIntunePolicies) {
                $PolicyFound = $false
                $tenantPolicy.policy | Add-Member -MemberType NoteProperty -Name 'URLName' -Value $TenantPolicy.Type -Force
                $TenantPolicyName = if ($TenantPolicy.Policy.displayName) { $TenantPolicy.Policy.displayName } else { $TenantPolicy.Policy.name }
                foreach ($TemplatePolicy in $TemplateIntuneTemplates) {
                    $TemplatePolicyName = if ($TemplatePolicy.displayName) { $TemplatePolicy.displayName } else { $TemplatePolicy.name }

                    if ($TemplatePolicy.displayName -eq $TenantPolicy.Policy.displayName -or
                        $TemplatePolicy.name -eq $TenantPolicy.Policy.name -or
                        $TemplatePolicy.displayName -eq $TenantPolicy.Policy.name -or
                        $TemplatePolicy.name -eq $TenantPolicy.Policy.displayName) {
                        $PolicyFound = $true
                        break
                    }
                }

                if (-not $PolicyFound) {
                    $PolicyKey = "IntuneTemplates.$($TenantPolicy.Policy.id)"
                    $Status = if ($ExistingDriftStates.ContainsKey($PolicyKey)) {
                        $ExistingDriftStates[$PolicyKey].Status
                    } else {
                        'New'
                    }
                    $reason = if ($ExistingDriftStates.ContainsKey($PolicyKey)) { $ExistingDriftStates[$PolicyKey].Reason }
                    $User = if ($ExistingDriftStates.ContainsKey($PolicyKey)) { $ExistingDriftStates[$PolicyKey].User }
                    $PolicyDeviation = [PSCustomObject]@{
                        standardName        = $PolicyKey
                        standardDisplayName = "Intune - $TenantPolicyName"
                        expectedValue       = 'This policy only exists in the tenant, not in the template.'
                        receivedValue       = ($TenantPolicy.Policy | ConvertTo-Json -Depth 10 -Compress)
                        state               = 'current'
                        Status              = $Status
                        Reason              = $reason
                        lastChangedByUser   = $User
                    }
                    $PolicyDeviations.Add($PolicyDeviation)
                }
            }

            # Check for extra Conditional Access policies not in template
            foreach ($TenantCAPolicy in $TenantCAPolicies) {
                $PolicyFound = $false

                foreach ($TemplateCAPolicy in $TemplateCATemplates) {
                    if ($TemplateCAPolicy.displayName -eq $TenantCAPolicy.displayName) {
                        $PolicyFound = $true
                        break
                    }
                }

                if (-not $PolicyFound) {
                    $PolicyKey = "ConditionalAccessTemplates.$($TenantCAPolicy.id)"
                    $Status = if ($ExistingDriftStates.ContainsKey($PolicyKey)) {
                        $ExistingDriftStates[$PolicyKey].Status
                    } else {
                        'New'
                    }
                    $reason = if ($ExistingDriftStates.ContainsKey($PolicyKey)) { $ExistingDriftStates[$PolicyKey].Reason }
                    $User = if ($ExistingDriftStates.ContainsKey($PolicyKey)) { $ExistingDriftStates[$PolicyKey].User }
                    $PolicyDeviation = [PSCustomObject]@{
                        standardName        = $PolicyKey
                        standardDisplayName = "Conditional Access - $($TenantCAPolicy.displayName)"
                        expectedValue       = 'This policy only exists in the tenant, not in the template.'
                        receivedValue       = (ConvertTo-Json -InputObject $TenantCAPolicy -Depth 10 -Compress)
                        state               = 'current'
                        Status              = $Status
                        Reason              = $reason
                        lastChangedByUser   = $User
                    }
                    $PolicyDeviations.Add($PolicyDeviation)
                }
            }


            # Combine all deviations and filter by status
            $AllDeviations = [System.Collections.Generic.List[object]]::new()
            $AllDeviations.AddRange($StandardsDeviations)
            $AllDeviations.AddRange($PolicyDeviations)

            # Filter deviations by status for counting
            $NewDeviations = $AllDeviations | Where-Object { $_.Status -eq 'New' }
            $AcceptedDeviations = $AllDeviations | Where-Object { $_.Status -eq 'Accepted' }
            $DeniedDeviations = $AllDeviations | Where-Object { $_.Status -like 'Denied*' }
            $CustomerSpecificDeviations = $AllDeviations | Where-Object { $_.Status -eq 'CustomerSpecific' }

            # Current deviations are New + Denied (not accepted or customer specific)
            $CurrentDeviations = $AllDeviations | Where-Object { $_.Status -in @('New', 'Denied') }

            $Result = [PSCustomObject]@{
                tenantFilter                    = $TenantFilter
                standardName                    = $Alignment.StandardName
                standardId                      = $Alignment.StandardId
                alignmentScore                  = $Alignment.AlignmentScore
                acceptedDeviationsCount         = $AcceptedDeviations.Count
                currentDeviationsCount          = $CurrentDeviations.Count
                deniedDeviationsCount           = $DeniedDeviations.Count
                customerSpecificDeviationsCount = $CustomerSpecificDeviations.Count
                newDeviationsCount              = $NewDeviations.Count
                alignedCount                    = $Alignment.CompliantStandards
                currentDeviations               = @($CurrentDeviations)
                acceptedDeviations              = @($AcceptedDeviations)
                customerSpecificDeviations      = @($CustomerSpecificDeviations)
                deniedDeviations                = @($DeniedDeviations)
                allDeviations                   = @($AllDeviations)
                latestDataCollection            = $Alignment.LatestDataCollection
                driftSettings                   = $AlignmentData
            }

            $Results.Add($Result)
        }

        return @($Results)

    } catch {
        Write-Error "Error getting drift data: $($_.Exception.Message)"
        throw
    }
}
