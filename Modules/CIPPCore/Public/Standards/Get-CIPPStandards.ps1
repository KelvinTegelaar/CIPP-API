function Get-CIPPStandards {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',
        [switch]$ListAllTenants
    )

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TimeStamp).JSON | ConvertFrom-Json

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
            $Normalized = Normalize-Standard $ComputedStandards[$Standard]
            [pscustomobject]@{
                Tenant   = 'AllTenants'
                Standard = $Standard
                Settings = $Normalized
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

            $ComputedStandards = [ordered]@{}
            foreach ($Template in $ApplicableTemplates) {
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
                    Tenant   = $TenantName
                    Standard = $Standard
                    Settings = $Normalized
                }
            }
        }
    }
}
