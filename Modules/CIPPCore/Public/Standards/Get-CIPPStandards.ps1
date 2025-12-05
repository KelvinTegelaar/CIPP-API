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

    # 1.5. Expand templates that contain TemplateList-Tags into multiple standards
    $ExpandedTemplates = foreach ($Template in $Templates) {
        Write-Information "Template $($Template.templateName) ($($Template.GUID)) processing..."
        $NewTemplate = $Template.PSObject.Copy()
        $ExpandedStandards = [ordered]@{}
        $HasExpansions = $false

        foreach ($StandardName in $Template.standards.PSObject.Properties.Name) {
            $StandardValue = $Template.standards.$StandardName
            $IsArray = $StandardValue -is [System.Collections.IEnumerable] -and -not ($StandardValue -is [string])

            if ($IsArray) {
                $NewArray = foreach ($Item in $StandardValue) {
                    if ($Item.'TemplateList-Tags'.value) {
                        $HasExpansions = $true
                        $Table = Get-CippTable -tablename 'templates'
                        $Filter = "PartitionKey eq 'IntuneTemplate'"
                        $TemplatesList = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property package -EQ $Item.'TemplateList-Tags'.value

                        foreach ($TemplateItem in $TemplatesList) {
                            $NewItem = $Item.PSObject.Copy()
                            $NewItem.PSObject.Properties.Remove('TemplateList-Tags')
                            $NewItem | Add-Member -NotePropertyName TemplateList -NotePropertyValue ([pscustomobject]@{
                                    label = "$($TemplateItem.RowKey)"
                                    value = "$($TemplateItem.RowKey)"
                                }) -Force
                            $NewItem | Add-Member -NotePropertyName TemplateId -NotePropertyValue $Template.GUID -Force
                            $NewItem
                        }
                    } else {
                        $Item | Add-Member -NotePropertyName TemplateId -NotePropertyValue $Template.GUID -Force
                        $Item
                    }
                }
                $ExpandedStandards[$StandardName] = $NewArray
            } else {
                if ($StandardValue.'TemplateList-Tags'.value) {
                    $HasExpansions = $true
                    $Table = Get-CippTable -tablename 'templates'
                    $Filter = "PartitionKey eq 'IntuneTemplate'"
                    $TemplatesList = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property package -EQ $StandardValue.'TemplateList-Tags'.value

                    $NewArray = foreach ($TemplateItem in $TemplatesList) {
                        $NewItem = $StandardValue.PSObject.Copy()
                        $NewItem.PSObject.Properties.Remove('TemplateList-Tags')
                        $NewItem | Add-Member -NotePropertyName TemplateList -NotePropertyValue ([pscustomobject]@{
                                label = "$($TemplateItem.RowKey)"
                                value = "$($TemplateItem.RowKey)"
                            }) -Force
                        $NewItem | Add-Member -NotePropertyName TemplateId -NotePropertyValue $Template.GUID -Force
                        $NewItem
                    }
                    $ExpandedStandards[$StandardName] = $NewArray
                } else {
                    $StandardValue | Add-Member -NotePropertyName TemplateId -NotePropertyValue $Template.GUID -Force
                    $ExpandedStandards[$StandardName] = $StandardValue
                }
            }
        }

        if ($HasExpansions) {
            $NewTemplate.standards = [pscustomobject]$ExpandedStandards
        }

        $NewTemplate
    }

    $Templates = $ExpandedTemplates

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

        foreach ($Template in $AllTenantsTemplates) {
            $Standards = $Template.standards

            foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                $Value = $Standards.$StandardName
                $IsArray = $Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])

                if ($IsArray) {
                    # Emit one object per array element
                    foreach ($Item in $Value) {
                        $CurrentStandard = $Item.PSObject.Copy()

                        # Add Remediate if autoRemediate is true
                        if ($CurrentStandard.autoRemediate -eq $true -and -not ($CurrentStandard.action.value -contains 'Remediate')) {
                            $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                label = 'Remediate'
                                value = 'Remediate'
                            }
                        }

                        # Add Report if Remediate present but Report missing
                        if ($CurrentStandard.action.value -contains 'Remediate' -and -not ($CurrentStandard.action.value -contains 'Report')) {
                            $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                label = 'Report'
                                value = 'Report'
                            }
                        }

                        $Actions = $CurrentStandard.action.value
                        if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                            $Normalized = ConvertTo-CippStandardObject $CurrentStandard

                            [pscustomobject]@{
                                Tenant     = 'AllTenants'
                                Standard   = $StandardName
                                Settings   = $Normalized
                                TemplateId = $Template.GUID
                            }
                        }
                    }
                } else {
                    # Single object
                    $CurrentStandard = $Value.PSObject.Copy()

                    # Add Remediate if autoRemediate is true
                    if ($CurrentStandard.autoRemediate -eq $true -and -not ($CurrentStandard.action.value -contains 'Remediate')) {
                        $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                            label = 'Remediate'
                            value = 'Remediate'
                        }
                    }

                    # Add Report if Remediate present but Report missing
                    if ($CurrentStandard.action.value -contains 'Remediate' -and -not ($CurrentStandard.action.value -contains 'Report')) {
                        $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                            label = 'Report'
                            value = 'Report'
                        }
                    }

                    $Actions = $CurrentStandard.action.value
                    if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                        $Normalized = ConvertTo-CippStandardObject $CurrentStandard

                        [pscustomobject]@{
                            Tenant     = 'AllTenants'
                            Standard   = $StandardName
                            Settings   = $Normalized
                            TemplateId = $Template.GUID
                        }
                    }
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
                if ($tenantFilterValues -contains $TenantName -and -not ($excludedTenantValues -contains $TenantName)) {
                    $TenantSpecificApplicable = $true
                }

                if ($AllTenantsApplicable -or $TenantSpecificApplicable) {
                    $template
                }
            }

            # Separate AllTenants vs TenantSpecific templates
            $AllTenantTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -contains 'AllTenants'
            }
            $TenantSpecificTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -notcontains 'AllTenants'
            }

            # Build merged standards keyed by (StandardName, TemplateList.value)
            $ComputedStandards = @{}

            # Process AllTenants templates first
            foreach ($Template in $AllTenantTemplatesSet) {
                $Standards = $Template.standards

                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $Value = $Standards.$StandardName
                    $IsArray = $Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])

                    if ($IsArray) {
                        foreach ($Item in $Value) {
                            $CurrentStandard = $Item.PSObject.Copy()
                            $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                            # Add Remediate if autoRemediate is true
                            if ($CurrentStandard.autoRemediate -eq $true -and -not ($CurrentStandard.action.value -contains 'Remediate')) {
                                $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                    label = 'Remediate'
                                    value = 'Remediate'
                                }
                            }

                            # Add Report if Remediate present but Report missing
                            if ($CurrentStandard.action.value -contains 'Remediate' -and -not ($CurrentStandard.action.value -contains 'Report')) {
                                $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                    label = 'Report'
                                    value = 'Report'
                                }
                            }

                            $Actions = $CurrentStandard.action.value
                            if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                                # Key by StandardName + TemplateList.value (if present)
                                $TemplateKey = if ($CurrentStandard.TemplateList.value) { $CurrentStandard.TemplateList.value } else { '' }
                                $Key = "$StandardName|$TemplateKey"

                                $ComputedStandards[$Key] = $CurrentStandard
                            }
                        }
                    } else {
                        $CurrentStandard = $Value.PSObject.Copy()
                        $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                        # Add Remediate if autoRemediate is true
                        if ($CurrentStandard.autoRemediate -eq $true -and -not ($CurrentStandard.action.value -contains 'Remediate')) {
                            $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                label = 'Remediate'
                                value = 'Remediate'
                            }
                        }

                        # Add Report if Remediate present but Report missing
                        if ($CurrentStandard.action.value -contains 'Remediate' -and -not ($CurrentStandard.action.value -contains 'Report')) {
                            $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                label = 'Report'
                                value = 'Report'
                            }
                        }

                        $Actions = $CurrentStandard.action.value
                        if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                            $TemplateKey = if ($CurrentStandard.TemplateList.value) { $CurrentStandard.TemplateList.value } else { '' }
                            $Key = "$StandardName|$TemplateKey"

                            $ComputedStandards[$Key] = $CurrentStandard
                        }
                    }
                }
            }

            # Process TenantSpecific templates, merging with AllTenants base
            foreach ($Template in $TenantSpecificTemplatesSet) {
                $Standards = $Template.standards

                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $Value = $Standards.$StandardName
                    $IsArray = $Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])

                    if ($IsArray) {
                        foreach ($Item in $Value) {
                            $CurrentStandard = $Item.PSObject.Copy()
                            $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                            # Add Remediate if autoRemediate is true
                            if ($CurrentStandard.autoRemediate -eq $true -and -not ($CurrentStandard.action.value -contains 'Remediate')) {
                                $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                    label = 'Remediate'
                                    value = 'Remediate'
                                }
                            }

                            # Add Report if Remediate present but Report missing
                            if ($CurrentStandard.action.value -contains 'Remediate' -and -not ($CurrentStandard.action.value -contains 'Report')) {
                                $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                    label = 'Report'
                                    value = 'Report'
                                }
                            }

                            $Actions = $CurrentStandard.action.value
                            if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                                $TemplateKey = if ($CurrentStandard.TemplateList.value) { $CurrentStandard.TemplateList.value } else { '' }
                                $Key = "$StandardName|$TemplateKey"

                                if ($ComputedStandards.ContainsKey($Key)) {
                                    # Merge tenant-specific over AllTenants base
                                    $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$Key] -New $CurrentStandard -StandardName $StandardName
                                    $ComputedStandards[$Key] = $MergedStandard
                                } else {
                                    $ComputedStandards[$Key] = $CurrentStandard
                                }
                            }
                        }
                    } else {
                        $CurrentStandard = $Value.PSObject.Copy()
                        $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                        # Add Remediate if autoRemediate is true
                        if ($CurrentStandard.autoRemediate -eq $true -and -not ($CurrentStandard.action.value -contains 'Remediate')) {
                            $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                label = 'Remediate'
                                value = 'Remediate'
                            }
                        }

                        # Add Report if Remediate present but Report missing
                        if ($CurrentStandard.action.value -contains 'Remediate' -and -not ($CurrentStandard.action.value -contains 'Report')) {
                            $CurrentStandard.action = @($CurrentStandard.action) + [pscustomobject]@{
                                label = 'Report'
                                value = 'Report'
                            }
                        }

                        $Actions = $CurrentStandard.action.value
                        if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                            $TemplateKey = if ($CurrentStandard.TemplateList.value) { $CurrentStandard.TemplateList.value } else { '' }
                            $Key = "$StandardName|$TemplateKey"

                            if ($ComputedStandards.ContainsKey($Key)) {
                                $MergedStandard = Merge-CippStandards -Existing $ComputedStandards[$Key] -New $CurrentStandard -StandardName $StandardName
                                $ComputedStandards[$Key] = $MergedStandard
                            } else {
                                $ComputedStandards[$Key] = $CurrentStandard
                            }
                        }
                    }
                }
            }

            # Emit one object per unique (StandardName, TemplateList.value)
            foreach ($Key in $ComputedStandards.Keys) {
                $Standard = $ComputedStandards[$Key]
                $StandardName = $Key -replace '\|.*$', ''

                # Preserve TemplateId before removing
                $PreservedTemplateId = $Standard.TemplateId
                $Standard.PSObject.Properties.Remove('TemplateId') | Out-Null

                $Normalized = ConvertTo-CippStandardObject $Standard

                [pscustomobject]@{
                    Tenant     = $TenantName
                    Standard   = $StandardName
                    Settings   = $Normalized
                    TemplateId = $PreservedTemplateId
                }
            }
        }
    }
}

