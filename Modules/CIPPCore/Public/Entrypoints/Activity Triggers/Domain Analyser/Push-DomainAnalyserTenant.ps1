function Push-DomainAnalyserTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants | Where-Object { $_.customerId -eq $Item.customerId }
    $DomainTable = Get-CippTable -tablename 'Domains'

    if ($Tenant.Excluded -eq $true) {
        $Filter = "PartitionKey eq 'TenantDomains' and TenantId eq '{0}'" -f $Exclude.defaultDomainName
        $CleanupRows = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter
        $CleanupCount = ($CleanupRows | Measure-Object).Count
        if ($CleanupCount -gt 0) {
            Write-LogMessage -API 'DomainAnalyser' -tenant $Exclude.defaultDomainName -message "Cleaning up $CleanupCount domain(s) for excluded tenant" -sev Info
            Remove-AzDataTableEntity @DomainTable -Entity $CleanupRows
        }
    } elseif ($Tenant.GraphErrorCount -gt 50) {
        return
    } else {
        try {
            $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains' -tenantid $Tenant.defaultDomainName | Where-Object { ($_.id -notlike '*.microsoftonline.com' -and $_.id -NotLike '*.exclaimer.cloud' -and $_.id -Notlike '*.excl.cloud' -and $_.id -NotLike '*.codetwo.online' -and $_.id -NotLike '*.call2teams.com' -and $_.isVerified) }

            $TenantDomains = foreach ($d in $domains) {
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

            $DomainCount = ($TenantDomains | Measure-Object).Count
            if ($DomainCount -gt 0) {
                Write-Host "$TenantCount tenant Domains"
                try {
                    $TenantDomainObjects = foreach ($Tenant in $TenantDomains) {
                        $TenantDetails = ($Tenant | ConvertTo-Json -Compress).ToString()
                        $Filter = "PartitionKey eq '{0}' and RowKey eq '{1}'" -f $Tenant.Tenant, $Tenant.Domain
                        $OldDomain = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter

                        if ($OldDomain) {
                            Remove-AzDataTableEntity @DomainTable -Entity $OldDomain | Out-Null
                        }

                        $Filter = "PartitionKey eq 'TenantDomains' and RowKey eq '{0}'" -f $Tenant.Domain
                        $Domain = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter

                        if (!$Domain -or $null -eq $Domain.TenantGUID) {
                            $DomainObject = [pscustomobject]@{
                                DomainAnalyser = ''
                                TenantDetails  = $TenantDetails
                                TenantId       = $Tenant.Tenant
                                TenantGUID     = $Tenant.TenantGUID
                                DkimSelectors  = ''
                                MailProviders  = ''
                                RowKey         = $Tenant.Domain
                                PartitionKey   = 'TenantDomains'
                            }

                            if ($OldDomain) {
                                $DomainObject.DkimSelectors = $OldDomain.DkimSelectors
                                $DomainObject.MailProviders = $OldDomain.MailProviders
                            }
                            $Domain = $DomainObject
                        } else {
                            $Domain.TenantDetails = $TenantDetails
                            if ($OldDomain) {
                                $Domain.DkimSelectors = $OldDomain.DkimSelectors
                                $Domain.MailProviders = $OldDomain.MailProviders
                            }
                        }
                        # Return domain object to list
                        $Domain
                    }

                    # Batch insert tenant domains
                    try {
                        Add-CIPPAzDataTableEntity @DomainTable -Entity $TenantDomainObjects -Force
                        $InputObject = [PSCustomObject]@{
                            Batch            = $TenantDomainObjects | Select-Object RowKey, @{n = 'FunctionName'; exp = { 'DomainAnalyserDomain' } }
                            OrchestratorName = "DomainAnalyser_$($Tenant.defaultDomainName)"
                            SkipLog          = $true
                        }
                        Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
                    } catch {
                        Write-LogMessage -API 'DomainAnalyser' -message 'Domain Analyser GetTenantDomains error' -sev info -LogData (Get-CippException -Exception $_)
                    }
                } catch {
                    Write-LogMessage -API 'DomainAnalyser' -message 'GetTenantDomains loop error' -sev 'Error' -LogData (Get-CippException -Exception $_)
                }
            }
        } catch {
            Write-Host (Get-CippException -Exception $_)
            Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.defaultDomainName -message 'DNS Analyser GraphGetRequest' -LogData (Get-CippException -Exception $_) -sev Error
        }
    }
    return $null
}