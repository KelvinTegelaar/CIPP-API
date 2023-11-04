function Test-CIPPAccessTenant {
    [CmdletBinding()]
    param (
        $TenantCSV,
        $APIName = "Access Check",
        $ExecutingUser
    )
    $ExpectedRoles = @(
        @{ Name = 'Application Administrator'; Id = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' },
        @{ Name = 'User Administrator'; Id = 'fe930be7-5e62-47db-91af-98c3a49a38b1' },
        @{ Name = 'Intune Administrator'; Id = '3a2c62db-5318-420d-8d74-23affee5d9d5' },
        @{ Name = 'Exchange Administrator'; Id = '29232cdf-9323-42fd-ade2-1d097af3e4de' },
        @{ Name = 'Security Administrator'; Id = '194ae4cb-b126-40b2-bd5b-6091b380977d' },
        @{ Name = 'Cloud App Security Administrator'; Id = '892c5842-a9a6-463a-8041-72aa08ca3cf6' },
        @{ Name = 'Cloud Device Administrator'; Id = '7698a772-787b-4ac8-901f-60d6b08affd2' },
        @{ Name = 'Teams Administrator'; Id = '69091246-20e8-4a56-aa4d-066075b2a7a8' },
        @{ Name = 'Sharepoint Administrator'; Id = 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' },
        @{ Name = 'Authentication Policy Administrator'; Id = '0526716b-113d-4c15-b2c8-68e3c22b9f80' },
        @{ Name = 'Privileged Role Administrator'; Id = 'e8611ab8-c189-46e8-94e1-60213ab1f814' },
        @{ Name = 'Privileged Authentication Administrator'; Id = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' }
    )
    $Tenants = ($TenantCSV).split(',')
    if (!$Tenants) { $results = 'Could not load the tenants list from cache. Please run permissions check first, or visit the tenants page.' }
    $TenantList = Get-Tenants
    $TenantIds = foreach ($Tenant in $Tenants) {
        ($TenantList | Where-Object { $_.defaultDomainName -eq $Tenant }).customerId
    }
    $MyRoles = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/myRoles?`$filter=tenantId in ('$($TenantIds -join "','")')"
    $results = foreach ($tenant in $Tenants) {
        $AddedText = ''
        try {
            $TenantId = ($TenantList | Where-Object { $_.defaultDomainName -eq $tenant }).customerId
            $Assignments = ($MyRoles | Where-Object { $_.tenantId -eq $TenantId }).assignments
            $SAMUserRoles = ($Assignments | Where-Object { $_.assignmentType -eq 'granularDelegatedAdminPrivileges' }).roles

            $BulkRequests = $ExpectedRoles | ForEach-Object { @(
                    @{
                        id     = "roleManagement_$($_.id)"
                        method = 'GET'
                        url    = "roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$($_.id)'&`$expand=principal"
                    }
                )
            }
            $GDAPRolesGraph = New-GraphBulkRequest -tenantid $tenant -Requests $BulkRequests
            $GDAPRoles = [System.Collections.Generic.List[object]]::new()
            $MissingRoles = [System.Collections.Generic.List[object]]::new()
            foreach ($RoleId in $ExpectedRoles) {
                $GraphRole = $GDAPRolesGraph.body.value | Where-Object -Property roleDefinitionId -EQ $RoleId.Id
                $Role = $GraphRole.principal | Where-Object -Property organizationId -EQ $ENV:tenantid
                $SAMRole = $SAMUserRoles | Where-Object -Property templateId -EQ $RoleId.Id
                if (!$Role) {
                    $MissingRoles.Add(
                        [PSCustomObject]@{
                            Name = $RoleId.Name
                            Type = 'Tenant'
                        }
                    )
                    $AddedText = 'but missing GDAP roles'
                }
                else {
                    $GDAPRoles.Add([PSCustomObject]$RoleId)
                }
                if (!$SAMRole) {
                    $MissingRoles.Add(
                        [PSCustomObject]@{
                            Name = $RoleId.Name
                            Type = 'SAM User'
                        }
                    )
                    $AddedText = 'but missing GDAP roles'
                }
            }
            if (!($MissingRoles | Measure-Object).Count -gt 0) {
                $MissingRoles = $true
            }
            @{
                TenantName   = "$($Tenant)"
                Status       = "Successfully connected $($AddedText)"
                GDAPRoles    = $GDAPRoles
                MissingRoles = $MissingRoles
                SAMUserRoles = $SAMUserRoles
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message 'Tenant access check executed successfully' -Sev 'Info'

        }
        catch {
            @{
                TenantName = "$($tenant)"
                Status     = "Failed to connect: $(Get-NormalizedError -message $_.Exception.Message)"
                GDAP       = ''
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check failed: $(Get-NormalizedError -message $_) " -Sev 'Error'

        }

        try {
            $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -ErrorAction Stop
            @{
                TenantName = "$($Tenant)"
                Status     = 'Successfully connected to Exchange'
            }

        }
        catch {
            $ReportedError = ($_.ErrorDetails | ConvertFrom-Json -ErrorAction SilentlyContinue)
            $Message = if ($ReportedError.error.details.message) { $ReportedError.error.details.message } else { $ReportedError.error.innererror.internalException.message }
            if ($null -eq $Message) { $Message = $($_.Exception.Message) }
            @{
                TenantName = "$($Tenant)"
                Status     = "Failed to connect to Exchange: $(Get-NormalizedError -message $Message)"
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check for Exchange failed: $(Get-NormalizedError -message $Message) " -Sev 'Error'
        }
    }
    if (!$Tenants) { $results = 'Could not load the tenants list from cache. Please run permissions check first, or visit the tenants page.' }

    return $results
}
