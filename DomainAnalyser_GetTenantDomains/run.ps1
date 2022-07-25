param($name)

$Tenants = Get-Tenants
$DomainTable = Get-CippTable -tablename 'Domains'

$TenantErrors = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()
$TenantDomains = $Tenants | ForEach-Object -Parallel {
    Import-Module '.\GraphHelper.psm1'
    $Tenant = $_
    # Get Domains to Lookup
    try {
        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains' -tenantid $Tenant.defaultDomainName | Where-Object { ($_.id -notlike '*.onmicrosoft.com' -and $_.id -notlike '*.microsoftonline.com' -and $_.id -NotLike '*.exclaimer.cloud' -and $_.id -NotLike '*.codetwo.online') }
        foreach ($d in $domains) {
            [PSCustomObject]@{
                Tenant             = $Tenant.defaultDomainName
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
    }
    catch {
        $dict = $using:TenantErrors
        $dict.TryAdd($Tenant.defaultDomainName, $_.Exception.Message) | Out-Null
        Write-LogMessage -API 'DomainAnalyser' -tenant $tenant.defaultDomainName -message "DNS Analyser GraphGetRequest Exception: $($_.Exception.Message)" -sev Error
    }
}

#Write-Host 'Tenant Errors: '
#Write-Host ($TenantErrors | Format-Table | Out-String)

# Cleanup domains from tenants with errors, skip domains with manually set selectors or mail providers
foreach ($Key in $TenantErrors.Keys) {
    Write-LogMessage -API 'DomainAnalyser' -tenant $Key -message 'Removing domains for tenant' -sev Error
    $Filter = "PartitionKey eq 'TenantDomains' and TenantID eq '{0}' and DkimSelectors eq '' and MailProviders eq ''" -f $Key
    $CleanupRows = Get-AzDataTableEntity @DomainTable -Filter $Filter
    if (($CleanupRows | Measure-Object).Count -gt 0) {
        Remove-AzDataTableRow @DomainTable -Entity $CleanupRows
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
            $OldDomain = Get-AzDataTableEntity @DomainTable -Filter $Filter

            if ($OldDomain) {
                Remove-AzDataTableEntity @DomainTable -Entity $OldDomain | Out-Null
            }

            $Filter = "PartitionKey eq 'TenantDomains' and RowKey eq '{0}'" -f $Tenant.Domain
            $Domain = Get-AzDataTableEntity @DomainTable -Filter $Filter

            if (!$Domain) {
                $DomainObject = @{
                    DomainAnalyser = ''
                    TenantDetails  = $TenantDetails
                    TenantId       = $Tenant.Tenant
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
            }
            else {
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
            Add-AzDataTableEntity @DomainTable -Entity $TenantDomainObjects -Force
        }
        catch { Write-LogMessage -API 'DomainAnalyser' -message "Domain Analyser GetTenantDomains Error $($_.Exception.Message)" -sev info }
    }
    catch { Write-LogMessage -API 'DomainAnalyser' -message "GetTenantDomains loop exception: $($_.Exception.Message) line $($_.InvocationInfo.ScriptLineNumber)" }
}