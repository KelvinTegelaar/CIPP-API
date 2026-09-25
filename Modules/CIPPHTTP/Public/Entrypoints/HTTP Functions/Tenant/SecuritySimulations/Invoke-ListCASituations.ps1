function Invoke-ListCASituations {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.SecuritySimulations.Read
    .DESCRIPTION
        Evaluates every predefined sign-in situation (admin, user and guest personas under unmanaged
        devices, foreign locations, legacy clients, device-code flow, risk levels and more) live against the
        tenant's Conditional Access through the What If API, and names the control missing wherever a
        sign-in gets through. Optional adminUserId, userUserId and guestUserId pick the accounts to sign
        in as; country picks where the foreign-country sign-ins come from.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $TenantFilter = $Request.Query.tenantFilter
        if (-not $TenantFilter -or $TenantFilter -in @('AllTenants', 'allTenants')) { throw 'Select a single tenant to evaluate the sign-in situations.' }

        $Overrides = @{}
        foreach ($Pair in @(@{ persona = 'admin'; query = 'adminUserId' }, @{ persona = 'user'; query = 'userUserId' }, @{ persona = 'guest'; query = 'guestUserId' })) {
            $Value = "$($Request.Query.($Pair.query))".Trim()
            if ($Value) { $Overrides[$Pair.persona] = $Value }
        }
        $Country = "$($Request.Query.country)".Trim()

        $Licensed = Test-CIPPStandardLicense -StandardName 'ConditionalAccessCache' -TenantFilter $TenantFilter -Preset Entra -SkipLog
        $Battery = $null
        if ($Licensed -ne $false) {
            $Battery = Invoke-CIPPCASituationBattery -TenantFilter $TenantFilter -IdentityOverrides $Overrides -Country $Country
        }

        $Results = [PSCustomObject]@{
            tenantFilter = $TenantFilter
            licensed     = $Licensed -ne $false
            identities   = $Battery.identities
            candidates   = $Battery.candidates
            country      = $Battery.country
            situations   = @($Battery.situations | Where-Object { $null -ne $_ })
            excluded     = @($Battery.excluded | Where-Object { $null -ne $_ })
            summary      = $Battery.summary
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to evaluate the sign-in situations: $($_.Exception.Message)" -Sev 'Error'
        $Results = @{ Results = "Failed to evaluate the sign-in situations: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
