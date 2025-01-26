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

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TimeStamp).JSON | ForEach-Object {
        #in the string $_, replace the word 'action' by the word 'Action'.
        try {
            $_ -replace 'Action', 'action' | ConvertFrom-Json -InputObject $_ -ErrorAction SilentlyContinue
        } catch {
        }
    } | Where-Object {
        $_.GUID -like $TemplateId -and $_.runManually -eq $runManually
    }

    $AllTenantsList = Get-Tenants
    if ($TenantFilter -ne 'allTenants') {
        $AllTenantsList = $AllTenantsList | Where-Object {
            $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter
        }
    }

    if ($ListAllTenants.IsPresent) {
        $AllTenantsTemplates = $Templates | Where-Object {
            $_.tenantFilter.value -contains 'AllTenants'
        }

        $ComputedStandards = [ordered]@{}

        foreach ($Template in $AllTenantsTemplates) {
            $Standards = $Template.standards
            foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                $CurrentStandard = $Standards.$StandardName.PSObject.Copy()
                $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                $Actions = $CurrentStandard.action.value
                if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                    if (-not $ComputedStandards.Contains($StandardName)) {
                        $ComputedStandards[$StandardName] = $CurrentStandard
                    } else {
                        $MergedStandard = Merge-CippStandards $ComputedStandards[$StandardName] $CurrentStandard
                        $MergedStandard.TemplateId = $CurrentStandard.TemplateId
                        $ComputedStandards[$StandardName] = $MergedStandard
                    }
                }
            }
        }

        foreach ($Standard in $ComputedStandards.Keys) {
            $TempCopy = $ComputedStandards[$Standard].PSObject.Copy()
            $TempCopy.PSObject.Properties.Remove('TemplateId')

            $Normalized = ConvertTo-CippStandardObject $TempCopy

            [pscustomobject]@{
                Tenant     = 'AllTenants'
                Standard   = $Standard
                Settings   = $Normalized
                TemplateId = $ComputedStandards[$Standard].TemplateId
            }
        }

    } else {
        foreach ($Tenant in $AllTenantsList) {
            $TenantName = $Tenant.defaultDomainName

            $ApplicableTemplates = $Templates | ForEach-Object {
                $template = $_
                $tenantFilterValues = $template.tenantFilter | ForEach-Object { $_.value }
                $excludedTenantValues = @()
                if ($template.excludedTenants) {
                    $excludedTenantValues = $template.excludedTenants | ForEach-Object { $_.value }
                }

                $AllTenantsApplicable = $false
                $TenantSpecificApplicable = $false

                if ($tenantFilterValues -contains 'AllTenants' -and (-not ($excludedTenantValues -contains $TenantName))) {
                    $AllTenantsApplicable = $true
                }
                if ($tenantFilterValues -contains $TenantName) {
                    $TenantSpecificApplicable = $true
                }

                if ($AllTenantsApplicable -or $TenantSpecificApplicable) {
                    $template
                }
            }

            $AllTenantTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -contains 'AllTenants'
            }
            $TenantSpecificTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -notcontains 'AllTenants'
            }

            $ComputedStandards = [ordered]@{}

            foreach ($Template in $AllTenantTemplatesSet) {
                $Standards = $Template.standards
                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $CurrentStandard = $Standards.$StandardName.PSObject.Copy()
                    $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                    $Actions = $CurrentStandard.action.value
                    if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                        if (-not $ComputedStandards.Contains($StandardName)) {
                            $ComputedStandards[$StandardName] = $CurrentStandard
                        } else {
                            $MergedStandard = Merge-CippStandards $ComputedStandards[$StandardName] $CurrentStandard
                            $MergedStandard.TemplateId = $CurrentStandard.TemplateId
                            $ComputedStandards[$StandardName] = $MergedStandard
                        }
                    }
                }
            }

            foreach ($Template in $TenantSpecificTemplatesSet) {
                $Standards = $Template.standards
                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $CurrentStandard = $Standards.$StandardName.PSObject.Copy()
                    $CurrentStandard | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $Template.GUID -Force

                    $Actions = $CurrentStandard.action.value | Where-Object { $_ -in 'Remediate', 'warn', 'report' }
                    if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                        if (-not $ComputedStandards.Contains($StandardName)) {
                            $ComputedStandards[$StandardName] = $CurrentStandard
                        } else {
                            $MergedStandard = Merge-CippStandards $ComputedStandards[$StandardName] $CurrentStandard
                            $MergedStandard.TemplateId = $CurrentStandard.TemplateId
                            $ComputedStandards[$StandardName] = $MergedStandard
                        }
                    }
                }
            }

            foreach ($Standard in $ComputedStandards.Keys) {
                $TempCopy = $ComputedStandards[$Standard].PSObject.Copy()
                $TempCopy.PSObject.Properties.Remove('TemplateId')

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
