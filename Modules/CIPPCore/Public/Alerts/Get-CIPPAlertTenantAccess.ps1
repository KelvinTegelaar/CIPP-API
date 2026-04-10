function Get-CIPPAlertTenantAccess {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
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
        @{ Name = 'SharePoint Administrator'; Id = 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' },
        @{ Name = 'Authentication Policy Administrator'; Id = '0526716b-113d-4c15-b2c8-68e3c22b9f80' },
        @{ Name = 'Privileged Role Administrator'; Id = 'e8611ab8-c189-46e8-94e1-60213ab1f814' },
        @{ Name = 'Privileged Authentication Administrator'; Id = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' },
        @{ Name = 'Billing Administrator'; Id = 'b0f54661-2d74-4c50-afa3-1ec803f12efe'; Optional = $true },
        @{ Name = 'Global Reader'; Id = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'; Optional = $true },
        @{ Name = 'Domain Name Administrator'; Id = '8329153b-31d0-4727-b945-745eb3bc5f31'; Optional = $true }
    )

    try {
        $Tenant = Get-Tenants -TenantFilter $TenantFilter -IncludeErrors
        if (-not $Tenant) {
            return
        }
        $TenantId = $Tenant.customerId
        $Issues = [System.Collections.Generic.List[object]]::new()

        # Test Graph API connectivity and GDAP role assignments
        $GraphStatus = $false
        $GraphMessage = ''
        try {
            $BulkRequests = $ExpectedRoles | ForEach-Object {
                @{
                    id     = "roleManagement_$($_.Id)"
                    method = 'GET'
                    url    = "roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$($_.Id)'&`$expand=principal"
                }
            }
            $GDAPRolesGraph = New-GraphBulkRequest -tenantid $TenantId -Requests $BulkRequests
            $MissingRoles = [System.Collections.Generic.List[string]]::new()

            foreach ($RoleId in $ExpectedRoles) {
                $GraphRole = $GDAPRolesGraph.body.value | Where-Object -Property roleDefinitionId -EQ $RoleId.Id
                $Role = $GraphRole.principal | Where-Object -Property organizationId -EQ $env:TenantID
                if (-not $Role -and $RoleId.Optional -ne $true) {
                    $MissingRoles.Add($RoleId.Name)
                }
            }

            $GraphStatus = $true
            if ($MissingRoles.Count -gt 0) {
                $GraphMessage = "Graph connected but missing required GDAP roles: $($MissingRoles -join ', ')"
                $Issues.Add([PSCustomObject]@{
                        Issue        = 'MissingGDAPRoles'
                        Message      = $GraphMessage
                        MissingRoles = ($MissingRoles -join ', ')
                        Tenant       = $TenantFilter
                    })
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -message $_.Exception.Message
            $GraphMessage = "Failed to connect to Graph API: $ErrorMessage"
            $Issues.Add([PSCustomObject]@{
                    Issue   = 'GraphFailure'
                    Message = $GraphMessage
                    Tenant  = $TenantFilter
                })
        }

        # Test Exchange Online connectivity
        $ExchangeStatus = $false
        try {
            $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Get-OrganizationConfig' -ErrorAction Stop
            $ExchangeStatus = $true
        } catch {
            $ErrorMessage = Get-NormalizedError -message $_.Exception.Message
            $Issues.Add([PSCustomObject]@{
                    Issue   = 'ExchangeFailure'
                    Message = "Failed to connect to Exchange Online: $ErrorMessage"
                    Tenant  = $TenantFilter
                })
        }

        # Build alert data only if there are issues
        $AlertData = @()
        if (-not $GraphStatus -and -not $ExchangeStatus) {
            $AlertData = @([PSCustomObject]@{
                    Message        = "Tenant $TenantFilter is inaccessible. Graph API and Exchange Online connectivity both failed. This tenant may have removed GDAP permissions or requires consent refresh."
                    GraphStatus    = $false
                    ExchangeStatus = $false
                    Issues         = ($Issues | ForEach-Object { $_.Message }) -join '; '
                    Tenant         = $TenantFilter
                })
        } elseif (-not $GraphStatus) {
            $AlertData = @([PSCustomObject]@{
                    Message        = "Tenant $TenantFilter has lost Graph API access. $GraphMessage"
                    GraphStatus    = $false
                    ExchangeStatus = $ExchangeStatus
                    Issues         = ($Issues | ForEach-Object { $_.Message }) -join '; '
                    Tenant         = $TenantFilter
                })
        } elseif (-not $ExchangeStatus) {
            $AlertData = @([PSCustomObject]@{
                    Message        = "Tenant $TenantFilter has lost Exchange Online access. This may indicate missing Exchange Administrator GDAP role or removed consent."
                    GraphStatus    = $GraphStatus
                    ExchangeStatus = $false
                    Issues         = ($Issues | ForEach-Object { $_.Message }) -join '; '
                    Tenant         = $TenantFilter
                })
        } elseif ($MissingRoles.Count -gt 0) {
            $AlertData = @([PSCustomObject]@{
                    Message        = "Tenant $TenantFilter is accessible but missing required GDAP roles: $($MissingRoles -join ', '). This may indicate a CIPP-SAM permission update is needed."
                    GraphStatus    = $GraphStatus
                    ExchangeStatus = $ExchangeStatus
                    MissingRoles   = ($MissingRoles -join ', ')
                    Tenant         = $TenantFilter
                })
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Tenant access alert error for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.Message)" -sev Error
    }
}
