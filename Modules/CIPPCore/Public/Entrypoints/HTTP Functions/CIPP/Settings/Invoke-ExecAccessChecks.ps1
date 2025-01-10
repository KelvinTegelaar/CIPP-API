using namespace System.Net

Function Invoke-ExecAccessChecks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -tablename 'AccessChecks'
    $LastRun = (Get-Date).ToUniversalTime()
    switch ($Request.Query.Type) {
        'Permissions' {
            if ($Request.Query.SkipCache -ne 'true') {
                try {
                    $Cache = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'AccessPermissions'"
                    $Results = $Cache.Data | ConvertFrom-Json
                } catch {
                    $Results = $null
                }
                if (!$Results) {
                    $Results = Test-CIPPAccessPermissions -tenantfilter $ENV:TenantID -APIName $APINAME -ExecutingUser $Request.Headers.'x-ms-client-principal'
                } else {
                    try {
                        $LastRun = [DateTime]::SpecifyKind($Cache.Timestamp.DateTime, [DateTimeKind]::Utc)
                    } catch {
                        $LastRun = $null
                    }
                }
            } else {
                $Results = Test-CIPPAccessPermissions -tenantfilter $ENV:TenantID -APIName $APINAME -ExecutingUser $Request.Headers.'x-ms-client-principal'
            }
        }
        'Tenants' {
            $AccessChecks = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantAccessChecks'"
            if (!$Request.Body.TenantId) {
                try {
                    $Tenants = Get-Tenants -IncludeErrors
                    $Results = foreach ($Tenant in $Tenants) {
                        $TenantCheck = $AccessChecks | Where-Object -Property RowKey -EQ $Tenant.customerId | Select-Object -Property Data
                        $TenantResult = [PSCustomObject]@{
                            TenantId          = $Tenant.customerId
                            TenantName        = $Tenant.displayName
                            DefaultDomainName = $Tenant.defaultDomainName
                            GraphStatus       = 'Not run yet'
                            ExchangeStatus    = 'Not run yet'
                            GDAPRoles         = ''
                            MissingRoles      = ''
                            LastRun           = ''
                            GraphTest         = ''
                            ExchangeTest      = ''
                        }
                        if ($TenantCheck) {
                            $Data = @($TenantCheck.Data | ConvertFrom-Json)
                            $TenantResult.GraphStatus = $Data.GraphStatus
                            $TenantResult.ExchangeStatus = $Data.ExchangeStatus
                            $TenantResult.GDAPRoles = $Data.GDAPRoles
                            $TenantResult.MissingRoles = $Data.MissingRoles
                            $TenantResult.LastRun = $Data.LastRun
                            $TenantResult.GraphTest = $Data.GraphTest
                            $TenantResult.ExchangeTest = $Data.ExchangeTest
                        }
                        $TenantResult
                    }

                    $LastRunTime = $AccessChecks | Sort-Object Timestamp | Select-Object -Property Timestamp -Last 1
                    try {
                        $LastRun = [DateTime]::SpecifyKind($LastRunTime.Timestamp.DateTime, [DateTimeKind]::Utc)
                    } catch {
                        $LastRun = $null
                    }
                } catch {
                    Write-Host $_.Exception.Message
                    $Results = @()
                }
            }

            if ($Request.Query.SkipCache -eq 'true') {
                $null = Test-CIPPAccessTenant -ExecutingUser $Request.Headers.'x-ms-client-principal'
            }

            if ($Request.Body.TenantId) {
                $Tenant = Get-Tenants -TenantFilter $Request.Body.TenantId
                $null = Test-CIPPAccessTenant -Tenant $Tenant.customerId -ExecutingUser $Request.Headers.'x-ms-client-principal'
                $Results = "Refreshing tenant $($Tenant.displayName)"
            }

        }
        'GDAP' {
            if (!$Request.Query.SkipCache -eq 'true') {
                try {
                    $Cache = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'GDAPRelationships'"
                    $Results = $Cache.Data | ConvertFrom-Json
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

    $body = [pscustomobject]@{
        'Results'  = $Results
        'Metadata' = @{
            'LastRun' = $LastRun
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
