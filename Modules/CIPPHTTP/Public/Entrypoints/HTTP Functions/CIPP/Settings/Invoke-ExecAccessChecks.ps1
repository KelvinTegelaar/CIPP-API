function Invoke-ExecAccessChecks {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.Read
    .DESCRIPTION
        Runs the CIPP deployment's self-diagnostics and returns the result. Type selects the check: 'Permissions' verifies the SAM application's Graph permissions, 'Tenants' tests access to each tenant, and 'GDAP' inspects the GDAP relationships and role mappings. Results are cached for an hour unless SkipCache is true.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Table = Get-CIPPTable -tablename 'AccessChecks'
    $LastRun = (Get-Date).ToUniversalTime()
    $4HoursAgo = (Get-Date).AddHours(-1).ToUniversalTime()
    $TimestampFilter = $4HoursAgo.ToString('yyyy-MM-ddTHH:mm:ss.fffK')

    # Which self-diagnostic to run: Permissions, Tenants or GDAP. Read from either the query
    # string or the body: the UI calls this as a GET with ?Type=, while a POST dispatcher (the
    # MCP gateway documents it as POST because it also reads a body field) delivers it in the
    # body - reading only the query left both empty and returned an empty result for every Type.
    $Type = $Request.Query.Type ?? $Request.Body.Type

    # Re-run the check instead of serving the cached result.
    $SkipCache = ($Request.Query.SkipCache ?? $Request.Body.SkipCache) -eq $true

    # The tenant to (re)check for the 'Tenants' type. Query or body, for the same reason as Type.
    $TenantId = $Request.Body.TenantId ?? $Request.Query.TenantId

    switch ($Type) {
        'Permissions' {
            if (-not $SkipCache) {
                try {
                    $Cache = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'AccessPermissions' and Timestamp and Timestamp ge datetime'$TimestampFilter'"
                    $Results = $Cache.Data | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    $Results = $null
                }
                if (!$Results) {
                    $Results = Test-CIPPAccessPermissions -tenantfilter $env:TenantID -APIName $APINAME -Headers $Request.Headers
                } else {
                    try {
                        $LastRun = [DateTime]::SpecifyKind($Cache.Timestamp.DateTime, [DateTimeKind]::Utc)
                    } catch {
                        $LastRun = $null
                    }
                }
            } else {
                $Results = Test-CIPPAccessPermissions -tenantfilter $env:TenantID -APIName $APINAME -Headers $Request.Headers
            }
        }
        'Tenants' {
            $AccessChecks = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantAccessChecks'"
            if (!$TenantId) {
                try {
                    $Tenants = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -ne $env:TenantID }
                    $Results = foreach ($Tenant in $Tenants) {
                        $TenantCheck = $AccessChecks | Where-Object -Property RowKey -EQ $Tenant.customerId | Select-Object -Property Data
                        $TenantResult = [PSCustomObject]@{
                            TenantId                  = $Tenant.customerId
                            TenantName                = $Tenant.displayName
                            DefaultDomainName         = $Tenant.defaultDomainName
                            TenantType                = if ($Tenant.delegatedPrivilegeStatus -eq 'directTenant') { 'Direct' } else { 'GDAP' }
                            ServiceAccount            = $Tenant.directTenantUserPrincipalName
                            ServiceAccountLastAuth    = $Tenant.directTenantAuthDate
                            GraphStatus               = 'Not run yet'
                            ExchangeStatus            = 'Not run yet'
                            AssignedRoles             = ''
                            MissingRoles              = ''
                            LastRun                   = ''
                            GraphTest                 = ''
                            ExchangeTest              = ''
                            OrgManagementRoles        = @()
                            OrgManagementRolesMissing = @()
                            OrgManagementRepairNeeded = $false
                        }
                        if ($TenantCheck) {
                            $Data = @($TenantCheck.Data | ConvertFrom-Json -ErrorAction Stop)
                            $TenantResult.GraphStatus = $Data.GraphStatus
                            $TenantResult.ExchangeStatus = $Data.ExchangeStatus
                            # Fall back to the old property name so checks cached before the rename
                            # keep rendering until the tenant is checked again.
                            $TenantResult.AssignedRoles = $Data.AssignedRoles ?? $Data.GDAPRoles
                            $TenantResult.MissingRoles = $Data.MissingRoles
                            $TenantResult.LastRun = $Data.LastRun
                            $TenantResult.GraphTest = $Data.GraphTest
                            $TenantResult.ExchangeTest = $Data.ExchangeTest
                            $TenantResult.OrgManagementRoles = $Data.OrgManagementRoles ? @($Data.OrgManagementRoles) : @()
                            $TenantResult.OrgManagementRolesMissing = $Data.OrgManagementRolesMissing ? @($Data.OrgManagementRolesMissing) : @()
                            $TenantResult.OrgManagementRepairNeeded = $Data.OrgManagementRolesMissing.Count -gt 0
                            # The check reads the account live, so it also backfills direct tenants
                            # onboarded before the service account was recorded on the tenant.
                            if ($Data.ServiceAccount) {
                                $TenantResult.ServiceAccount = $Data.ServiceAccount
                            }
                        }
                        $TenantResult
                    }

                    $LastRunTime = $AccessChecks | Sort-Object Timestamp | Select-Object -Property Timestamp -Last 1
                    try {
                        $LastRun = [DateTime]::SpecifyKind($LastRunTime.Timestamp.DateTime, [DateTimeKind]::Utc)
                    } catch {
                        $LastRun = $null
                    }

                    if (!$Results) {
                        $Results = @()
                    }
                } catch {
                    Write-Warning "Error running tenant access check - $($_.Exception.Message)"
                    $Results = @()
                }
            }

            if ($SkipCache -or $LastRun -lt $4HoursAgo) {
                $Message = Test-CIPPAccessTenant -Headers $Request.Headers
            }

            if ($TenantId) {
                $Tenant = Get-Tenants -TenantFilter $TenantId
                $null = Test-CIPPAccessTenant -Tenant $Tenant.customerId -Headers $Request.Headers
                $Results = "Refreshing tenant $($Tenant.displayName)"
            }

        }
        'GDAP' {
            if (-not $SkipCache) {
                try {
                    $Cache = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'GDAPRelationships' and Timestamp ge datetime'$TimestampFilter'"
                    $Results = $Cache.Data | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    $Results = $null
                }
                if (!$Results) {
                    $Results = Test-CIPPGDAPRelationships
                } else {
                    try {
                        $LastRun = [DateTime]::SpecifyKind($Cache.Timestamp.DateTime, [DateTimeKind]::Utc)
                    } catch {
                        $LastRun = $null
                    }
                }
            } else {
                $Results = Test-CIPPGDAPRelationships
            }
        }
    }
    $Metadata = @{
        LastRun = $LastRun
    }
    if ($Message) {
        $Metadata.AlertMessage = $Message
    }

    $body = [pscustomobject]@{
        'Results'  = $Results
        'Metadata' = $Metadata
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
