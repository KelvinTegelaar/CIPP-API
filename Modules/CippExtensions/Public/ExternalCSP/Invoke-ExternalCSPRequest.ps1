function Invoke-ExternalCSPRequest {
    <#
    .FUNCTIONALITY
        Internal
    .DESCRIPTION
        Sends one External CSP contract call to the vendor URL configured for that action.
        Reads (Catalog, Subscriptions) are GETs with tenantId in the query; writes are JSON POSTs with tenantId in the body.
        Test is a GET with no tenant, used to prove the URL and credentials.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Test', 'Catalog', 'Subscriptions', 'Order', 'Quantity', 'Cancel')]
        [string]$Action,
        [string]$TenantFilter,
        [hashtable]$Body = @{},
        $Headers
    )

    # Every call to the provider goes through here, so this is the one place the feature flag is enforced.
    if ((Get-CIPPFeatureFlag -Id 'ExternalCSP').Enabled -ne $true) {
        throw 'The External CSP integration is turned off. Enable it in Application Settings > Features.'
    }

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).ExternalCSP
    $IsWrite = $Action -in @('Order', 'Quantity', 'Cancel')

    # Headers are only present for interactive and API-client callers; scheduled tasks run ungated, as with Sherweb.
    $AllowedRoles = $Config.AllowedCustomRoles.value
    if ($IsWrite -and $Headers -and $AllowedRoles) {
        if ($Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Headers.'x-ms-client-principal-name' -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            $Client = Get-CippApiClient -AppId $Headers.'x-ms-client-principal-name'
            $CallerRoles = if ($Client.Role) { @($Client.Role) } else { @('cipp-api') }
        } elseif ($Headers.'x-ms-client-principal') {
            $CallerRoles = @(Get-CIPPAccessRole -Headers $Headers)
        } else {
            $CallerRoles = @()
        }
        if (-not ($CallerRoles | Where-Object { $AllowedRoles -contains $_ })) {
            throw 'This caller is not allowed to modify CSP subscriptions.'
        }
    }

    $Url = $Config."$($Action)Url"
    if ($Url -notmatch '^https://') {
        throw "The External CSP $Action URL is not configured, or is not an https:// URL."
    }

    if ($Action -ne 'Test') {
        $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
        if (-not $TenantId) {
            throw "Could not resolve a tenant ID for '$TenantFilter'."
        }
    }

    # The extension store holds one secret, so it is the bearer token, basic password, API key value
    # or custom headers JSON depending on the type.
    $Secret = ([string](Get-ExtensionAPIKey -Extension 'ExternalCSP')).Trim()
    if (-not $Secret) {
        throw 'The External CSP authentication secret is not set.'
    }
    # Secrets are often pasted with the scheme or header name still attached; send each only once.
    $AuthHeader = switch ([string]$Config.AuthType.value) {
        'Bearer' {
            @{ Authorization = 'Bearer {0}' -f ($Secret -replace '^(Authorization\s*:\s*)?(Bearer\s+)?', '') }
        }
        'Basic' {
            $Username = ([string]$Config.AuthUsername).Trim()
            $Pasted = $Secret -replace '^Authorization\s*:\s*', ''
            if ($Pasted -match '^Basic\s+\S+$') {
                # Already an encoded Basic credential.
                @{ Authorization = $Pasted -replace '^Basic\s+', 'Basic ' }
            } elseif ($Username) {
                $BasicBytes = [System.Text.Encoding]::UTF8.GetBytes("${Username}:$Secret")
                @{ Authorization = 'Basic {0}' -f [System.Convert]::ToBase64String($BasicBytes) }
            } elseif ($Secret -match '^[^:]+:.') {
                # No username entered, but the secret is already in username:password form.
                @{ Authorization = 'Basic {0}' -f [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Secret)) }
            } else {
                throw 'External CSP basic authentication needs a username.'
            }
        }
        'CustomHeaders' {
            # Never fall back to an unauthenticated call: this endpoint buys licences.
            $Parsed = try { $Secret | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { $null }
            $CustomHeaders = @{}
            if ($Parsed -is [System.Collections.IDictionary]) {
                foreach ($Name in $Parsed.Keys) {
                    $CleanName = ([string]$Name).Trim().TrimEnd(':').Trim()
                    if ($CleanName -and $null -ne $Parsed[$Name]) {
                        $CustomHeaders[$CleanName] = ([string]$Parsed[$Name]).Trim()
                    }
                }
            }
            if ($CustomHeaders.Count -eq 0) {
                throw 'The External CSP custom headers must be a JSON object, for example {"x-api-key":"value"}.'
            }
            $CustomHeaders
        }
        default {
            $HeaderName = ([string]$Config.AuthHeaderName).Trim().TrimEnd(':').Trim()
            if (-not $HeaderName) { $HeaderName = 'x-api-key' }
            # Drop a pasted "x-api-key: " prefix so the header value is the key alone.
            @{ $HeaderName = $Secret -replace "^$([regex]::Escape($HeaderName))\s*:\s*", '' }
        }
    }
    try {
        if ($IsWrite) {
            $Body.tenantId = $TenantId
            $Response = Invoke-RestMethod -Uri $Url -Method POST -Headers $AuthHeader -Body (ConvertTo-Json -Depth 10 -InputObject $Body) -ContentType 'application/json'
        } elseif ($Action -eq 'Test') {
            $Response = Invoke-RestMethod -Uri $Url -Method GET -Headers $AuthHeader
        } else {
            $Separator = if ($Url -match '\?') { '&' } else { '?' }
            $Response = Invoke-RestMethod -Uri "$Url${Separator}tenantId=$TenantId" -Method GET -Headers $AuthHeader
        }
    } catch {
        # The contract lets the vendor explain a refusal as { "message": "..." }.
        $VendorMessage = try { ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop).message } catch { $null }
        if ($VendorMessage) {
            throw "The CSP provider rejected the $Action request: $VendorMessage"
        }
        $Status = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        if ($Status -ge 500) {
            throw "The CSP provider could not process the $Action request (HTTP $Status) and gave no reason. Check the request in the provider's own portal or logs."
        }
        throw "The CSP provider rejected the $Action request: $($_.Exception.Message)"
    }
    # Platforms that cannot set an HTTP status (low-code workflow tools) refuse with a 2xx { "success": false, "message": "..." }.
    if ($Response -is [System.Management.Automation.PSCustomObject] -and $Response.PSObject.Properties.Name -contains 'success' -and "$($Response.success)" -eq 'False') {
        $Reason = if ($Response.message) { $Response.message } else { 'no reason was given' }
        throw "The CSP provider rejected the $Action request: $Reason"
    }
    return $Response
}
