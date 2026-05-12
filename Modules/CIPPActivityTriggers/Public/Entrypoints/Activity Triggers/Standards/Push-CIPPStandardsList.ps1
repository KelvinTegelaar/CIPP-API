function Push-CIPPStandardsList {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $runManually = $Item.runManually
    $TemplateId = $Item.TemplateId

    try {
        # Get standards for this tenant
        $GetStandardParams = @{
            TenantFilter = $TenantFilter
            runManually  = $runManually
        }
        if ($TemplateId) {
            $GetStandardParams['TemplateId'] = $TemplateId
        }

        $AllStandards = Get-CIPPStandards @GetStandardParams

        if ($AllStandards.Count -eq 0) {
            Write-Information "No standards found for tenant $TenantFilter"
            return @()
        }
        Write-Host "Retrieved $($AllStandards.Count) standards for tenant $TenantFilter before filtering."
        # Build hashtable for efficient lookup
        $ComputedStandards = @{}
        foreach ($Standard in $AllStandards) {
            $Key = "$($Standard.Standard)|$($Standard.Settings.TemplateList.value)"
            $ComputedStandards[$Key] = $Standard
        }

        # Check if IntuneTemplate standards are present
        $IntuneTemplateFound = ($ComputedStandards.Keys.Where({ $_ -like '*IntuneTemplate*' }, 'First').Count -gt 0)

        if ($IntuneTemplateFound) {
            # Perform license check
            $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneTemplate_general' -TenantFilter $TenantFilter -Preset Intune

            if (-not $TestResult) {
                # Remove IntuneTemplate standards and set compare fields
                $IntuneKeys = @($ComputedStandards.Keys | Where-Object { $_ -like '*IntuneTemplate*' })
                $BulkFields = [System.Collections.Generic.List[object]]::new()

                foreach ($Key in $IntuneKeys) {
                    $TemplateKey = ($Key -split '\|', 2)[1]
                    if ($TemplateKey) {
                        $BulkFields.Add([PSCustomObject]@{
                                FieldName  = "standards.IntuneTemplate.$TemplateKey"
                                FieldValue = 'This tenant does not have the required license for this standard.'
                            })
                    }
                    [void]$ComputedStandards.Remove($Key)
                }

                if ($BulkFields.Count -gt 0) {
                    Set-CIPPStandardsCompareField -TenantFilter $TenantFilter -BulkFields $BulkFields
                }

                Write-Information "Removed IntuneTemplate standards for $TenantFilter - missing required license"
            } else {
                # License valid - check policy timestamps to filter unchanged templates
                # URLs are fully specified per-type because Graph OData support varies:
                # - Catalog uses 'name' not 'displayName'
                # - windows update types don't support $orderby
                # - App protection types only work via managedAppPolicies
                $BulkRequests = @(
                    @{ id = 'Device'; url = "deviceManagement/deviceConfigurations?`$orderby=lastModifiedDateTime desc&`$select=id,lastModifiedDateTime,displayName&`$top=999"; method = 'GET' }
                    @{ id = 'Catalog'; url = "deviceManagement/configurationPolicies?`$orderby=lastModifiedDateTime desc&`$select=id,lastModifiedDateTime,name&`$top=999"; method = 'GET' }
                    @{ id = 'Admin'; url = "deviceManagement/groupPolicyConfigurations?`$orderby=lastModifiedDateTime desc&`$select=id,lastModifiedDateTime,displayName&`$top=999"; method = 'GET' }
                    @{ id = 'deviceCompliancePolicies'; url = "deviceManagement/deviceCompliancePolicies?`$orderby=lastModifiedDateTime desc&`$select=id,lastModifiedDateTime,displayName&`$top=999"; method = 'GET' }
                    @{ id = 'AppProtection'; url = "deviceAppManagement/managedAppPolicies?`$orderby=lastModifiedDateTime desc&`$select=id,lastModifiedDateTime,displayName&`$top=999"; method = 'GET' }
                    @{ id = 'AppConfiguration'; url = "deviceAppManagement/mobileAppConfigurations?`$orderby=lastModifiedDateTime desc&`$select=id,lastModifiedDateTime,displayName&`$top=200"; method = 'GET' }
                    @{ id = 'windowsDriverUpdateProfiles'; url = "deviceManagement/windowsDriverUpdateProfiles?`$select=id,lastModifiedDateTime,displayName&`$top=200"; method = 'GET' }
                    @{ id = 'windowsFeatureUpdateProfiles'; url = "deviceManagement/windowsFeatureUpdateProfiles?`$select=id,lastModifiedDateTime,displayName&`$top=200"; method = 'GET' }
                    @{ id = 'windowsQualityUpdatePolicies'; url = "deviceManagement/windowsQualityUpdatePolicies?`$select=id,lastModifiedDateTime,displayName&`$top=200"; method = 'GET' }
                    @{ id = 'windowsQualityUpdateProfiles'; url = "deviceManagement/windowsQualityUpdateProfiles?`$select=id,lastModifiedDateTime,displayName&`$top=200"; method = 'GET' }
                )

                try {
                    $TrackingTable = Get-CippTable -tablename 'IntunePolicyTypeTracking'
                    $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter -NoPaginateIds @($BulkRequests | ForEach-Object { $_.id })
                    $PolicyTimestamps = @{}
                    $PolicyNamesByType = @{}

                    foreach ($Result in $BulkResults) {
                        $FirstPolicy = if ($Result.body.value) { $Result.body.value[0] } else { $null }
                        $GraphTime = $FirstPolicy.lastModifiedDateTime
                        $GraphId = $FirstPolicy.id
                        $GraphCount = ($Result.body.value | Measure-Object).Count
                        $Cached = Get-CIPPAzDataTableEntity @TrackingTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$($Result.id)'"

                        $CountChanged = $false
                        if ($Cached -and $Cached.PolicyCount -ne $null) {
                            $CountChanged = ($GraphCount -ne $Cached.PolicyCount)
                        }

                        $IdChanged = $false
                        if ($GraphId -and $Cached -and $Cached.LatestPolicyId) {
                            $IdChanged = ($GraphId -ne $Cached.LatestPolicyId)
                        }

                        if ($GraphTime) {
                            $GraphTimeUtc = ([DateTime]$GraphTime).ToUniversalTime()
                            if ($Cached -and $Cached.LatestPolicyModified -and -not $IdChanged -and -not $CountChanged) {
                                $CachedTimeUtc = ([DateTimeOffset]$Cached.LatestPolicyModified).UtcDateTime
                                $TimeDiff = [Math]::Abs(($GraphTimeUtc - $CachedTimeUtc).TotalSeconds)
                                $Changed = ($TimeDiff -gt 60)
                            } else {
                                $Changed = $true
                            }
                            Add-CIPPAzDataTableEntity @TrackingTable -Entity @{
                                PartitionKey         = $TenantFilter
                                RowKey               = $Result.id
                                LatestPolicyModified = $GraphTime
                                LatestPolicyId       = $GraphId
                                PolicyCount          = $GraphCount
                            } -Force | Out-Null
                        } elseif ($Cached -and $Cached.PolicyCount -ne $null) {
                            # No timestamp available - fall back to count-based detection
                            $Changed = $CountChanged -or $IdChanged
                            Add-CIPPAzDataTableEntity @TrackingTable -Entity @{
                                PartitionKey   = $TenantFilter
                                RowKey         = $Result.id
                                LatestPolicyId = $GraphId
                                PolicyCount    = $GraphCount
                            } -Force | Out-Null
                        } else {
                            # No timestamp and no prior cache entry - treat as changed and seed the cache
                            $Changed = $true
                            Add-CIPPAzDataTableEntity @TrackingTable -Entity @{
                                PartitionKey   = $TenantFilter
                                RowKey         = $Result.id
                                LatestPolicyId = $GraphId
                                PolicyCount    = $GraphCount
                            } -Force | Out-Null
                        }

                        $PolicyTimestamps[$Result.id] = $Changed
                        $PolicyNamesByType[$Result.id] = @($Result.body.value | ForEach-Object { $_.displayName; $_.name } | Where-Object { $_ })
                        Write-Host "POLICY TYPE CHANGE CHECK: $($Result.id) -> Changed=$Changed (GraphCount=$GraphCount, CachedCount=$($Cached.PolicyCount), IdChanged=$IdChanged)"
                    }

                    # Filter unchanged templates
                    $TemplateTable = Get-CippTable -tablename 'templates'
                    $IntuneKeys = @($ComputedStandards.Keys | Where-Object { $_ -like '*IntuneTemplate*' })
                    Write-Host "INTUNE FILTER: Processing $($IntuneKeys.Count) IntuneTemplate standards for $TenantFilter"

                    # Build compliance lookup - keyed by "standards.IntuneTemplate.<templateValue>"
                    $IntuneComplianceLookup = @{}
                    try {
                        $AlignmentResults = Get-CIPPTenantAlignment -TenantFilter $TenantFilter
                        foreach ($AlignmentResult in $AlignmentResults) {
                            foreach ($Detail in $AlignmentResult.ComparisonDetails) {
                                if ($Detail.StandardName -like 'standards.IntuneTemplate.*') {
                                    $IntuneComplianceLookup[$Detail.StandardName] = $Detail.Compliant
                                }
                            }
                        }
                    } catch {
                        Write-Warning "Failed to get tenant alignment data for $TenantFilter : $($_.Exception.Message)"
                    }
                    Write-Host "COMPLIANCE LOOKUP: Found $($IntuneComplianceLookup.Count) IntuneTemplate entries in alignment data"

                    foreach ($Key in $IntuneKeys) {
                        $Template = $ComputedStandards[$Key]
                        $TemplateEntity = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$($Template.Settings.TemplateList.value)'"

                        if (-not $TemplateEntity) {
                            Write-Host "SKIP: $Key - no IntuneTemplate entity found for RowKey '$($Template.Settings.TemplateList.value)'"
                            continue
                        }

                        $ParsedTemplate = $TemplateEntity.JSON | ConvertFrom-Json
                        if (-not $ParsedTemplate.Type) {
                            Write-Host "SKIP: $Key - template has no Type property"
                            continue
                        }

                        $PolicyType = $ParsedTemplate.Type
                        $PolicyChanged = if ($PolicyType -eq 'AppProtection') {
                            [bool]$PolicyTimestamps['AppProtection']
                        } else {
                            [bool]$PolicyTimestamps[$PolicyType]
                        }
                        Write-Host "TEMPLATE CHECK: $Key | PolicyType=$PolicyType | PolicyChanged=$PolicyChanged"

                        # Check StandardTemplate changes
                        $StandardTemplate = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$($Template.TemplateId)'"
                        $StandardTemplateChanged = $false

                        if ($StandardTemplate) {
                            $StandardTimeUtc = ([DateTimeOffset]$StandardTemplate.Timestamp).UtcDateTime
                            $CachedStandardTemplate = Get-CIPPAzDataTableEntity @TrackingTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq 'StandardTemplate_$($Template.TemplateId)'"

                            if ($CachedStandardTemplate -and $CachedStandardTemplate.CachedTimestamp) {
                                $CachedStandardTimeUtc = ([DateTimeOffset]$CachedStandardTemplate.CachedTimestamp).UtcDateTime
                                $TimeDiff = [Math]::Abs(($StandardTimeUtc - $CachedStandardTimeUtc).TotalSeconds)
                                $StandardTemplateChanged = ($TimeDiff -gt 60)
                                Write-Host "STDTEMPLATE CHECK: TemplateId=$($Template.TemplateId) | TimeDiff=${TimeDiff}s | Changed=$StandardTemplateChanged"
                            } else {
                                $StandardTemplateChanged = $true
                                Write-Host "STDTEMPLATE CHECK: TemplateId=$($Template.TemplateId) | No cached timestamp - treating as changed"
                            }

                            Add-CIPPAzDataTableEntity @TrackingTable -Entity @{
                                PartitionKey    = $TenantFilter
                                RowKey          = "StandardTemplate_$($Template.TemplateId)"
                                CachedTimestamp = $StandardTemplate.Timestamp
                            } -Force | Out-Null
                        }

                        if (-not $PolicyChanged -and -not $StandardTemplateChanged) {
                            $AlignmentKey = "standards.IntuneTemplate.$($Template.Settings.TemplateList.value)"
                            $IsDeployed = $IntuneComplianceLookup.ContainsKey($AlignmentKey)
                            $IsCompliant = $IsDeployed -and ($IntuneComplianceLookup[$AlignmentKey] -eq $true)
                            Write-Host "COMPLIANCE CHECK: $AlignmentKey | InLookup=$IsDeployed | Compliant=$IsCompliant | LookupValue=$($IntuneComplianceLookup[$AlignmentKey])"

                            if ($IsCompliant) {
                                # Verify the policy still exists in Graph before trusting compliance
                                $TemplateDisplayName = $ParsedTemplate.Displayname
                                $TypeNames = if ($PolicyType -eq 'AppProtection') {
                                    @($PolicyNamesByType['AppProtection'])
                                } else {
                                    @($PolicyNamesByType[$PolicyType])
                                }
                                if ($TypeNames -contains $TemplateDisplayName) {
                                    # Policy unchanged, exists in Graph, and compliant - safe to skip
                                    Write-Host "NO INTUNE CHANGE: Filtering out $Key for $TenantFilter (compliant)"
                                    [void]$ComputedStandards.Remove($Key)
                                } else {
                                    Write-Host "KEEPING: $Key - policy '$TemplateDisplayName' not found in Graph for type $PolicyType (deleted?)"
                                }
                            } else {
                                Write-Host "KEEPING: $Key - not compliant or not in lookup (InLookup=$IsDeployed, Compliant=$IsCompliant)"
                            }
                        } else {
                            Write-Host "KEEPING: $Key - changed (PolicyChanged=$PolicyChanged, StdTemplateChanged=$StandardTemplateChanged)"
                        }
                    }
                } catch {
                    Write-Warning "Timestamp check failed for $TenantFilter : $($_.Exception.Message)"
                }
            }
        }

        $CAStandardFound = ($ComputedStandards.Keys.Where({ $_ -like '*ConditionalAccessTemplate*' }, 'First').Count -gt 0)
        if ($CAStandardFound) {
            $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_general' -TenantFilter $TenantFilter -Preset Entra
            if (-not $TestResult) {
                $CAKeys = @($ComputedStandards.Keys | Where-Object { $_ -like '*ConditionalAccessTemplate*' })
                $BulkFields = [System.Collections.Generic.List[object]]::new()
                foreach ($Key in $CAKeys) {
                    $TemplateKey = ($Key -split '\|', 2)[1]
                    if ($TemplateKey) {
                        $BulkFields.Add([PSCustomObject]@{
                                FieldName  = "standards.ConditionalAccessTemplate.$TemplateKey"
                                FieldValue = 'This tenant does not have the required license for this standard.'
                            })
                    }
                    [void]$ComputedStandards.Remove($Key)
                }
                if ($BulkFields.Count -gt 0) {
                    Set-CIPPStandardsCompareField -TenantFilter $TenantFilter -BulkFields $BulkFields
                }

                Write-Information "Removed ConditionalAccessTemplate standards for $TenantFilter - missing required license"
            } else {
                # License valid - update CIPPDB cache with latest CA information before we run so that standards have the most up to date info
                try {
                    Write-Information "Updating CIPPDB cache for Conditional Access policies for $TenantFilter"
                    Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $TenantFilter
                } catch {
                    Write-Warning "Failed to update CA cache for $TenantFilter : $($_.Exception.Message)"
                }
            }
        }

        Write-Host "Returning $($ComputedStandards.Count) standards for tenant $TenantFilter after filtering."
        # Return filtered standards
        $FilteredStandards = $ComputedStandards.Values | ForEach-Object {
            [PSCustomObject]@{
                Tenant       = $_.Tenant
                Standard     = $_.Standard
                Settings     = $_.Settings
                TemplateId   = $_.TemplateId
                FunctionName = 'CIPPStandard'
            }
        }
        Write-Host "Sending back $($FilteredStandards.Count) standards"
        return @($FilteredStandards)
    } catch {
        Write-Warning "Error listing standards for $TenantFilter : $($_.Exception.Message)"
        return @()
    }
}
