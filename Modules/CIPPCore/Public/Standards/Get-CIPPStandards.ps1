function Get-CIPPStandards {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',

        [Parameter(Mandatory = $false)]
        [switch]$ListAllTenants,

        [Parameter(Mandatory = $false)]
        $TemplateId = '*',

        [Parameter(Mandatory = $false)]
        $runManually = $false
    )

    # Get tenant groups
    $TenantGroups = Get-TenantGroups

    # 1. Get all JSON-based templates from the "templates" table
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TimeStamp).JSON |
    ForEach-Object {
        try {
            # Fix old "Action" => "action"
            $JSON = $_ -replace '"Action":', '"action":' -replace '"permissionlevel":', '"permissionLevel":'
            ConvertFrom-Json -InputObject $JSON -ErrorAction SilentlyContinue
        } catch {}
    } |
    Where-Object {
        $_.GUID -like $TemplateId -and $_.runManually -eq $runManually
    }

    # 2. Get tenant list, filter if needed
    $AllTenantsList = Get-Tenants
    if ($TenantFilter -ne 'allTenants') {
        $AllTenantsList = $AllTenantsList | Where-Object {
            $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter
        }
    }

    # 3. If -ListAllTenants, build standards for "AllTenants" only
    if ($ListAllTenants.IsPresent) {
        $AllTenantsTemplates = $Templates | Where-Object {
            $_.tenantFilter.value -contains 'AllTenants'
        }

        $ComputedStandards = [ordered]@{}

        foreach ($Template in $AllTenantsTemplates) {
            $Standards = $Template.standards

            foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                $Value = $Standards.$StandardName
                $IsArray = $Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])

                if ($IsArray) {
                    # e.g. IntuneTemplate with 2 items
                    foreach ($Item in $Value) {
                        $CurrentStandard = $Item.PSObject.Copy()
                        $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                        $Actions = $CurrentStandard.action.value
                        if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                            if (-not $ComputedStandards.Contains($StandardName)) {
                                $ComputedStandards[$StandardName] = $CurrentStandard
                            } else {
                                $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$StandardName] -New $CurrentStandard -StandardName $StandardName
                                $ComputedStandards[$StandardName] = $MergedStandard
                            }
                        }
                    }
                } else {
                    # single object
                    $CurrentStandard = $Value.PSObject.Copy()
                    $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                    $Actions = $CurrentStandard.action.value
                    if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                        if (-not $ComputedStandards.Contains($StandardName)) {
                            $ComputedStandards[$StandardName] = $CurrentStandard
                        } else {
                            $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$StandardName] -New $CurrentStandard -StandardName $StandardName
                            $ComputedStandards[$StandardName] = $MergedStandard
                        }
                    }
                }
            }
        }

        # Output result for 'AllTenants'
        foreach ($Standard in $ComputedStandards.Keys) {
            $TempCopy = $ComputedStandards[$Standard].PSObject.Copy()

            # Remove 'TemplateId' from final output
            if ($TempCopy -is [System.Collections.IEnumerable] -and -not ($TempCopy -is [string])) {
                foreach ($subItem in $TempCopy) {
                    $subItem.PSObject.Properties.Remove('TemplateId') | Out-Null
                }
            } else {
                $TempCopy.PSObject.Properties.Remove('TemplateId') | Out-Null
            }

            $Normalized = ConvertTo-CippStandardObject $TempCopy

            [pscustomobject]@{
                Tenant     = 'AllTenants'
                Standard   = $Standard
                Settings   = $Normalized
                TemplateId = if ($ComputedStandards[$Standard] -is [System.Collections.IEnumerable] -and -not ($ComputedStandards[$Standard] -is [string])) {
                    # If multiple items from multiple templates, you may have multiple TemplateIds
                    $ComputedStandards[$Standard] | ForEach-Object { $_.TemplateId }
                } else {
                    $ComputedStandards[$Standard].TemplateId
                }
            }
        }
    } else {
        # 4. For each tenant, figure out which templates apply, merge them, and output.
        foreach ($Tenant in $AllTenantsList) {
            $TenantName = $Tenant.defaultDomainName
            # Determine which templates apply to this tenant
            $ApplicableTemplates = $Templates | ForEach-Object {
                $template = $_
                $tenantFilterValues = $template.tenantFilter | ForEach-Object {
                    $FilterValue = $_.value
                    # Group lookup
                    if ($_.type -eq 'Group') {
                        ($TenantGroups | Where-Object {
                            $_.Id -eq $FilterValue
                        }).Members.defaultDomainName
                    } else {
                        $FilterValue
                    }
                }

                $excludedTenantValues = @()

                if ($template.excludedTenants) {
                    if ($template.excludedTenants -is [System.Collections.IEnumerable] -and -not ($template.excludedTenants -is [string])) {
                        $excludedTenantValues = $template.excludedTenants | ForEach-Object {
                            $FilterValue = $_.value
                            if ($_.type -eq 'Group') {
                        ($TenantGroups | Where-Object {
                                    $_.Id -eq $FilterValue
                                }).Members.defaultDomainName
                            } else {
                                $FilterValue
                            } }
                    } else {
                        $excludedTenantValues = @($template.excludedTenants)
                    }
                }

                $AllTenantsApplicable = $false
                $TenantSpecificApplicable = $false

                if ($tenantFilterValues -contains 'AllTenants' -and -not ($excludedTenantValues -contains $TenantName)) {
                    $AllTenantsApplicable = $true
                }
                if ($tenantFilterValues -contains $TenantName) {
                    $TenantSpecificApplicable = $true
                }

                if ($AllTenantsApplicable -or $TenantSpecificApplicable) {
                    $template
                }
            }

            # Separate them into AllTenant vs. TenantSpecific sets
            $AllTenantTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -contains 'AllTenants'
            }
            $TenantSpecificTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -notcontains 'AllTenants'
            }

            $ComputedStandards = [ordered]@{}

            # 4a. Merge the AllTenantTemplatesSet
            foreach ($Template in $AllTenantTemplatesSet) {
                $Standards = $Template.standards

                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $Value = $Standards.$StandardName
                    $IsArray = $Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])

                    if ($IsArray) {
                        foreach ($Item in $Value) {
                            $CurrentStandard = $Item.PSObject.Copy()
                            $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                            $Actions = $CurrentStandard.action.value
                            if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                                if (-not $ComputedStandards.Contains($StandardName)) {
                                    $ComputedStandards[$StandardName] = $CurrentStandard
                                } else {
                                    $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$StandardName] -New $CurrentStandard -StandardName $StandardName
                                    $ComputedStandards[$StandardName] = $MergedStandard
                                }
                            }
                        }
                    } else {
                        $CurrentStandard = $Value.PSObject.Copy()
                        $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                        $Actions = $CurrentStandard.action.value
                        if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                            if (-not $ComputedStandards.Contains($StandardName)) {
                                $ComputedStandards[$StandardName] = $CurrentStandard
                            } else {
                                $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$StandardName] -New $CurrentStandard -StandardName $StandardName
                                $ComputedStandards[$StandardName] = $MergedStandard
                            }
                        }
                    }
                }
            }

            # 4b. Merge the TenantSpecificTemplatesSet
            foreach ($Template in $TenantSpecificTemplatesSet) {
                $Standards = $Template.standards

                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $Value = $Standards.$StandardName
                    $IsArray = $Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])

                    if ($IsArray) {
                        foreach ($Item in $Value) {
                            $CurrentStandard = $Item.PSObject.Copy()
                            $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                            # Filter actions only 'Remediate','warn','Report'
                            $Actions = $CurrentStandard.action.value | Where-Object { $_ -in 'Remediate', 'warn', 'Report' }
                            if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                                if (-not $ComputedStandards.Contains($StandardName)) {
                                    $ComputedStandards[$StandardName] = $CurrentStandard
                                } else {
                                    $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$StandardName] -New $CurrentStandard -StandardName $StandardName
                                    $ComputedStandards[$StandardName] = $MergedStandard
                                }
                            }
                        }
                    } else {
                        $CurrentStandard = $Value.PSObject.Copy()
                        $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                        $Actions = $CurrentStandard.action.value | Where-Object { $_ -in 'Remediate', 'warn', 'Report' }
                        if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                            if (-not $ComputedStandards.Contains($StandardName)) {
                                $ComputedStandards[$StandardName] = $CurrentStandard
                            } else {
                                $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$StandardName] -New $CurrentStandard -StandardName $StandardName
                                $ComputedStandards[$StandardName] = $MergedStandard
                            }
                        }
                    }
                }
            }

            # 4c. Output each final standard for this tenant
            foreach ($Standard in $ComputedStandards.Keys) {
                $TempCopy = $ComputedStandards[$Standard].PSObject.Copy()
                # Remove local 'TemplateId' from final object(s)
                if ($TempCopy -is [System.Collections.IEnumerable] -and -not ($TempCopy -is [string])) {
                    foreach ($subItem in $TempCopy) {
                        $subItem.PSObject.Properties.Remove('TemplateId') | Out-Null
                    }
                } else {
                    $TempCopy.PSObject.Properties.Remove('TemplateId') | Out-Null
                }

                $Normalized = ConvertTo-CippStandardObject $TempCopy

                [pscustomobject]@{
                    Tenant     = $TenantName
                    Standard   = $Standard
                    Settings   = $Normalized
                    TemplateId = $ComputedStandards[$Standard].TemplateId
                }
            }
        }
    }
}

