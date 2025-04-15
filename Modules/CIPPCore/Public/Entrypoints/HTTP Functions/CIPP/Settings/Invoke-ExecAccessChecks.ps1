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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -tablename 'AccessChecks'
    $LastRun = (Get-Date).ToUniversalTime()
    $4HoursAgo = (Get-Date).AddHours(-1).ToUniversalTime()
    $TimestampFilter = $4HoursAgo.ToString('yyyy-MM-ddTHH:mm:ss.fffK')


    switch ($Request.Query.Type) {
        'Permissions' {
            if ($Request.Query.SkipCache -ne 'true' -or $Request.Query.SkipCache -ne $true) {
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
            if (!$Request.Body.TenantId) {
                try {
                    $Tenants = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -ne $env:TenantID }
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
                            $Data = @($TenantCheck.Data | ConvertFrom-Json -ErrorAction Stop)
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

                    if (!$Results) {
                        $Results = @()
                    }
                } catch {
                    Write-Warning "Error running tenant access check - $($_.Exception.Message)"
                    $Results = @()
                }
            }

            if ($Request.Query.SkipCache -eq 'true' -or $Request.Query.SkipCache -eq $true -or $LastRun -lt $4HoursAgo) {
                $Message = Test-CIPPAccessTenant -Headers $Request.Headers
            }

            if ($Request.Body.TenantId) {
                $Tenant = Get-Tenants -TenantFilter $Request.Body.TenantId
                $null = Test-CIPPAccessTenant -Tenant $Tenant.customerId -Headers $Request.Headers
                $Results = "Refreshing tenant $($Tenant.displayName)"
            }

        }
        'GDAP' {
            if (!$Request.Query.SkipCache -eq 'true' -or !$Request.Query.SkipCache -eq $true) {
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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
