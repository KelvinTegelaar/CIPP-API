function Get-CIPPStandards {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',
        [switch]$ListAllTenants,
        [switch]$SkipGetTenants
    )

    #Write-Host "Getting standards for tenant - $($tenantFilter)"
    $Table = Get-CippTable -tablename 'standards'
    $Filter = "PartitionKey eq 'standards'"
    $Standards = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
    $StandardsAllTenants = $Standards | Where-Object { $_.Tenant -eq 'AllTenants' }

    # Get tenant list based on filter
    if ($SkipGetTenants.IsPresent) {
        # Debugging flag to skip Get-Tenants
        $Tenants = $Standards.Tenant | Sort-Object -Unique | ForEach-Object { [pscustomobject]@{ defaultDomainName = $_ } }
    } else {
        $Tenants = Get-Tenants
    }
    if ($TenantFilter -ne 'allTenants') {
        $Tenants = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }
    }

    if ($ListAllTenants.IsPresent) {
        $ComputedStandards = @{}
        foreach ($StandardName in $StandardsAllTenants.Standards.PSObject.Properties.Name) {
            $CurrentStandard = $StandardsAllTenants.Standards.$StandardName
            #Write-Host ($CurrentStandard | ConvertTo-Json -Depth 10)
            if ($CurrentStandard.remediate -eq $true -or $CurrentStandard.alert -eq $true -or $CurrentStandard.report -eq $true) {
                #Write-Host "AllTenant Standard $StandardName"
                $ComputedStandards[$StandardName] = $CurrentStandard
            }
        }
        foreach ($Standard in $ComputedStandards.Keys) {
            [pscustomobject]@{
                Tenant   = 'AllTenants'
                Standard = $Standard
                Settings = $ComputedStandards.$Standard
            }
        }
    } else {
        foreach ($Tenant in $Tenants) {
            #Write-Host "`r`n###### Tenant: $($Tenant.defaultDomainName)"
            $StandardsTenant = $Standards | Where-Object { $_.Tenant -eq $Tenant.defaultDomainName }

            $ComputedStandards = @{}
            if ($StandardsTenant.Standards.OverrideAllTenants.remediate -ne $true) {
                #Write-Host 'AllTenant Standards apply to this tenant.'
                foreach ($StandardName in $StandardsAllTenants.Standards.PSObject.Properties.Name) {
                    $CurrentStandard = $StandardsAllTenants.Standards.$StandardName.PSObject.Copy()
                    #Write-Host ($CurrentStandard | ConvertTo-Json -Depth 10)
                    if ($CurrentStandard.remediate -eq $true -or $CurrentStandard.alert -eq $true -or $CurrentStandard.report -eq $true) {
                        #Write-Host "AllTenant Standard $StandardName"
                        $ComputedStandards[$StandardName] = $CurrentStandard
                    }
                }
            }

            foreach ($StandardName in $StandardsTenant.Standards.PSObject.Properties.Name) {
                if ($StandardName -eq 'OverrideAllTenants') { continue }
                $CurrentStandard = $StandardsTenant.Standards.$StandardName.PSObject.Copy()

                if ($CurrentStandard.remediate -eq $true -or $CurrentStandard.alert -eq $true -or $CurrentStandard.report -eq $true) {
                    # Write-Host "`r`nTenant: $StandardName"
                    if (!$ComputedStandards[$StandardName] ) {
                        #Write-Host "Applying tenant level $StandardName"
                        $ComputedStandards[$StandardName] = $CurrentStandard
                    } else {
                        foreach ($Setting in $CurrentStandard.PSObject.Properties.Name) {
                            if ($CurrentStandard.$Setting -ne $false -and ($CurrentStandard.$Setting -ne $ComputedStandards[$StandardName].$($Setting) -and ![string]::IsNullOrWhiteSpace($CurrentStandard.$Setting) -or ($null -ne $CurrentStandard.$Setting -and $null -ne $ComputedStandards[$StandardName].$($Setting) -and (Compare-Object $CurrentStandard.$Setting $ComputedStandards[$StandardName].$($Setting))))) {
                                #Write-Host "Overriding $Setting for $StandardName at tenant level"
                                if ($ComputedStandards[$StandardName].PSObject.Properties.Name -contains $Setting) {
                                    $ComputedStandards[$StandardName].$($Setting) = $CurrentStandard.$Setting
                                } else {
                                    $ComputedStandards[$StandardName] | Add-Member -NotePropertyName $Setting -NotePropertyValue $CurrentStandard.$Setting
                                }
                            }
                        }
                    }
                }
            }

            foreach ($Standard in $ComputedStandards.Keys) {
                [pscustomobject]@{
                    Tenant   = $Tenant.defaultDomainName
                    Standard = $Standard
                    Settings = $ComputedStandards.$Standard
                }
            }
        }
    }
}
