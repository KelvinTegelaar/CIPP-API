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
            $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneTemplate_general' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

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
                $TypeMap = @{
                    Device                   = 'deviceManagement/deviceConfigurations'
                    Catalog                  = 'deviceManagement/configurationPolicies'
                    Admin                    = 'deviceManagement/groupPolicyConfigurations'
                    deviceCompliancePolicies = 'deviceManagement/deviceCompliancePolicies'
                    AppProtection_Android    = 'deviceAppManagement/androidManagedAppProtections'
                    AppProtection_iOS        = 'deviceAppManagement/iosManagedAppProtections'
                }

                $BulkRequests = $TypeMap.GetEnumerator() | ForEach-Object {
                    @{
                        id     = $_.Key
                        url    = "$($_.Value)?`$orderby=lastModifiedDateTime desc&`$select=id,lastModifiedDateTime&`$top=999"
                        method = 'GET'
                    }
                }

                try {
                    $TrackingTable = Get-CippTable -tablename 'IntunePolicyTypeTracking'
                    $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter -NoPaginateIds @($BulkRequests.id)
                    $PolicyTimestamps = @{}

                    foreach ($Result in $BulkResults) {
                        $GraphTime = $Result.body.value[0].lastModifiedDateTime
                        $GraphId = $Result.body.value[0].id
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
                        } else {
                            $Changed = $true
                        }

                        $PolicyTimestamps[$Result.id] = $Changed
                    }

                    # Filter unchanged templates
                    $TemplateTable = Get-CippTable -tablename 'templates'
                    $StandardTemplateTable = Get-CippTable -tablename 'templates'
                    $IntuneKeys = @($ComputedStandards.Keys | Where-Object { $_ -like '*IntuneTemplate*' })

                    foreach ($Key in $IntuneKeys) {
                        $Template = $ComputedStandards[$Key]
                        $TemplateEntity = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$($Template.Settings.TemplateList.value)'"

                        if (-not $TemplateEntity) { continue }

                        $ParsedTemplate = $TemplateEntity.JSON | ConvertFrom-Json
                        if (-not $ParsedTemplate.Type) { continue }

                        $PolicyType = $ParsedTemplate.Type
                        $PolicyChanged = if ($PolicyType -eq 'AppProtection') {
                            [bool]($PolicyTimestamps['AppProtection_Android'] -or $PolicyTimestamps['AppProtection_iOS'])
                        } else {
                            [bool]$PolicyTimestamps[$PolicyType]
                        }

                        # Check StandardTemplate changes
                        $StandardTemplate = Get-CIPPAzDataTableEntity @StandardTemplateTable -Filter "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$($Template.TemplateId)'"
                        $StandardTemplateChanged = $false

                        if ($StandardTemplate) {
                            $StandardTimeUtc = ([DateTimeOffset]$StandardTemplate.Timestamp).UtcDateTime
                            $CachedStandardTemplate = Get-CIPPAzDataTableEntity @TrackingTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq 'StandardTemplate_$($Template.TemplateId)'"

                            if ($CachedStandardTemplate -and $CachedStandardTemplate.CachedTimestamp) {
                                $CachedStandardTimeUtc = ([DateTimeOffset]$CachedStandardTemplate.CachedTimestamp).UtcDateTime
                                $TimeDiff = [Math]::Abs(($StandardTimeUtc - $CachedStandardTimeUtc).TotalSeconds)
                                $StandardTemplateChanged = ($TimeDiff -gt 60)
                            } else {
                                $StandardTemplateChanged = $true
                            }

                            Add-CIPPAzDataTableEntity @TrackingTable -Entity @{
                                PartitionKey    = $TenantFilter
                                RowKey          = "StandardTemplate_$($Template.TemplateId)"
                                CachedTimestamp = $StandardTemplate.Timestamp
                            } -Force | Out-Null
                        }

                        # Remove if both unchanged
                        if (-not $PolicyChanged -and -not $StandardTemplateChanged) {
                            Write-Host "NO INTUNE CHANGE: Filtering out $key for $($TenantFilter)"
                            [void]$ComputedStandards.Remove($Key)
                        }
                    }
                } catch {
                    Write-Warning "Timestamp check failed for $TenantFilter : $($_.Exception.Message)"
                }
            }
        }

        $CAStandardFound = ($ComputedStandards.Keys.Where({ $_ -like '*ConditionalAccessTemplate*' }, 'First').Count -gt 0)
        if ($CAStandardFound) {
            $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_general' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2')
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
        Write-Host "Sending back $($FilteredStandards.Count) standards: $($FilteredStandards | ConvertTo-Json -Depth 5 -Compress)"
        return $FilteredStandards

    } catch {
        Write-Warning "Error listing standards for $TenantFilter : $($_.Exception.Message)"
        return @()
    }
}
