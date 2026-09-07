function Invoke-ExecAppServiceDomains {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    .SYNOPSIS
        Manage custom domains (hostname bindings) and managed certificates on the CIPP App Service.
    .DESCRIPTION
        Drives the super-admin "Custom Domains" page. All actions operate on the App Service that
        hosts this CIPP instance (Microsoft.Web/sites/$env:WEBSITE_SITE_NAME) using the managed
        identity via New-CIPPAzRestRequest — the same resource and auth path the Container
        Management page uses.

        Actions (passed as Query.Action or Body.Action):
            List           - Site metadata (default hostname, inbound IP) plus every hostname
                             binding, any App Service Managed Certificate that matches, and the
                             state of a certificate job still running in the background.
            CheckDns       - Live DoH lookup of the alias record a custom domain needs. CIPP no
                             longer uses domain-verification TXT records, so a leftover
                             asuid.<host> record is detected and flagged for removal rather than
                             requested. Powers wizard step 1 + resume.
            AddBinding     - Create the hostname binding (wizard step 2). Azure validates ownership
                             through the alias record.
            AddCertificate - Issue an App Service Managed Certificate and enable the SNI SSL binding
                             (wizard step 3) via Invoke-CIPPCustomDomainCertificate. Issuance that
                             outlives the request carries on as a hidden scheduled task that retries
                             every 15 minutes, a few times, then stops.
            Remove         - Delete a custom hostname binding (and its managed cert, best effort).

        Every action is independently re-runnable so the wizard can resume a half-finished domain or
        retry a failed step without redoing the ones that already succeeded.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Query.Action ?? $Request.Body.Action

    # Trim/lowercase the requested hostname and reject anything that is not a DNS name - it goes
    # into ARM URIs and table filters verbatim.
    function Get-CleanHostname {
        param([string]$Value)
        $Clean = ([string]$Value).Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($Clean)) { throw 'Hostname is required' }
        if ($Clean -notmatch '^(\*\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$') { throw "'$Clean' is not a valid hostname" }
        return $Clean
    }

    # Work out which DNS record a given custom hostname needs. Azure accepts either a CNAME (to the
    # app's default hostname) or an A record (to the inbound IP) for the alias. That alias is the
    # only record CIPP asks for — LegacyAsuidHost is carried along purely so CheckDns can look for a
    # leftover asuid.<host> TXT record from an older setup and tell the operator to remove it.
    function Get-DomainRecordPlan {
        param(
            [string]$Hostname,
            [string]$DefaultHostName,
            [string]$InboundIp
        )
        $IsWildcard = $Hostname.StartsWith('*.')
        $BaseHost = $IsWildcard ? $Hostname.Substring(2) : $Hostname
        $Labels = $BaseHost.Split('.')
        # 2-label names (contoso.com) are treated as apex → A record. Everything else is a subdomain
        # → CNAME. This is a heuristic (multi-part TLDs like co.uk can't be detected without a public
        # suffix list); CheckDns reports which record actually resolved and AddBinding honours that.
        $IsApex = -not $IsWildcard -and $Labels.Count -le 2

        return [pscustomobject]@{
            Hostname        = $Hostname
            IsWildcard      = $IsWildcard
            IsApex          = $IsApex
            RecommendedType = $IsApex ? 'A' : 'CNAME'
            LegacyAsuidHost = $IsWildcard ? "asuid.$BaseHost" : "asuid.$Hostname"
            CnameAlias      = $Hostname
            CnameTarget     = $DefaultHostName
            ARecordAlias    = $Hostname
            ARecordTarget   = $InboundIp
        }
    }

    # DoH lookup that never throws — returns the trimmed data strings for a record type, or @().
    function Resolve-DohRecord {
        param([string]$Name, [string]$Type)
        try {
            $Result = Resolve-DnsHttpsQuery -Domain $Name -RecordType $Type -ErrorAction Stop
            if ($Result.Answer) {
                return @($Result.Answer | ForEach-Object { ($_.data -replace '^"' -replace '"$').Trim().TrimEnd('.') })
            }
        } catch {
            Write-Information "DoH lookup failed for $Type $Name : $($_.Exception.Message)"
        }
        return @()
    }

    try {
        switch ($Action) {
            'List' {
                $AppService = Get-CIPPAppServiceSite
                $Api = $AppService.ApiVersion
                $BindingResponse = New-CIPPAzRestRequest -Uri "$($AppService.ArmBase)/hostNameBindings?api-version=$Api" -Method GET -ErrorAction Stop
                $TaskTable = Get-CIPPTable -TableName 'ScheduledTasks'

                $Domains = foreach ($Binding in $BindingResponse.value) {
                    # ARM returns bindings named "<site>/<hostname>"; keep just the hostname.
                    $HostName = ($Binding.name -split '/')[-1]
                    $IsDefault = $HostName -like '*.azurewebsites.net'
                    $Secured = $Binding.properties.sslState -in @('SniEnabled', 'IpBasedEnabled')
                    $Cert = $AppService.Certificates | Where-Object { $_.properties.canonicalName -eq $HostName } | Select-Object -First 1

                    # A certificate still being issued in the background is a chain of hidden retry
                    # tasks: the planned one says which attempt is next, the last finished one why.
                    $Active = $null
                    $Finished = $null
                    if (-not $IsDefault -and -not $Secured) {
                        $Jobs = @(Get-CIPPAzDataTableEntity @TaskTable -Filter "PartitionKey eq 'ScheduledTask' and Reference eq 'CustomDomainCert-$HostName'")
                        $Active = $Jobs | Where-Object { $_.TaskState -in @('Planned', 'Pending', 'Running') } | Select-Object -First 1
                        $Finished = $Jobs | Where-Object { $_.TaskState -in @('Completed', 'Failed') } | Sort-Object -Property Timestamp -Descending | Select-Object -First 1
                    }
                    $JobParams = try { ($Active ?? $Finished).Parameters | ConvertFrom-Json } catch { $null }
                    $LastResult = try { ($Finished.Results | ConvertFrom-Json).Results } catch { [string]$Finished.Results }

                    [pscustomobject]@{
                        Hostname           = $HostName
                        IsDefault          = $IsDefault
                        HostNameType       = $Binding.properties.hostNameType
                        SslState           = $Binding.properties.sslState ?? 'Disabled'
                        Thumbprint         = $Binding.properties.thumbprint
                        DnsRecordType      = $Binding.properties.customHostNameDnsRecordType
                        Secured            = $Secured
                        CertName           = $Cert.name
                        CertThumbprint     = $Cert.properties.thumbprint
                        CertExpiration     = $Cert.properties.expirationDate
                        CertIssuer         = $Cert.properties.issuer
                        CertJobActive      = [bool]$Active
                        CertJobAttempt     = $JobParams ? [int]$JobParams.Attempt : $null
                        CertJobMaxAttempts = $JobParams ? [int]$JobParams.MaxAttempts : $null
                        CertJobNextRun     = $Active ? [DateTimeOffset]::FromUnixTimeSeconds([int64]$Active.ScheduledTime).UtcDateTime.ToString('o') : $null
                        CertJobResult      = $LastResult
                    }
                }

                $Body = @{
                    Results = @{
                        SiteName              = $AppService.SiteName
                        ResourceGroup         = $AppService.ResourceGroup
                        DefaultHostName       = $AppService.Site.properties.defaultHostName
                        InboundIpAddress      = $AppService.Site.properties.inboundIpAddress
                        # The App Service's own Custom domains blade - the fallback the wizard offers when Azure rejects a binding.
                        AzurePortalDomainsUrl = "https://portal.azure.com/#@/resource/subscriptions/$($AppService.SubscriptionId)/resourceGroups/$($AppService.ResourceGroup)/providers/Microsoft.Web/sites/$($AppService.SiteName)/customDomains"
                        Domains               = @($Domains | Sort-Object -Property IsDefault, Hostname)
                    }
                }
            }

            'CheckDns' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }
                $HostName = Get-CleanHostname $HostName

                # DoH resolver lives in the DNSHealth module; import + initialize it the same way the
                # domain health endpoint does before resolving.
                Import-Module DNSHealth -ErrorAction SilentlyContinue
                Set-DnsResolver -Resolver 'Google' -ErrorAction SilentlyContinue

                $AppService = Get-CIPPAppServiceSite
                $Plan = Get-DomainRecordPlan -Hostname $HostName `
                    -DefaultHostName $AppService.Site.properties.defaultHostName `
                    -InboundIp $AppService.Site.properties.inboundIpAddress

                # CIPP no longer asks for a domain-verification TXT record at asuid.<host>, but an
                # old one left behind by a previous setup is actively harmful: Azure hard-fails the
                # binding when the asuid value doesn't match this App Service, even if the alias
                # record is correct. Detect any leftover record so the wizard can flag it.
                $LegacyAsuidValues = Resolve-DohRecord -Name $Plan.LegacyAsuidHost -Type 'TXT'
                $LegacyAsuid = $LegacyAsuidValues.Count -gt 0

                # Alias: accept a CNAME to the default hostname OR an A record to the inbound IP.
                # Wildcards can't be resolved directly, so they pass this check unconditionally —
                # Azure validates the wildcard alias when the binding is created.
                $AliasVerified = $false
                $AliasType = $null
                $AliasDetail = $null
                if ($Plan.IsWildcard) {
                    $AliasVerified = $true
                    $AliasDetail = 'Wildcard alias is validated by Azure when the binding is created.'
                } else {
                    $CnameValues = Resolve-DohRecord -Name $HostName -Type 'CNAME'
                    $AValues = Resolve-DohRecord -Name $HostName -Type 'A'
                    $CnameMatch = $CnameValues | Where-Object { $_ -eq ($Plan.CnameTarget.TrimEnd('.')) }
                    $AMatch = $AValues | Where-Object { $_ -eq $Plan.ARecordTarget }
                    if ($CnameMatch) {
                        $AliasVerified = $true
                        $AliasType = 'CNAME'
                        $AliasDetail = "CNAME -> $($Plan.CnameTarget)"
                    } elseif ($AMatch) {
                        $AliasVerified = $true
                        $AliasType = 'A'
                        $AliasDetail = "A -> $($Plan.ARecordTarget)"
                    } else {
                        $Found = @($CnameValues + $AValues) -join ', '
                        $AliasDetail = $Found ? "Found: $Found (expected CNAME $($Plan.CnameTarget) or A $($Plan.ARecordTarget))" : 'No CNAME or A record found yet.'
                    }
                }

                $Records = @(
                    [pscustomobject]@{
                        Purpose  = 'Alias'
                        Type     = $Plan.RecommendedType
                        Host     = $Plan.IsApex ? '@' : $HostName
                        Value    = $Plan.IsApex ? $Plan.ARecordTarget : $Plan.CnameTarget
                        Verified = $AliasVerified
                    }
                )

                $Body = @{
                    Results = @{
                        Hostname        = $HostName
                        RecommendedType = $Plan.RecommendedType
                        IsWildcard      = $Plan.IsWildcard
                        LegacyAsuid     = $LegacyAsuid
                        LegacyAsuidHost = $Plan.LegacyAsuidHost
                        AliasVerified   = $AliasVerified
                        AliasType       = $AliasType
                        CanProceed      = [bool]$AliasVerified
                        AliasDetail     = $AliasDetail
                        Records         = @($Records)
                    }
                }
            }

            'AddBinding' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }
                $HostName = Get-CleanHostname $HostName
                if ($HostName -like '*.azurewebsites.net') { throw 'The default *.azurewebsites.net hostname is managed by Azure and cannot be added.' }

                $AppService = Get-CIPPAppServiceSite
                $Plan = Get-DomainRecordPlan -Hostname $HostName `
                    -DefaultHostName $AppService.Site.properties.defaultHostName `
                    -InboundIp $AppService.Site.properties.inboundIpAddress

                # Which alias record Azure should validate against: the one CheckDns saw resolve (A or CNAME), else the recommended type for this hostname shape.
                $DnsRecordType = switch ([string]$Request.Body.DnsRecordType) {
                    'A' { 'A' }
                    'CNAME' { 'CName' }
                    default { $Plan.IsApex ? 'A' : 'CName' }
                }

                # Azure validates ownership during this PUT through the alias record - but only when
                # customHostNameDnsRecordType says which one to check. Without it ARM skips the
                # CNAME/A check and demands an asuid TXT record instead, so a correct CNAME still
                # fails with "A TXT record pointing from asuid.<host> ... was not found".
                $BindingUri = "$($AppService.ArmBase)/hostNameBindings/$HostName`?api-version=$($AppService.ApiVersion)"
                $BindingBody = @{ properties = @{ customHostNameDnsRecordType = $DnsRecordType } }
                try {
                    $null = New-CIPPAzRestRequest -Uri $BindingUri -Method PUT -Body $BindingBody -ErrorAction Stop
                } catch {
                    # A leftover asuid TXT record from an older setup hard-fails validation when its
                    # value doesn't match this App Service — even if the alias is correct.
                    $BindingError = $_.Exception.Message
                    if ($BindingError -match 'TXT record|asuid|CanonicalName') {
                        throw "$BindingError — If a TXT record named '$($Plan.LegacyAsuidHost)' exists from a previous setup, remove it: CIPP no longer uses domain-verification TXT records, and a leftover one blocks validation even when the CNAME/A alias is correct."
                    }
                    throw
                }

                Write-LogMessage -API $APIName -headers $Headers -message "Added custom domain binding '$HostName' ($DnsRecordType) to $($AppService.SiteName)" -sev Info
                $Body = @{ Results = "Custom domain '$HostName' bound to the App Service. You can now enable a managed certificate." }
            }

            'AddCertificate' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }
                $HostName = Get-CleanHostname $HostName
                if ($HostName -like '*.azurewebsites.net') { throw 'The default hostname is already secured by Azure.' }
                if ($HostName.StartsWith('*.')) { throw 'App Service Managed Certificates do not support wildcard domains. Upload your own certificate in the Azure Portal instead.' }

                # First attempt runs inline; a certificate that is not issued by the time it returns
                # is followed up by hidden scheduled retries (see Invoke-CIPPCustomDomainCertificate).
                $Message = Invoke-CIPPCustomDomainCertificate -Hostname $HostName
                $AppService = Get-CIPPAppServiceSite
                $SslState = ($AppService.Site.properties.hostNameSslStates | Where-Object { $_.name -eq $HostName } | Select-Object -First 1).sslState

                Write-LogMessage -API $APIName -headers $Headers -message $Message -sev Info
                $Body = @{
                    Results = $Message
                    Secured = $SslState -in @('SniEnabled', 'IpBasedEnabled')
                }
            }

            'Remove' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }
                $HostName = Get-CleanHostname $HostName
                if ($HostName -like '*.azurewebsites.net') { throw 'The default *.azurewebsites.net hostname cannot be removed.' }

                $AppService = Get-CIPPAppServiceSite
                $Api = $AppService.ApiVersion
                $null = New-CIPPAzRestRequest -Uri "$($AppService.ArmBase)/hostNameBindings/$HostName`?api-version=$Api" -Method DELETE -ErrorAction Stop

                # Best effort: drop the managed certificate(s) for this hostname so they don't linger and
                # keep holding the one-certificate-per-hostname slot on the plan.
                foreach ($Cert in @($AppService.Certificates | Where-Object { $_.properties.canonicalName -eq $HostName })) {
                    try {
                        $null = New-CIPPAzRestRequest -Uri "https://management.azure.com$($Cert.id)?api-version=$Api" -Method DELETE -ErrorAction Stop
                    } catch {
                        Write-Information "Could not remove certificate '$($Cert.name)': $($_.Exception.Message)"
                    }
                }

                Write-LogMessage -API $APIName -headers $Headers -message "Removed custom domain '$HostName' from $($AppService.SiteName)" -sev Info
                $Body = @{ Results = "Custom domain '$HostName' removed from the App Service." }
            }

            default {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Unknown action: $Action. Valid actions: List, CheckDns, AddBinding, AddCertificate, Remove" }
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -headers $Headers -message "AppServiceDomains '$Action' failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = ($Action -eq 'List') ? [HttpStatusCode]::InternalServerError : [HttpStatusCode]::BadRequest
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
