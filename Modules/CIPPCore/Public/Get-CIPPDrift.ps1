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


    $IntuneTable = Get-CippTable -tablename 'templates'
    $IntuneFilter = "PartitionKey eq 'IntuneTemplate'"
    $RawIntuneTemplates = (Get-CIPPAzDataTableEntity @IntuneTable -Filter $IntuneFilter)
    $AllIntuneTemplates = $RawIntuneTemplates | ForEach-Object {
        try {
            $JSONData = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
            $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
            $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
            $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $JSONData.Description -Force
            $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $JSONData.Type -Force
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
                        #if the $ComparisonItem.StandardName contains *intuneTemplate*, then it's an Intune policy deviation, and we need to grab the correct displayname from the template table
                        if ($ComparisonItem.StandardName -like '*intuneTemplate*') {
                            $CompareGuid = $ComparisonItem.StandardName.Split('.') | Select-Object -Index 2
                            Write-Host "Extracted GUID: $CompareGuid"
                            $Template = $AllIntuneTemplates | Where-Object { $_.GUID -like "*$CompareGuid*" }
                            if ($Template) { $displayName = $Template.displayName }
                        }
                        $reason = if ($ExistingDriftStates.ContainsKey($ComparisonItem.StandardName)) { $ExistingDriftStates[$ComparisonItem.StandardName].Reason }
                        $User = if ($ExistingDriftStates.ContainsKey($ComparisonItem.StandardName)) { $ExistingDriftStates[$ComparisonItem.StandardName].User }
                        $StandardsDeviations.Add([PSCustomObject]@{
                                standardName        = $ComparisonItem.StandardName
                                standardDisplayName = $displayName
                                expectedValue       = 'Compliant'
                                receivedValue       = $ComparisonItem.StandardValue
                                state               = 'current'
                                Status              = $Status
                                Reason              = $reason
                                lastChangedByUser   = $User
                            })
                    }
                }
            }

            # Perform full policy collection

            # Always get live data when not in AllTenants mode
            $IntuneRequests = @(
                @{
                    id     = 'deviceAppManagement/managedAppPolicies'
                    url    = 'deviceAppManagement/managedAppPolicies'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/deviceCompliancePolicies'
                    url    = 'deviceManagement/deviceCompliancePolicies'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/groupPolicyConfigurations'
                    url    = 'deviceManagement/groupPolicyConfigurations'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/deviceConfigurations'
                    url    = 'deviceManagement/deviceConfigurations'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/configurationPolicies'
                    url    = 'deviceManagement/configurationPolicies'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/windowsDriverUpdateProfiles'
                    url    = 'deviceManagement/windowsDriverUpdateProfiles'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/windowsFeatureUpdateProfiles'
                    url    = 'deviceManagement/windowsFeatureUpdateProfiles'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/windowsQualityUpdatePolicies'
                    url    = 'deviceManagement/windowsQualityUpdatePolicies'
                    method = 'GET'
                }
                @{
                    id     = 'deviceManagement/windowsQualityUpdateProfiles'
                    url    = 'deviceManagement/windowsQualityUpdateProfiles'
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

            # Get Conditional Access policies
            try {
                $CARequests = @(
                    @{
                        id     = 'policies'
                        url    = 'identity/conditionalAccess/policies'
                        method = 'GET'
                    }
                )
                $CAGraphRequest = New-GraphBulkRequest -Requests $CARequests -tenantid $TenantFilter -asapp $true
                $TenantCAPolicies = ($CAGraphRequest | Where-Object { $_.id -eq 'policies' }).body.value
            } catch {
                Write-Warning "Failed to get Conditional Access policies: $($_.Exception.Message)"
                $TenantCAPolicies = @()
            }

            if ($Alignment.standardSettings) {
                if ($Alignment.standardSettings.IntuneTemplate) {
                    $IntuneTemplateIds = $Alignment.standardSettings.IntuneTemplate.TemplateList | ForEach-Object { $_.value }
                }
                if ($Alignment.standardSettings.ConditionalAccessTemplate) {
                    $CATemplateIds = $Alignment.standardSettings.ConditionalAccessTemplate.TemplateList | ForEach-Object { $_.value }
                }
            }

            # Get actual CA templates from templates table
            if ($CATemplateIds.Count -gt 0) {
                try {
                    $CATable = Get-CippTable -tablename 'templates'
                    $CAFilter = "PartitionKey eq 'CATemplate'"
                    $AllCATemplates = (Get-CIPPAzDataTableEntity @CATable -Filter $CAFilter) | ForEach-Object {
                        $data = $_.JSON | ConvertFrom-Json -Depth 100
                        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
                        $data
                    } | Sort-Object -Property displayName

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
                    $PolicyDeviation = [PSCustomObject]@{
                        standardName        = $PolicyKey
                        standardDisplayName = "Intune - $TenantPolicyName"
                        expectedValue       = 'This policy only exists in the tenant, not in the template.'
                        receivedValue       = ($TenantPolicy.Policy | ConvertTo-Json -Depth 10 -Compress)
                        state               = 'current'
                        Status              = $Status
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
                    $PolicyDeviation = [PSCustomObject]@{
                        standardName        = $PolicyKey
                        standardDisplayName = "Conditional Access - $($TenantCAPolicy.displayName)"
                        expectedValue       = 'This policy only exists in the tenant, not in the template.'
                        receivedValue       = ($TenantCAPolicy | ConvertTo-Json -Depth 10 -Compress)
                        state               = 'current'
                        Status              = $Status
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
            }

            $Results.Add($Result)
        }

        return @($Results)

    } catch {
        Write-Error "Error getting drift data: $($_.Exception.Message)"
        throw
    }
}
