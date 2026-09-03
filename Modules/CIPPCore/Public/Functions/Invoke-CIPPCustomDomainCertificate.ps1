function Invoke-CIPPCustomDomainCertificate {
    <#
    .SYNOPSIS
        Issues an App Service Managed Certificate for a bound custom domain and enables its SNI binding.
    .DESCRIPTION
        Managed certificate issuance is asynchronous and regularly outlives a single request, so this
        runs once inline from the Custom Domains wizard and then, while the certificate is still
        pending or the attempt failed, reschedules itself as a hidden one-off task 15 minutes out.
        It stops on success, when the hostname is no longer bound (the domain was removed in the
        meantime), and after MaxAttempts - it never reschedules past that.

        Every run is idempotent: an existing certificate for the hostname is reused rather than
        re-created, and a certificate whose issuance is already in flight (ARM answers 409) is
        polled for instead of failing.
    .PARAMETER Hostname
        The custom domain. Its hostname binding must already exist on the App Service.
    .PARAMETER Attempt
        Current attempt number. Managed by the reschedule - callers should leave it at the default.
    .PARAMETER MaxAttempts
        Total attempts before giving up. Defaults to 4: the inline run plus three retries.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Invoke-CIPPCustomDomainCertificate -Hostname 'portal.contoso.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$')]
        [string]$Hostname,

        [int]$Attempt = 1,

        [int]$MaxAttempts = 4
    )

    $AppService = Get-CIPPAppServiceSite
    $Api = $AppService.ApiVersion

    if ($AppService.Site.properties.hostNames -notcontains $Hostname) {
        $Message = "No hostname binding exists for '$Hostname' - the domain was removed or never added. Nothing to do."
        Write-LogMessage -API 'CustomDomains' -message $Message -sev Warn
        return $Message
    }

    $SslState = ($AppService.Site.properties.hostNameSslStates | Where-Object { $_.name -eq $Hostname } | Select-Object -First 1).sslState
    if ($SslState -in @('SniEnabled', 'IpBasedEnabled')) {
        $Message = "'$Hostname' is already secured ($SslState)."
        Write-LogMessage -API 'CustomDomains' -message $Message -sev Info
        return $Message
    }

    $Outcome = $null
    try {
        # Reuse whatever certificate already covers this hostname, whatever it is named: Azure keys
        # uniqueness on canonicalName per plan, so a second PUT for the same hostname is rejected.
        $Cert = $AppService.Certificates | Where-Object { $_.properties.canonicalName -eq $Hostname } | Select-Object -First 1
        if (-not $Cert) {
            # Same name the Azure portal uses, so a portal-created certificate is the same resource.
            $CertUri = "$($AppService.CertBase)/$Hostname-$($AppService.SiteName)?api-version=$Api"
            $CertBody = @{
                location   = $AppService.Site.location
                properties = @{
                    canonicalName = $Hostname
                    serverFarmId  = $AppService.Site.properties.serverFarmId
                }
            }
            try {
                $Cert = New-CIPPAzRestRequest -Uri $CertUri -Method PUT -Body $CertBody -ErrorAction Stop
            } catch {
                # An issuance already in flight holds the hostname's slot before the resource exists,
                # so the list above finds nothing and the PUT answers 409. Poll for it instead.
                if ($_.Exception.Message -notmatch 'Conflict|duplicate') { throw }
                Write-Information "Certificate creation for $Hostname returned 409 - an issuance is already pending, polling for it instead"
            }
        }

        # Brief poll (6 x 10 s): issuance usually takes a minute or two; anything longer is what
        # the retry is for.
        $Thumbprint = $Cert.properties.thumbprint
        for ($Poll = 0; -not $Thumbprint -and $Poll -lt 6; $Poll++) {
            Start-Sleep -Seconds 10
            $Issued = try {
                (New-CIPPAzRestRequest -Uri "$($AppService.CertBase)?api-version=$Api" -Method GET -ErrorAction Stop).value |
                    Where-Object { $_.properties.canonicalName -eq $Hostname } | Select-Object -First 1
            } catch { $null }
            $Thumbprint = $Issued.properties.thumbprint
        }

        if ($Thumbprint) {
            $BindBody = @{ properties = @{ sslState = 'SniEnabled'; thumbprint = $Thumbprint; toUpdate = $true } }
            $null = New-CIPPAzRestRequest -Uri "$($AppService.ArmBase)/hostNameBindings/$Hostname`?api-version=$Api" -Method PUT -Body $BindBody -ErrorAction Stop
            $Message = "Managed certificate issued and SNI SSL enabled for '$Hostname'. The domain is now secured."
            Write-LogMessage -API 'CustomDomains' -message $Message -sev Info
            return $Message
        }
        $Outcome = "The managed certificate for '$Hostname' is still being issued"
    } catch {
        $Outcome = "Certificate provisioning for '$Hostname' failed: $((Get-CippException -Exception $_).NormalizedError)"
    }

    if ($Attempt -ge $MaxAttempts) {
        $Message = "$Outcome. Giving up after $MaxAttempts attempts - check that the domain's DNS record points directly at this App Service (not through a proxy or CDN), then run 'Provision certificate' on the domain again."
        Write-LogMessage -API 'CustomDomains' -message $Message -sev Error
        return $Message
    }

    $ScheduleResult = Add-CIPPScheduledTask -Hidden $true -Task ([pscustomobject]@{
            TenantFilter  = $env:TenantID
            Name          = "Custom domain certificate: $Hostname"
            Command       = @{ value = 'Invoke-CIPPCustomDomainCertificate' }
            Parameters    = [pscustomobject]@{
                Hostname    = $Hostname
                Attempt     = $Attempt + 1
                MaxAttempts = $MaxAttempts
            }
            ScheduledTime = [int64](([datetime]::UtcNow.AddMinutes(15)) - (Get-Date '1/1/1970')).TotalSeconds
            Recurrence    = '0'
            PostExecution = @{}
            Reference     = "CustomDomainCert-$Hostname"
        })
    if ("$ScheduleResult" -match '^Error') {
        $Message = "$Outcome, and the retry could not be scheduled: $ScheduleResult"
        Write-LogMessage -API 'CustomDomains' -message $Message -sev Error
        return $Message
    }

    $Message = "$Outcome (attempt $Attempt of $MaxAttempts). CIPP will try again in 15 minutes."
    Write-LogMessage -API 'CustomDomains' -message $Message -sev Info
    return $Message
}
