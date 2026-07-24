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
            List           - Site metadata (default hostname, inbound IP, verification id) plus every
                             hostname binding and any App Service Managed Certificate that matches.
            CheckDns       - Live DoH lookup of the two records a custom domain needs (ownership TXT
                             at asuid.<host> and the CNAME/A alias). Powers wizard step 1 + resume.
            AddBinding     - Create the hostname binding (wizard step 2). Azure re-validates ownership.
            AddCertificate - Create an App Service Managed Certificate and enable the SNI SSL binding
                             (wizard step 3). Safe to re-run — reuses an existing cert if present.
            Remove         - Delete a custom hostname binding (and its managed cert, best effort).

        Every action is independently re-runnable so the wizard can resume a half-finished domain or
        retry a failed step without redoing the ones that already succeeded.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $ApiVersion = '2024-11-01'

    # Resolve the ARM coordinates of the App Service running this instance. Mirrors the resolution
    # the Container Management endpoint uses (platform env + managed identity token), so a missing
    # resource group fails loudly rather than guessing.
    function Get-AppServiceSiteInfo {
        $SiteName = $env:WEBSITE_SITE_NAME
        $RGName = Get-CIPPFunctionAppResourceGroup -SiteName $SiteName
        return @{
            Subscription = Get-CIPPAzFunctionAppSubId
            SiteName     = $SiteName
            RGName       = $RGName
        }
    }

    function Get-SiteArmBase {
        param($Site)
        return "https://management.azure.com/subscriptions/$($Site.Subscription)/resourceGroups/$($Site.RGName)/providers/Microsoft.Web/sites/$($Site.SiteName)"
    }

    # Work out which DNS records a given custom hostname needs. Azure accepts either a CNAME (to the
    # app's default hostname) or an A record (to the inbound IP) for the alias itself, plus a TXT
    # ownership record at asuid.<host>. Wildcards verify ownership at the parent domain.
    function Get-DomainRecordPlan {
        param(
            [string]$Hostname,
            [string]$DefaultHostName,
            [string]$InboundIp,
            [string]$VerificationId
        )
        $IsWildcard = $Hostname.StartsWith('*.')
        $BaseHost = $IsWildcard ? $Hostname.Substring(2) : $Hostname
        $Labels = $BaseHost.Split('.')
        # 2-label names (contoso.com) are treated as apex → A record. Everything else is a subdomain
        # → CNAME. This is a heuristic (multi-part TLDs like co.uk can't be detected without a public
        # suffix list); the UI lets the operator pick the other record type, and Azure accepts either.
        $IsApex = -not $IsWildcard -and $Labels.Count -le 2
        $AsuidHost = $IsWildcard ? "asuid.$BaseHost" : "asuid.$Hostname"

        return [pscustomobject]@{
            Hostname          = $Hostname
            IsWildcard        = $IsWildcard
            IsApex            = $IsApex
            RecommendedType   = $IsApex ? 'A' : 'CNAME'
            AsuidHost         = $AsuidHost
            VerificationId    = $VerificationId
            CnameAlias        = $Hostname
            CnameTarget       = $DefaultHostName
            ARecordAlias      = $Hostname
            ARecordTarget     = $InboundIp
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
                $Site = Get-AppServiceSiteInfo
                $ArmBase = Get-SiteArmBase -Site $Site

                $SiteObj = New-CIPPAzRestRequest -Uri "$($ArmBase)?api-version=$ApiVersion" -Method GET
                $DefaultHostName = $SiteObj.properties.defaultHostName
                $InboundIp = $SiteObj.properties.inboundIpAddress
                $VerificationId = $SiteObj.properties.customDomainVerificationId

                $BindingResponse = New-CIPPAzRestRequest -Uri "$($ArmBase)/hostNameBindings?api-version=$ApiVersion" -Method GET

                # Pull managed certs in the RG once so we can attach expiry/thumbprint per domain.
                $Certs = @()
                try {
                    $CertResponse = New-CIPPAzRestRequest -Uri "https://management.azure.com/subscriptions/$($Site.Subscription)/resourceGroups/$($Site.RGName)/providers/Microsoft.Web/certificates?api-version=$ApiVersion" -Method GET
                    $Certs = @($CertResponse.value)
                } catch {
                    Write-Information "Could not list certificates: $($_.Exception.Message)"
                }

                $Domains = foreach ($Binding in $BindingResponse.value) {
                    $HostName = $Binding.name
                    # ARM returns bindings named "<site>/<hostname>"; keep just the hostname.
                    if ($HostName -match '/') { $HostName = ($HostName -split '/')[-1] }
                    $IsDefault = $HostName -like '*.azurewebsites.net'
                    $Cert = $Certs | Where-Object { $_.properties.canonicalName -eq $HostName } | Select-Object -First 1

                    [pscustomobject]@{
                        Hostname       = $HostName
                        IsDefault      = $IsDefault
                        HostNameType   = $Binding.properties.hostNameType
                        SslState       = $Binding.properties.sslState ?? 'Disabled'
                        Thumbprint     = $Binding.properties.thumbprint
                        DnsRecordType  = $Binding.properties.customHostNameDnsRecordType
                        Secured        = ($Binding.properties.sslState -in @('SniEnabled', 'IpBasedEnabled'))
                        CertName       = $Cert.name
                        CertThumbprint = $Cert.properties.thumbprint
                        CertExpiration = $Cert.properties.expirationDate
                        CertIssuer     = $Cert.properties.issuer
                    }
                }

                $Body = @{
                    Results = @{
                        SiteName                   = $Site.SiteName
                        ResourceGroup              = $Site.RGName
                        DefaultHostName            = $DefaultHostName
                        InboundIpAddress           = $InboundIp
                        CustomDomainVerificationId = $VerificationId
                        Domains                    = @($Domains | Sort-Object -Property IsDefault, Hostname)
                    }
                }
            }

            'CheckDns' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if (-not [string]::IsNullOrWhiteSpace($HostName)) { $HostName = ([string]$HostName).Trim().ToLower() }
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }

                # DoH resolver lives in the DNSHealth module; import + initialize it the same way the
                # domain health endpoint does before resolving.
                Import-Module DNSHealth -ErrorAction SilentlyContinue
                Set-DnsResolver -Resolver 'Google' -ErrorAction SilentlyContinue

                $Site = Get-AppServiceSiteInfo
                $ArmBase = Get-SiteArmBase -Site $Site
                $SiteObj = New-CIPPAzRestRequest -Uri "$($ArmBase)?api-version=$ApiVersion" -Method GET
                $Plan = Get-DomainRecordPlan -Hostname $HostName `
                    -DefaultHostName $SiteObj.properties.defaultHostName `
                    -InboundIp $SiteObj.properties.inboundIpAddress `
                    -VerificationId $SiteObj.properties.customDomainVerificationId

                # Ownership: TXT at asuid.<host> must contain the verification id.
                $TxtValues = Resolve-DohRecord -Name $Plan.AsuidHost -Type 'TXT'
                $OwnershipVerified = $TxtValues -contains $Plan.VerificationId

                # Alias: accept a CNAME to the default hostname OR an A record to the inbound IP.
                # Wildcards can't be resolved directly, so ownership alone gates them here — Azure
                # validates the wildcard alias when the binding is created.
                $AliasVerified = $false
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
                        $AliasDetail = "CNAME -> $($Plan.CnameTarget)"
                    } elseif ($AMatch) {
                        $AliasVerified = $true
                        $AliasDetail = "A -> $($Plan.ARecordTarget)"
                    } else {
                        $Found = @($CnameValues + $AValues) -join ', '
                        $AliasDetail = $Found ? "Found: $Found (expected CNAME $($Plan.CnameTarget) or A $($Plan.ARecordTarget))" : 'No CNAME or A record found yet.'
                    }
                }

                $Body = @{
                    Results = @{
                        Hostname          = $HostName
                        RecommendedType   = $Plan.RecommendedType
                        IsWildcard        = $Plan.IsWildcard
                        OwnershipVerified = $OwnershipVerified
                        AliasVerified     = $AliasVerified
                        AllVerified       = ($OwnershipVerified -and $AliasVerified)
                        AliasDetail       = $AliasDetail
                        Records           = @(
                            [pscustomobject]@{
                                Purpose  = 'Ownership'
                                Type     = 'TXT'
                                Host     = $Plan.AsuidHost
                                Value    = $Plan.VerificationId
                                Verified = $OwnershipVerified
                            }
                            [pscustomobject]@{
                                Purpose  = 'Alias'
                                Type     = $Plan.RecommendedType
                                Host     = $Plan.IsApex ? '@' : $HostName
                                Value    = $Plan.IsApex ? $Plan.ARecordTarget : $Plan.CnameTarget
                                Verified = $AliasVerified
                            }
                        )
                    }
                }
            }

            'AddBinding' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if (-not [string]::IsNullOrWhiteSpace($HostName)) { $HostName = ([string]$HostName).Trim().ToLower() }
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }
                if ($HostName -like '*.azurewebsites.net') { throw 'The default *.azurewebsites.net hostname is managed by Azure and cannot be added.' }

                $Site = Get-AppServiceSiteInfo
                $ArmBase = Get-SiteArmBase -Site $Site

                # Azure enforces domain-ownership validation (asuid TXT + alias) during this PUT and
                # returns a descriptive error if the records aren't in place yet.
                $BindingUri = "$($ArmBase)/hostNameBindings/$HostName`?api-version=$ApiVersion"
                $BindingBody = @{
                    properties = @{
                        siteName     = $Site.SiteName
                        hostNameType = 'Verified'
                    }
                }
                New-CIPPAzRestRequest -Uri $BindingUri -Method PUT -Body $BindingBody -ContentType 'application/json' | Out-Null

                Write-LogMessage -API $APIName -headers $Headers -message "Added custom domain binding '$HostName' to $($Site.SiteName)" -sev Info
                $Body = @{ Results = "Custom domain '$HostName' bound to the App Service. You can now enable a managed certificate." }
            }

            'AddCertificate' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if (-not [string]::IsNullOrWhiteSpace($HostName)) { $HostName = ([string]$HostName).Trim().ToLower() }
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }
                if ($HostName -like '*.azurewebsites.net') { throw 'The default hostname is already secured by Azure.' }
                if ($HostName.StartsWith('*.')) { throw 'App Service Managed Certificates do not support wildcard domains. Upload your own certificate in the Azure Portal instead.' }

                $Site = Get-AppServiceSiteInfo
                $ArmBase = Get-SiteArmBase -Site $Site

                $SiteObj = New-CIPPAzRestRequest -Uri "$($ArmBase)?api-version=$ApiVersion" -Method GET
                $Location = $SiteObj.location
                $ServerFarmId = $SiteObj.properties.serverFarmId

                # The binding must already exist — the managed cert is validated against it.
                $Bindings = New-CIPPAzRestRequest -Uri "$($ArmBase)/hostNameBindings?api-version=$ApiVersion" -Method GET
                $ExistingBinding = $Bindings.value | Where-Object { (($_.name -split '/')[-1]) -eq $HostName } | Select-Object -First 1
                if (-not $ExistingBinding) {
                    throw "No hostname binding exists for '$HostName'. Create the domain binding first."
                }

                # Reuse a managed cert for this hostname if one is already issued, otherwise create it.
                $CertName = "$($HostName -replace '[^a-zA-Z0-9-]', '-')-$($Site.SiteName)"
                $CertUri = "https://management.azure.com/subscriptions/$($Site.Subscription)/resourceGroups/$($Site.RGName)/providers/Microsoft.Web/certificates/$CertName`?api-version=$ApiVersion"

                $Thumbprint = $null
                try {
                    $ExistingCert = New-CIPPAzRestRequest -Uri $CertUri -Method GET
                    $Thumbprint = $ExistingCert.properties.thumbprint
                } catch {
                    Write-Information "No existing certificate '$CertName', creating a new managed certificate."
                }

                if (-not $Thumbprint) {
                    $CertBody = @{
                        location   = $Location
                        properties = @{
                            serverFarmId           = $ServerFarmId
                            canonicalName          = $HostName
                            domainValidationMethod = 'cname-delegation'
                        }
                    }
                    # Managed-cert issuance validates the domain during the PUT. If the alias is proxied
                    # (e.g. Cloudflare orange-cloud) validation can fail — the operator should turn the
                    # proxy off until the cert is issued, then re-enable it.
                    $NewCert = New-CIPPAzRestRequest -Uri $CertUri -Method PUT -Body $CertBody -ContentType 'application/json'
                    $Thumbprint = $NewCert.properties.thumbprint

                    # Occasionally the thumbprint isn't populated on the create response; poll briefly.
                    $Attempt = 0
                    while (-not $Thumbprint -and $Attempt -lt 6) {
                        Start-Sleep -Seconds 5
                        $Attempt++
                        try {
                            $PolledCert = New-CIPPAzRestRequest -Uri $CertUri -Method GET
                            $Thumbprint = $PolledCert.properties.thumbprint
                        } catch {
                            Write-Information "Polling certificate '$CertName' (attempt $Attempt): $($_.Exception.Message)"
                        }
                    }
                }

                if (-not $Thumbprint) {
                    throw "The managed certificate for '$HostName' was created but is still provisioning. Re-run this step in a minute to finish the SNI binding."
                }

                # Enable the SNI SSL binding by merging sslState + thumbprint into the existing binding.
                $BindingUri = "$($ArmBase)/hostNameBindings/$HostName`?api-version=$ApiVersion"
                $BindingBody = @{
                    properties = @{
                        siteName     = $Site.SiteName
                        hostNameType = 'Verified'
                        sslState     = 'SniEnabled'
                        thumbprint   = $Thumbprint
                    }
                }
                New-CIPPAzRestRequest -Uri $BindingUri -Method PUT -Body $BindingBody -ContentType 'application/json' | Out-Null

                Write-LogMessage -API $APIName -headers $Headers -message "Provisioned managed certificate and SNI binding for '$HostName'" -sev Info
                $Body = @{ Results = "Managed certificate issued and SNI SSL enabled for '$HostName'. The domain is now secured." }
            }

            'Remove' {
                $HostName = $Request.Body.Hostname ?? $Request.Query.Hostname
                if (-not [string]::IsNullOrWhiteSpace($HostName)) { $HostName = ([string]$HostName).Trim().ToLower() }
                if ([string]::IsNullOrWhiteSpace($HostName)) { throw 'Hostname is required' }
                if ($HostName -like '*.azurewebsites.net') { throw 'The default *.azurewebsites.net hostname cannot be removed.' }

                $Site = Get-AppServiceSiteInfo
                $ArmBase = Get-SiteArmBase -Site $Site

                $BindingUri = "$($ArmBase)/hostNameBindings/$HostName`?api-version=$ApiVersion"
                New-CIPPAzRestRequest -Uri $BindingUri -Method DELETE | Out-Null

                # Best effort: drop the managed cert we created for this hostname so it doesn't linger.
                $CertName = "$($HostName -replace '[^a-zA-Z0-9-]', '-')-$($Site.SiteName)"
                $CertUri = "https://management.azure.com/subscriptions/$($Site.Subscription)/resourceGroups/$($Site.RGName)/providers/Microsoft.Web/certificates/$CertName`?api-version=$ApiVersion"
                try {
                    New-CIPPAzRestRequest -Uri $CertUri -Method DELETE | Out-Null
                } catch {
                    Write-Information "Could not remove certificate '$CertName' (may not exist): $($_.Exception.Message)"
                }

                Write-LogMessage -API $APIName -headers $Headers -message "Removed custom domain '$HostName' from $($Site.SiteName)" -sev Info
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
