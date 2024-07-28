function Push-DomainAnalyserTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -IncludeAll | Where-Object { $_.customerId -eq $Item.customerId } | Select-Object -First 1
    $DomainTable = Get-CippTable -tablename 'Domains'

    if ($Tenant.Excluded -eq $true) {
        $Filter = "PartitionKey eq 'TenantDomains' and TenantId eq '{0}'" -f $Tenant.defaultDomainName
        $CleanupRows = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter
        $CleanupCount = ($CleanupRows | Measure-Object).Count
        if ($CleanupCount -gt 0) {
            Write-LogMessage -API 'DomainAnalyser' -tenant $Tenant.defaultDomainName -message "Cleaning up $CleanupCount domain(s) for excluded tenant" -sev Info
            Remove-AzDataTableEntity @DomainTable -Entity $CleanupRows
        }
    } elseif ($Tenant.GraphErrorCount -gt 50) {
        return
    } else {
        try {
            $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $Tenant.customerId | Where-Object { ($_.id -notlike '*.microsoftonline.com' -and $_.id -NotLike '*.exclaimer.cloud' -and $_.id -Notlike '*.excl.cloud' -and $_.id -NotLike '*.codetwo.online' -and $_.id -NotLike '*.call2teams.com' -and $_.isVerified) }

            $TenantDomains = foreach ($d in $Domains) {
                [PSCustomObject]@{
                    Tenant             = $Tenant.defaultDomainName
                    TenantGUID         = $Tenant.customerId
                    InitialDomainName  = $Tenant.initialDomainName
                    Domain             = $d.id
                    AuthenticationType = $d.authenticationType
                    IsAdminManaged     = $d.isAdminManaged
                    IsDefault          = $d.isDefault
                    IsInitial          = $d.isInitial
                    IsRoot             = $d.isRoot
                    IsVerified         = $d.isVerified
                    SupportedServices  = $d.supportedServices
                }
            }

            Write-Information ($TenantDomains | ConvertTo-Json -Depth 10)

            $DomainCount = ($TenantDomains | Measure-Object).Count
            if ($DomainCount -gt 0) {
                Write-Host "############# $DomainCount tenant Domains"
                $TenantDomainObjects = [System.Collections.Generic.List[object]]::new()
                try {
                    foreach ($TenantDomain in $TenantDomains) {
                        $TenantDetails = ($TenantDomain | ConvertTo-Json -Compress).ToString()
                        $Filter = "PartitionKey eq '{0}' and RowKey eq '{1}'" -f $TenantDomain.Tenant, $TenantDomain.Domain
                        $OldDomain = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter

                        if ($OldDomain) {
                            Remove-AzDataTableEntity @DomainTable -Entity $OldDomain | Out-Null
                        }

                        $Filter = "PartitionKey eq 'TenantDomains' and RowKey eq '{0}'" -f $TenantDomain.Domain
                        $Domain = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter

                        if (!$Domain -or $null -eq $TenantDomain.TenantGUID) {
                            $Domain = [pscustomobject]@{
                                DomainAnalyser = ''
                                TenantDetails  = $TenantDetails
                                TenantId       = $TenantDomain.Tenant
                                TenantGUID     = $TenantDomain.TenantGUID
                                DkimSelectors  = ''
                                MailProviders  = ''
                                RowKey         = $TenantDomain.Domain
                                PartitionKey   = 'TenantDomains'
                            }

                            if ($OldDomain) {
                                $DomainObject.DkimSelectors = $OldDomain.DkimSelectors
                                $DomainObject.MailProviders = $OldDomain.MailProviders
                            }
                        } else {
                            $Domain.TenantDetails = $TenantDetails
                            if ($OldDomain) {
                                $Domain.DkimSelectors = $OldDomain.DkimSelectors
                                $Domain.MailProviders = $OldDomain.MailProviders
                            }
                        }
                        # Return domain object to list
                        $TenantDomainObjects.Add($Domain)
                    }

                    # Batch insert tenant domains
                    try {
                        Add-CIPPAzDataTableEntity @DomainTable -Entity $TenantDomainObjects -Force
                        $InputObject = [PSCustomObject]@{
                            QueueFunction    = @{
                                FunctionName = 'GetTenantDomains'
                                TenantGUID   = $Tenant.customerId
                            }
                            OrchestratorName = "DomainAnalyser_$($Tenant.defaultDomainName)"
                            SkipLog          = $true
                        }
                        Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
                        Write-Host "Started analysis for $DomainCount tenant domains in $($Tenant.defaultDomainName)"
                        Write-LogMessage -API 'DomainAnalyser' -tenant $Tenant.defaultDomainName -message "Started analysis for $DomainCount tenant domains" -sev Info
                    } catch {
                        Write-LogMessage -API 'DomainAnalyser' -message 'Domain Analyser GetTenantDomains error' -sev 'Error' -LogData (Get-CippException -Exception $_)
                    }
                } catch {
                    Write-LogMessage -API 'DomainAnalyser' -message 'GetTenantDomains loop error' -sev 'Error' -LogData (Get-CippException -Exception $_)
                }
            }
        } catch {
            #Write-Host (Get-CippException -Exception $_ | ConvertTo-Json)
            Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.defaultDomainName -message 'DNS Analyser GraphGetRequest' -LogData (Get-CippException -Exception $_) -sev Error
        }
    }
    return $null
}
