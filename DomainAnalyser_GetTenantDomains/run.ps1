param($name)

$Tenants = Get-Tenants
$ExcludedTenants = Get-Tenants -SkipList
$DomainTable = Get-CippTable -tablename 'Domains'

$TenantDomains = $Tenants | ForEach-Object -Parallel {
    Import-Module CippCore
    $Tenant = $_
    # Get Domains to Lookup
    try {
        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains' -tenantid $Tenant.defaultDomainName | Where-Object { ($_.id -notlike '*.microsoftonline.com' -and $_.id -NotLike '*.exclaimer.cloud' -and $_.id -Notlike '*.excl.cloud' -and $_.id -NotLike '*.codetwo.online' -and $_.id -NotLike '*.call2teams.com' -and $_.isVerified) }

        foreach ($d in $domains) {
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
    } catch {
        Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.defaultDomainName -message 'DNS Analyser GraphGetRequest' -LogData (Get-CippException -Exception $_) -sev Error
    }
} | Sort-Object -Unique -Property Domain

# Cleanup domains from tenants with errors, skip domains with manually set selectors or mail providers
foreach ($Exclude in $ExcludedTenants) {
    $Filter = "PartitionKey eq 'TenantDomains' and TenantId eq '{0}'" -f $Exclude.defaultDomainName
    $CleanupRows = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter
    $CleanupCount = ($CleanupRows | Measure-Object).Count
    if ($CleanupCount -gt 0) {
        Write-LogMessage -API 'DomainAnalyser' -tenant $Exclude.defaultDomainName -message "Cleaning up $CleanupCount domain(s) for excluded tenant" -sev Info
        Remove-AzDataTableEntity @DomainTable -Entity $CleanupRows
    }
}

$TenantCount = ($TenantDomains | Measure-Object).Count
if ($TenantCount -gt 0) {
    Write-Host "$TenantCount tenant Domains"

    # Process tenant domain results
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

        # Batch insert all tenant domains
        try {
            Add-CIPPAzDataTableEntity @DomainTable -Entity $TenantDomainObjects -Force
        } catch { Write-LogMessage -API 'DomainAnalyser' -message 'Domain Analyser GetTenantDomains error' -sev info -LogData (Get-CippException -Exception $_) }
    } catch { Write-LogMessage -API 'DomainAnalyser' -message 'GetTenantDomains loop error' -sev 'Error' -LogData (Get-CippException -Exception $_) }
}
