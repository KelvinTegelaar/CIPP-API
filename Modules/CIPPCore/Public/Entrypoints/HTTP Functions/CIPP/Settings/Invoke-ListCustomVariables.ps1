function Invoke-ListCustomVariables {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    $HttpResponse = [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{}
    }

    try {
        # Define reserved variables (matching Get-CIPPTextReplacement)
        $ReservedVariables = @(
            @{
                Name        = 'tenantid'
                Variable    = '%tenantid%'
                Description = 'The tenant customer ID'
                Type        = 'reserved'
                Category    = 'tenant'
            },
            @{
                Name        = 'organizationid'
                Variable    = '%organizationid%'
                Description = 'The tenant customer ID'
                Type        = 'reserved'
                Category    = 'tenant'
            },
            @{
                Name        = 'tenantfilter'
                Variable    = '%tenantfilter%'
                Description = 'The tenant default domain name'
                Type        = 'reserved'
                Category    = 'tenant'
            },
            @{
                Name        = 'tenantname'
                Variable    = '%tenantname%'
                Description = 'The tenant display name'
                Type        = 'reserved'
                Category    = 'tenant'
            },
            @{
                Name        = 'defaultdomain'
                Variable    = '%defaultdomain%'
                Description = 'The tenant default domain name'
                Type        = 'reserved'
                Category    = 'tenant'
            },
            @{
                Name        = 'initialdomain'
                Variable    = '%initialdomain%'
                Description = 'The tenant initial domain name'
                Type        = 'reserved'
                Category    = 'tenant'
            },
            @{
                Name        = 'partnertenantid'
                Variable    = '%partnertenantid%'
                Description = 'The partner tenant ID'
                Type        = 'reserved'
                Category    = 'partner'
            },
            @{
                Name        = 'samappid'
                Variable    = '%samappid%'
                Description = 'The SAM application ID'
                Type        = 'reserved'
                Category    = 'partner'
            },
            @{
                Name        = 'cippuserschema'
                Variable    = '%cippuserschema%'
                Description = 'The CIPP user schema extension ID'
                Type        = 'reserved'
                Category    = 'cipp'
            },
            @{
                Name        = 'cippurl'
                Variable    = '%cippurl%'
                Description = 'The CIPP instance URL'
                Type        = 'reserved'
                Category    = 'cipp'
            },
            @{
                Name        = 'serial'
                Variable    = '%serial%'
                Description = 'System serial number'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'systemroot'
                Variable    = '%systemroot%'
                Description = 'System root directory'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'systemdrive'
                Variable    = '%systemdrive%'
                Description = 'System drive letter'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'temp'
                Variable    = '%temp%'
                Description = 'Temporary directory path'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'userprofile'
                Variable    = '%userprofile%'
                Description = 'User profile directory'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'username'
                Variable    = '%username%'
                Description = 'Current username'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'userdomain'
                Variable    = '%userdomain%'
                Description = 'User domain'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'windir'
                Variable    = '%windir%'
                Description = 'Windows directory'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'programfiles'
                Variable    = '%programfiles%'
                Description = 'Program Files directory'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'programfiles(x86)'
                Variable    = '%programfiles(x86)%'
                Description = 'Program Files (x86) directory'
                Type        = 'reserved'
                Category    = 'system'
            },
            @{
                Name        = 'programdata'
                Variable    = '%programdata%'
                Description = 'Program Data directory'
                Type        = 'reserved'
                Category    = 'system'
            }
        )

        # Use a hashtable to track variables by name to handle overrides
        $VariableMap = @{}

        if ($Request.Query.includeSystem -and $Request.Query.includeSystem -ne 'true') {
            $ReservedVariables = $ReservedVariables | Where-Object { $_.Category -ne 'system' }
        }

        # Filter out global reserved variables if requested (for tenant group rules)
        # These variables are the same for all tenants so they're not useful for grouping
        if ($Request.Query.excludeGlobalReserved -eq 'true') {
            $ReservedVariables = $ReservedVariables | Where-Object {
                $_.Category -notin @('partner', 'cipp', 'system')
            }
        }

        # Add reserved variables first
        foreach ($Variable in $ReservedVariables) {
            $VariableMap[$Variable.Name] = $Variable
        }

        # Get custom variables from the replace map table
        $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'

        # Get global variables (AllTenants) - these can be overridden by tenant-specific ones
        $GlobalVariables = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq 'AllTenants'"
        if ($GlobalVariables) {
            foreach ($Variable in $GlobalVariables) {
                if ($Variable.RowKey -and $Variable.Value) {
                    $VariableMap[$Variable.RowKey] = @{
                        Name        = $Variable.RowKey
                        Variable    = "%$($Variable.RowKey)%"
                        Description = 'Global custom variable'
                        Value       = $Variable.Value
                        Type        = 'custom'
                        Category    = 'global'
                        Scope       = 'AllTenants'
                    }
                }
            }
        }

        # Get tenant-specific variables if tenantFilter is provided
        # These override any global variables with the same name
        $TenantFilter = $Request.Query.tenantFilter
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            # Try to get tenant to find customerId
            try {
                $Tenant = Get-Tenants -TenantFilter $TenantFilter
                $CustomerId = $Tenant.customerId

                # Get variables by customerId
                $TenantVariables = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$CustomerId'"

                # If no results found by customerId, try by defaultDomainName
                if (-not $TenantVariables) {
                    $TenantVariables = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$($Tenant.defaultDomainName)'"
                }

                if ($TenantVariables) {
                    foreach ($Variable in $TenantVariables) {
                        if ($Variable.RowKey -and $Variable.Value) {
                            # Tenant variables override global ones with the same name
                            $VariableMap[$Variable.RowKey] = @{
                                Name        = $Variable.RowKey
                                Variable    = "%$($Variable.RowKey)%"
                                Description = 'Tenant-specific custom variable'
                                Value       = $Variable.Value
                                Type        = 'custom'
                                Category    = 'tenant-custom'
                                Scope       = $TenantFilter
                            }
                        }
                    }
                }
            } catch {
                Write-LogMessage -API $APIName -message "Could not retrieve tenant-specific variables for $TenantFilter : $($_.Exception.Message)" -sev 'Warn'
            }
        }

        # Convert hashtable values to array and sort
        $AllVariables = $VariableMap.Values
        $SortedVariables = $AllVariables | Sort-Object @{
            Expression = {
                switch ($_.Type) {
                    'reserved' { 1 }
                    'custom' {
                        switch ($_.Category) {
                            'global' { 2 }
                            'tenant-custom' { 3 }
                            default { 4 }
                        }
                    }
                    default { 5 }
                }
            }
        }, Name

        $HttpResponse.Body = @{
            Results  = @($SortedVariables)
            Metadata = @{
                TenantFilter  = $TenantFilter
                TotalCount    = $SortedVariables.Count
                ReservedCount = @($SortedVariables | Where-Object { $_.Type -eq 'reserved' }).Count
                CustomCount   = @($SortedVariables | Where-Object { $_.Type -eq 'custom' }).Count
            }
        }

    } catch {
        $HttpResponse.StatusCode = [HttpStatusCode]::InternalServerError
        $HttpResponse.Body = @{
            Results = @()
            Error   = $_.Exception.Message
        }
        Write-LogMessage -API $APIName -message "Failed to retrieve custom variables: $($_.Exception.Message)" -Sev 'Error'
    }

    return $HttpResponse
}
