function Normalize-Standard {
    param(
        [Parameter(Mandatory = $true)] $StandardObject
    )

    # Ensure it's a PSCustomObject
    $StandardObject = [pscustomobject]$StandardObject

    # Check if combinedActions is present
    $AllActionValues = @()
    if ($StandardObject.PSObject.Properties.Name -contains 'combinedActions') {
        $AllActionValues = $StandardObject.combinedActions
        # Remove combinedActions now that we have the values
        $null = $StandardObject.PSObject.Properties.Remove('combinedActions')
    }

    # Determine booleans based on combinedActions
    $remediate = $AllActionValues -contains 'Remediate'
    $alert = $AllActionValues -contains 'warn'
    $report = $AllActionValues -contains 'Report'

    # Add or update the booleans
    $StandardObject | Add-Member -NotePropertyName 'remediate' -NotePropertyValue $remediate -Force
    $StandardObject | Add-Member -NotePropertyName 'alert' -NotePropertyValue $alert -Force
    $StandardObject | Add-Member -NotePropertyName 'report' -NotePropertyValue $report -Force

    # Flatten any nested settings from 'standards'
    if ($StandardObject.PSObject.Properties.Name -contains 'standards' -and $StandardObject.standards) {
        foreach ($standardKey in $StandardObject.standards.PSObject.Properties.Name) {
            $NestedStandard = $StandardObject.standards.$standardKey
            if ($NestedStandard) {
                # Move each property from the nested standard up
                foreach ($nsProp in $NestedStandard.PSObject.Properties) {
                    $StandardObject | Add-Member -NotePropertyName $nsProp.Name -NotePropertyValue $nsProp.Value -Force
                }
            }
        }
        # Remove the 'standards' property after flattening
        $null = $StandardObject.PSObject.Properties.Remove('standards')
    }

    return $StandardObject
}

function Get-CIPPStandards {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',
        [switch]$ListAllTenants
    )

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    $AllTenantsList = Get-Tenants
    if ($TenantFilter -ne 'allTenants') {
        $AllTenantsList = $AllTenantsList | Where-Object {
            $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter
        }
    }

    function Merge-Standards {
        param(
            [Parameter(Mandatory = $true)] $Existing,
            [Parameter(Mandatory = $true)] $CurrentStandard
        )

        # Ensure PSCustomObject
        $Existing = [pscustomobject]$Existing
        $CurrentStandard = [pscustomobject]$CurrentStandard

        # Extract action from Existing
        $ExistingActionValues = @()
        if ($Existing.PSObject.Properties.Name -contains 'action') {
            if ($Existing.action -and $Existing.action.value) {
                $ExistingActionValues = @($Existing.action.value)
            }
            $null = $Existing.PSObject.Properties.Remove('action')
        }

        # Extract action from CurrentStandard
        $CurrentActionValues = @()
        if ($CurrentStandard.PSObject.Properties.Name -contains 'action') {
            if ($CurrentStandard.action -and $CurrentStandard.action.value) {
                $CurrentActionValues = @($CurrentStandard.action.value)
            }
            $null = $CurrentStandard.PSObject.Properties.Remove('action')
        }

        # Combine and get unique actions
        $AllActionValues = ($ExistingActionValues + $CurrentActionValues) | Select-Object -Unique

        # Merge other properties from CurrentStandard into Existing
        foreach ($prop in $CurrentStandard.PSObject.Properties) {
            if ($prop.Name -eq 'action') { continue }
            $Existing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
        if ($AllActionValues.Count -gt 0) {
            $Existing | Add-Member -NotePropertyName 'combinedActions' -NotePropertyValue $AllActionValues -Force
        }

        return $Existing
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
                        $ComputedStandards[$StandardName] = Merge-Standards $ComputedStandards[$StandardName] $CurrentStandard
                    }
                }
            }
        }

        # Normalize each standard before outputting
        foreach ($Standard in $ComputedStandards.Keys) {
            # Normalize-Standard will convert combinedActions into remediate/alert/report and remove action arrays.
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
                            $ComputedStandards[$StandardName] = Merge-Standards $ComputedStandards[$StandardName] $CurrentStandard
                        }
                    }
                }
            }

            # Normalize each standard before outputting
            foreach ($Standard in $ComputedStandards.Keys) {
                $Normalized = Normalize-Standard $ComputedStandards[$Standard]
                [pscustomobject]@{
                    Tenant   = $TenantName
                    Standard = $Standard
                    Settings = $Normalized
                }
            }
        }
    }
}
