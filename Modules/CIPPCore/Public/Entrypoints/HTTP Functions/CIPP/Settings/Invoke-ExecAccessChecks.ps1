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
                $Cache = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'AccessPermissions'"
                Write-Host $Cache
                try {
                    $Results = $Cache.Data | ConvertFrom-Json
                } catch {
                    $Results = $null
                }
                if (!$Results) {
                    $Results = Test-CIPPAccessPermissions -tenantfilter $ENV:TenantID -APIName $APINAME -ExecutingUser $Request.Headers.'x-ms-client-principal'
                } else {
                    $LastRun = [DateTime]::SpecifyKind($Cache.Timestamp.DateTime, [DateTimeKind]::Utc)
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
                            GraphStatus       = $null
                            ExchangeStatus    = $null
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
                    $LastRun = [DateTime]::SpecifyKind($LastRunTime.Timestamp.DateTime, [DateTimeKind]::Utc)
                } catch {
                    $Results = @()
                }
            }

            if ($Request.Query.SkipCache -eq 'true') {
                $null = Test-CIPPAccessTenant -ExecutingUser $Request.Headers.'x-ms-client-principal'
            }

            if ($Request.Body.TenantId) {
                $Tenant = $Request.Body.TenantId
                $null = Test-CIPPAccessTenant -Tenant $Tenant -ExecutingUser $Request.Headers.'x-ms-client-principal'
                $Results = "Refreshing tenant $Tenant"
            }

        }
        'GDAP' {
            if (!$Request.Query.SkipCache -eq 'true') {
                $Cache = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'GDAPRelationships'"
                try {
                    $Results = $Cache.Data | ConvertFrom-Json
                } catch {
                    $Results = $null
                }
                if (!$Results) {
                    $Results = Test-CIPPGDAPRelationships
                } else {
                    $LastRun = [DateTime]::SpecifyKind($Cache.Timestamp.DateTime, [DateTimeKind]::Utc)
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
