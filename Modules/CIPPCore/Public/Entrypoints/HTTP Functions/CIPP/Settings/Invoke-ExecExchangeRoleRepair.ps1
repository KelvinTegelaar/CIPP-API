function Invoke-ExecExchangeRoleRepair {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers

    $TenantId = $Request.Query.tenantId ?? $Request.Body.tenantId
    $Tenant = Get-Tenants -TenantFilter $TenantId

    try {
        Write-Information "Starting Exchange Organization Management role repair for tenant: $($Tenant.defaultDomainName)"
        $OrgManagementRoles = New-ExoRequest -tenantid $Tenant.customerId -cmdlet 'Get-ManagementRoleAssignment' -cmdParams @{ Delegating = $false } | Where-Object { $_.RoleAssigneeName -eq 'Organization Management' } | Select-Object -Property Role, Guid
        Write-Information "Found $($OrgManagementRoles.Count) Organization Management roles in Exchange"

        $RoleDefinitions = New-GraphGetRequest -tenantid $Tenant.customerId -uri 'https://graph.microsoft.com/beta/roleManagement/exchange/roleDefinitions'
        Write-Information "Found $($RoleDefinitions.Count) Exchange role definitions"

        $BasePath = Get-Module -Name 'CIPPCore' | Select-Object -ExpandProperty ModuleBase
        $AllOrgManagementRoles = Get-Content -Path "$BasePath\Public\OrganizationManagementRoles.json" -ErrorAction Stop | ConvertFrom-Json

        $AvailableRoles = $RoleDefinitions | Where-Object -Property displayName -In $AllOrgManagementRoles | Select-Object -Property displayName, id, description
        Write-Information "Found $($AvailableRoles.Count) available Organization Management roles in Exchange"
        $MissingOrgMgmtRoles = $AvailableRoles | Where-Object { $OrgManagementRoles.Role -notcontains $_.displayName }

        if ($MissingOrgMgmtRoles.Count -gt 0) {
            $Requests = foreach ($Role in $MissingOrgMgmtRoles) {
                [PSCustomObject]@{
                    id      = $Role.id
                    method  = 'POST'
                    url     = 'roleManagement/exchange/roleAssignments'
                    body    = @{
                        principalId      = '/RoleGroups/Organization Management'
                        roleDefinitionId = $Role.id
                        directoryScopeId = '/'
                        appScopeId       = $null
                    }
                    headers = @{
                        'Content-Type' = 'application/json'
                    }
                }
            }

            $RepairResults = New-GraphBulkRequest -tenantid $Tenant.customerId -Requests @($Requests) -asapp $true
            $RepairSuccess = $RepairResults.status -eq 201
            if ($RepairSuccess) {
                $Results = @{
                    state      = 'success'
                    resultText = "Successfully repaired the missing Organization Management roles: $($MissingOrgMgmtRoles.displayName -join ', ')"
                }
                Write-LogMessage -API 'ExecExchangeRoleRepair' -headers $Headers -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -Message "Successfully repaired the missing Organization Management roles: $($MissingOrgMgmtRoles.displayName -join ', '). Run another Tenant Access check after waiting a bit for replication." -sev 'Info'
            } else {
                # Get roles that failed to repair
                $FailedRoles = $RepairResults | Where-Object { $_.status -ne 201 } | ForEach-Object {
                    $RoleId = $_.id
                    $Role = $MissingOrgMgmtRoles | Where-Object { $_.id -eq $RoleId }
                    $Role.displayName
                }
                $PermissionError = $false
                if ($RepairResults.status -in (401, 403, 500)) {
                    $PermissionError = $true
                }
                $LogData = $RepairResults | Select-Object -Property id, status, body
                $Results = @{
                    state      = 'error'
                    resultText = "Failed to repair the missing Organization Management roles: $($FailedRoles -join ', ').$(if ($PermissionError) { " This may be due to insufficient permissions. The required Graph Permission is 'Application - RoleManagement.ReadWrite.Exchange'" })"
                }
                Write-LogMessage -API 'ExecExchangeRoleRepair' -headers $Headers -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -Message "Failed to repair the missing Organization Management roles: $($FailedRoles -join ', ')" -sev 'Error' -LogData $LogData
                Write-Warning 'Exchange role repair failed'
            }
        } else {
            $Results = @{
                state      = 'success'
                resultText = 'No missing Organization Management roles found.'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Warning "Exception during Exchange Organization Management role repair: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API 'ExecExchangeRoleRepair' -headers $Headers -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -Message "Exchange Organization Management role repair failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        $Results = @{
            state      = 'error'
            resultText = "Exchange Organization Management role repair failed: $($ErrorMessage.NormalizedError)"
        }
    }

    Push-OutputBinding -Name 'Response' -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body       = $Results
        })
}
