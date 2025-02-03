function Test-CIPPAccessTenant {
    [CmdletBinding()]
    param (
        $Tenant = 'AllTenants',
        $APIName = 'Access Check',
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

    $TenantParams = @{
        IncludeErrors = $true
    }
    if ($Tenant -eq 'AllTenants') {
        $TenantList = Get-Tenants @TenantParams
        $Queue = New-CippQueueEntry -Name 'Tenant Access Check' -TotalTasks ($TenantList | Measure-Object).Count

        $InputObject = [PSCustomObject]@{
            QueueFunction    = @{
                FunctionName = 'GetTenants'
                TenantParams = $TenantParams
                DurableName  = 'CIPPAccessTenantTest'
                QueueId      = $Queue.RowKey
            }
            OrchestratorName = 'CippAccessTenantTest'
            SkipLog          = $true
        }
        $null = Start-NewOrchestration -FunctionName CIPPOrchestrator -InputObject ($InputObject | ConvertTo-Json -Depth 10)
        $Results = "Queued $($TenantList.Count) tenants for access checks"

    } else {
        $TenantParams.TenantFilter = $Tenant
        $Tenant = Get-Tenants @TenantParams

        $GraphStatus = $false
        $ExchangeStatus = $false

        $Results = [PSCustomObject]@{
            TenantName     = $Tenant.defaultDomainName
            GraphStatus    = $false
            GraphTest      = ''
            ExchangeStatus = $false
            ExchangeTest   = ''
            GDAPRoles      = ''
            MissingRoles   = ''
            LastRun        = (Get-Date).ToUniversalTime()
        }

        $AddedText = ''
        try {
            $TenantId = $Tenant.customerId
            $BulkRequests = $ExpectedRoles | ForEach-Object { @(
                    @{
                        id     = "roleManagement_$($_.Id)"
                        method = 'GET'
                        url    = "roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$($_.Id)'&`$expand=principal"
                    }
                )
            }
            $GDAPRolesGraph = New-GraphBulkRequest -tenantid $TenantId -Requests $BulkRequests
            $GDAPRoles = [System.Collections.Generic.List[object]]::new()
            $MissingRoles = [System.Collections.Generic.List[object]]::new()

            foreach ($RoleId in $ExpectedRoles) {
                $GraphRole = $GDAPRolesGraph.body.value | Where-Object -Property roleDefinitionId -EQ $RoleId.Id
                $Role = $GraphRole.principal | Where-Object -Property organizationId -EQ $ENV:TenantID

                if (!$Role) {
                    $MissingRoles.Add(
                        [PSCustomObject]@{
                            Name = $RoleId.Name
                            Type = 'Tenant'
                        }
                    )
                    $AddedText = 'but missing GDAP roles'
                } else {
                    $GDAPRoles.Add([PSCustomObject]@{
                            Role  = $RoleId.Name
                            Group = $Role.displayName
                        })
                }
            }

            $GraphTest = "Successfully connected to Graph $($AddedText)"
            $GraphStatus = $true
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $GraphTest = "Failed to connect to Graph: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $tenant.defaultDomainName -message "Tenant access check failed: $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
        }

        try {
            $null = New-ExoRequest -tenantid $Tenant.customerId -cmdlet 'Get-OrganizationConfig' -ErrorAction Stop
            $ExchangeStatus = $true
            $ExchangeTest = 'Successfully connected to Exchange'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $ReportedError = ($_.ErrorDetails | ConvertFrom-Json -ErrorAction SilentlyContinue)
            $Message = if ($ReportedError.error.details.message) { $ReportedError.error.details.message } else { $ReportedError.error.innererror.internalException.message }
            if ($null -eq $Message) { $Message = $($_.Exception.Message) }

            $ExchangeTest = "Failed to connect to Exchange: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $tenant.defaultDomainName -message "Tenant access check for Exchange failed: $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
        }

        if ($GraphStatus -and $ExchangeStatus) {
            Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $Tenant.defaultDomainName -tenantId $Tenant.customerId -message 'Tenant access check executed successfully' -Sev 'Info'
        }

        $Results.GraphStatus = $GraphStatus
        $Results.GraphTest = $GraphTest
        $Results.ExchangeStatus = $ExchangeStatus
        $Results.ExchangeTest = $ExchangeTest
        $Results.GDAPRoles = @($GDAPRoles)
        $Results.MissingRoles = @($MissingRoles)

        $ExecutingUser = $ExecutingUser.UserDetails
        $Entity = @{
            PartitionKey = 'TenantAccessChecks'
            RowKey       = $Tenant.customerId
            Data         = [string]($Results | ConvertTo-Json -Depth 10 -Compress)
        }
        $Table = Get-CIPPTable -TableName 'AccessChecks'
        try {
            $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        } catch {
            Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $Tenant.defaultDomainName -message "Failed to add access check for $($Tenant.customerId): $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        }
    }

    return $Results
}
