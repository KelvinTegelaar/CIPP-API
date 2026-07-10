function New-TeamsRequestV2 {
    <#
    .SYNOPSIS
        Talks to the Teams admin ConfigAPI (api.interfaces.records.teams.microsoft.com)
        directly, instead of the MicrosoftTeams PowerShell module.

    .DESCRIPTION
        The MicrosoftTeams module routes policy-definition writes through the legacy
        /Skype.Policy/tenants/policies surface, which returns 40301 Forbidden under CSP/GDAP
        (for both delegate-with-Teams-Admin and app-only-with-Global-Admin tokens). The Teams
        admin center (ACMS) instead uses /Skype.Policy/configurations/{Type}/configuration/{Identity},
        which authorizes fine with the roles CIPP already has. This helper speaks that surface.

        All HTTP goes through Invoke-CIPPRestMethod (pooled CIPP.CIPPRestClient) so gzip
        responses are decompressed and JSON is deserialized consistently across platforms
        (raw Invoke-RestMethod does NOT decompress gzip in the Linux worker, which yields
        garbage/null objects and unreadable error bodies).

        Operations:
          Get     -> GET  configurations/{Type}/configuration/{Identity}   (single object)
          Get -ListAll -> GET configurations/{Type}                         (all instances, array)
          Set     -> PUT  configurations/{Type}/configuration/{Identity}   (MERGE; only changed props)
          New     -> PUT  configurations/{Type}/configuration/{Identity}   (create named policy) [best-effort]
          Remove  -> DELETE configurations/{Type}/configuration/{Identity} [best-effort]

    .PARAMETER TenantFilter
        Target tenant (GUID or default domain).

    .PARAMETER Type
        ConfigAPI type (e.g. 'TeamsMeetingPolicy'), a cmdlet noun, or a full cmdlet name
        (e.g. 'Set-CsTenantFederationConfiguration'); the verb is stripped and known
        noun->type aliases are applied automatically.

    .PARAMETER Action
        Get (default) | Set | New | Remove.

    .PARAMETER Identity
        Policy instance identity. Default 'Global'. (e.g. 'Tag:Default' or a custom name.)

    .PARAMETER Parameters
        Hashtable of properties to write (Set/New). Only these are sent (merge).

    .PARAMETER ListAll
        Get: return every instance of the type (array) instead of one identity.

    .PARAMETER AsApp
        Use an app-only (client_credentials) token instead of the delegate token.

    .PARAMETER NoRead
        Set: skip the read-for-Key step and PUT only the bare changed props (ACMS-style).
        Faster; safe for flat/Host-authority types and federation. Default is read-modify-write
        (adds the Key envelope when the type carries one) for maximum compatibility.

    .PARAMETER UseServiceDiscovery
        Resolve the per-tenant ConfigApi host + X-MS-Forest via Teams.Tenant/tenants and use
        them (and, for federation/ACS types, the OcsPowershellWebservice target headers).

    .EXAMPLE
        New-TeamsRequestV2 -TenantFilter $t -Type TeamsMeetingPolicy -Action Set -Parameters @{ AllowAnonymousUsersToJoinMeeting = $false }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $TenantFilter,
        [Parameter(Mandatory)] [string] $Type,
        [ValidateSet('Get', 'Set', 'New', 'Remove')] [string] $Action = 'Get',
        [string] $Identity = 'Global',
        [hashtable] $Parameters = @{},
        [switch] $ListAll,
        [switch] $AsApp,
        [switch] $NoRead,
        [switch] $UseServiceDiscovery
    )

    # ---- cmdlet-noun -> ConfigAPI type aliases (noun != type) ----
    $TypeAliases = @{
        'TenantFederationConfiguration' = 'TenantFederationSettings'
    }
    # types backed by the legacy OcsPowershellWebservice (need target-uri headers via discovery)
    $FederationTypes = @('TenantFederationSettings', 'TeamsAcsFederationConfiguration')

    # normalize Type: strip Get-/Set-/New-/Remove-Cs prefix, then alias
    $ConfigType = $Type -replace '^(Get|Set|New|Remove|Grant|Revoke)-Cs', ''
    if ($TypeAliases.ContainsKey($ConfigType)) { $ConfigType = $TypeAliases[$ConfigType] }

    # ---- token ----
    $TokenSplat = @{ tenantid = $TenantFilter; scope = '48ac35b8-9aa8-4d74-927d-1f4a14a0b239/.default' }
    if ($AsApp) { $TokenSplat['AsApp'] = $true }
    $TeamsToken = (Get-GraphToken @TokenSplat).Authorization -replace 'Bearer '

    # ---- endpoint + forest (service discovery optional) ----
    $ApiHost = 'api.interfaces.records.teams.microsoft.com'
    $Forest = $null
    $AdminServiceEndpoint = $null
    $AdminDomain = $null
    if ($UseServiceDiscovery) {
        try {
            $disc = Invoke-CIPPRestMethod -Uri "https://$ApiHost/Teams.Tenant/tenants" -Method GET `
                -Headers @{ Authorization = "Bearer $TeamsToken"; Accept = 'application/json' }
            if ($disc.serviceDiscovery.Endpoints.ConfigApiEndpoint) { $ApiHost = $disc.serviceDiscovery.Endpoints.ConfigApiEndpoint }
            $Forest = $disc.serviceDiscovery.Headers.'X-MS-Forest'
            $AdminServiceEndpoint = $disc.serviceDiscovery.Endpoints.AdminServiceEndpoint
            $AdminDomain = ($disc.verifiedDomains | Where-Object { $_.name -like '*.onmicrosoft.com' -and $_.name -notlike '*.*.onmicrosoft.com' } | Select-Object -First 1).name
        } catch {
            Write-Verbose "Service discovery failed, using defaults: $($_.Exception.Message)"
        }
    }
    $Base = "https://$ApiHost/Skype.Policy/configurations/$ConfigType"

    # ---- headers ----
    $Headers = @{
        Authorization         = "Bearer $TeamsToken"
        Accept                = 'application/json'
        'x-authz-scope'       = 'tenant'
        'x-ms-correlation-id' = (New-Guid).Guid
    }
    if ($Forest) { $Headers['x-ms-forest'] = $Forest }
    if ($ConfigType -in $FederationTypes -and $AdminServiceEndpoint) {
        $Headers['x-ms-target-uri'] = "https://$AdminServiceEndpoint/OcsPowershellWebservice"
        $Headers['x-ms-tenant-id'] = $TenantFilter
    }
    $Query = if ($ConfigType -in $FederationTypes -and $AdminDomain) { "?adminDomain=$AdminDomain" } else { '' }

    switch ($Action) {

        'Get' {
            $Uri = if ($ListAll) { "$Base$Query" } else { "$Base/configuration/$Identity$Query" }
            return Invoke-CIPPRestMethod -Uri $Uri -Method GET -Headers $Headers
        }

        'Set' {
            $Uri = "$Base/configuration/$Identity$Query"

            # build body of only the changed props (skip control keys)
            $Body = [ordered]@{}
            foreach ($k in $Parameters.Keys) {
                if ($k -in @('Identity', 'ErrorAction', 'Confirm', 'WhatIf', 'Verbose', 'Debug')) { continue }
                $Body[$k] = $Parameters[$k]
            }

            if (-not $NoRead) {
                # read-modify-write: include the Key envelope when the type carries one (max compat)
                try {
                    $Current = Invoke-CIPPRestMethod -Uri $Uri -Method GET -Headers $Headers
                    if ($Current -and ($Current.PSObject.Properties.Name -contains 'Key')) {
                        $Merged = [ordered]@{ Identity = $Identity; Key = $Current.Key }
                        foreach ($k in $Body.Keys) { $Merged[$k] = $Body[$k] }
                        $Body = $Merged
                    }
                } catch {
                    Write-Verbose "Pre-read failed ($($_.Exception.Message)); sending bare props."
                }
            }

            $Json = $Body | ConvertTo-Json -Depth 25 -Compress
            $StatusCode = $null
            $RespBody = Invoke-CIPPRestMethod -Uri $Uri -Method PUT -Body $Json -ContentType 'application/json' `
                -Headers $Headers -SkipHttpErrorCheck -StatusCodeVariable StatusCode
            if ([int]$StatusCode -ge 400) {
                $Detail = if ($RespBody -is [string]) { $RespBody } elseif ($null -ne $RespBody) { $RespBody | ConvertTo-Json -Compress -Depth 10 } else { '' }
                throw "Teams ConfigApi Set $ConfigType/$Identity failed: $StatusCode $Detail"
            }
            return [pscustomobject]@{ Type = $ConfigType; Identity = $Identity; StatusCode = [int]$StatusCode }
        }

        'New' {
            # best-effort: create a named policy by PUTting the props at a new identity
            $Uri = "$Base/configuration/$Identity$Query"
            $Body = [ordered]@{ Identity = $Identity }
            foreach ($k in $Parameters.Keys) {
                if ($k -in @('Identity', 'ErrorAction', 'Confirm', 'WhatIf', 'Verbose', 'Debug')) { continue }
                $Body[$k] = $Parameters[$k]
            }
            $Json = $Body | ConvertTo-Json -Depth 25 -Compress
            $StatusCode = $null
            $RespBody = Invoke-CIPPRestMethod -Uri $Uri -Method PUT -Body $Json -ContentType 'application/json' `
                -Headers $Headers -SkipHttpErrorCheck -StatusCodeVariable StatusCode
            if ([int]$StatusCode -ge 400) {
                $Detail = if ($RespBody -is [string]) { $RespBody } elseif ($null -ne $RespBody) { $RespBody | ConvertTo-Json -Compress -Depth 10 } else { '' }
                throw "Teams ConfigApi New $ConfigType/$Identity failed: $StatusCode $Detail"
            }
            return [pscustomobject]@{ Type = $ConfigType; Identity = $Identity; StatusCode = [int]$StatusCode }
        }

        'Remove' {
            $Uri = "$Base/configuration/$Identity$Query"
            $StatusCode = $null
            $RespBody = Invoke-CIPPRestMethod -Uri $Uri -Method DELETE -Headers $Headers -SkipHttpErrorCheck -StatusCodeVariable StatusCode
            if ([int]$StatusCode -ge 400) {
                $Detail = if ($RespBody -is [string]) { $RespBody } elseif ($null -ne $RespBody) { $RespBody | ConvertTo-Json -Compress -Depth 10 } else { '' }
                throw "Teams ConfigApi Remove $ConfigType/$Identity failed: $StatusCode $Detail"
            }
            return [pscustomobject]@{ Type = $ConfigType; Identity = $Identity; StatusCode = [int]$StatusCode }
        }
    }
}
