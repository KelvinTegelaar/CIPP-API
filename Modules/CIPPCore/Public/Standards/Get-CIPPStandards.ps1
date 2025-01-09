
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
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TimeStamp).JSON | ConvertFrom-Json | Where-Object {
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
                $Actions = $CurrentStandard.action.value
                if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                    if (-not $ComputedStandards.Contains($StandardName)) {
                        $ComputedStandards[$StandardName] = $CurrentStandard
                    } else {
                        $ComputedStandards[$StandardName] = Merge-CippStandards $ComputedStandards[$StandardName] $CurrentStandard
                    }
                }
            }
        }

        foreach ($Standard in $ComputedStandards.Keys) {
            $Normalized = ConvertTo-CippStandardObject $ComputedStandards[$Standard]
            [pscustomobject]@{
                Tenant   = 'AllTenants'
                Standard = $Standard
                Settings = $Normalized
            }
        }

    } else {
        foreach ($Tenant in $AllTenantsList) {
            $TenantName = $Tenant.defaultDomainName
            # Determine applicable templates
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

            # Separate AllTenants and Tenant-Specific templates
            $AllTenantTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -contains 'AllTenants'
            }

            $TenantSpecificTemplatesSet = $ApplicableTemplates | Where-Object {
                $_.tenantFilter.value -notcontains 'AllTenants'
            }

            $ComputedStandards = [ordered]@{}

            # First merge AllTenants templates
            foreach ($Template in $AllTenantTemplatesSet) {
                $Standards = $Template.standards
                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $CurrentStandard = $Standards.$StandardName.PSObject.Copy()
                    $Actions = $CurrentStandard.action.value
                    if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                        if (-not $ComputedStandards.Contains($StandardName)) {
                            $ComputedStandards[$StandardName] = $CurrentStandard
                        } else {
                            $ComputedStandards[$StandardName] = Merge-CippStandards $ComputedStandards[$StandardName] $CurrentStandard
                        }
                    }
                }
            }

            # Then merge Tenant-Specific templates (overriding AllTenants where needed)
            foreach ($Template in $TenantSpecificTemplatesSet) {
                $Standards = $Template.standards
                foreach ($StandardName in $Standards.PSObject.Properties.Name) {
                    $CurrentStandard = $Standards.$StandardName.PSObject.Copy()
                    $Actions = $CurrentStandard.action.value | Where-Object { $_ -in 'Remediate', 'warn', 'report' }
                    if ($Actions -contains 'Remediate' -or $Actions -contains 'warn' -or $Actions -contains 'Report') {
                        if (-not $ComputedStandards.Contains($StandardName)) {
                            $ComputedStandards[$StandardName] = $CurrentStandard
                        } else {
                            # Tenant-specific overrides any previous AllTenants settings
                            $ComputedStandards[$StandardName] = Merge-CippStandards $ComputedStandards[$StandardName] $CurrentStandard
                        }
                    }
                }
            }

            # Normalize and output
            foreach ($Standard in $ComputedStandards.Keys) {
                $Normalized = ConvertTo-CippStandardObject $ComputedStandards[$Standard]
                [pscustomobject]@{
                    Tenant   = $TenantName
                    Standard = $Standard
                    Settings = $Normalized
                }
            }
        }
    }
}
