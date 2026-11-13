function Get-CIPPAppFederatedCredential {
    <#
    .SYNOPSIS
        Lists the federated identity credentials of a tenant's app registrations
    .DESCRIPTION
        A federated credential lets a token from another identity provider (GitHub Actions, a Kubernetes cluster,
        a managed identity, any OIDC issuer) sign in as the app, with no secret or certificate on the app. Returns
        one row per credential: the app registration, the issuer, the subject it accepts, the audiences and, for a
        flexible credential, its claims matching expression. Throws when the credentials of any app could not be
        read, so a cache never holds a partial set.
    .PARAMETER TenantFilter
        The tenant to read
    .PARAMETER Applications
        The app registrations to read (id, appId, displayName); every app registration in the tenant when not given
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [object[]]$Applications
    )

    $Apps = if ($PSBoundParameters.ContainsKey('Applications')) {
        @($Applications | Where-Object { $_.id })
    } else {
        @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/applications?$select=id,appId,displayName&$top=999' -tenantid $TenantFilter | Where-Object { $_.id })
    }
    if ($Apps.Count -eq 0) { return @() }

    $AppById = @{}
    $Requests = foreach ($App in $Apps) {
        $AppById[[string]$App.id] = $App
        @{ id = [string]$App.id; method = 'GET'; url = "applications/$($App.id)/federatedIdentityCredentials" }
    }

    $Failed = [System.Collections.Generic.List[string]]::new()
    $Rows = foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests))) {
        $App = $AppById[[string]$Response.id]
        if ([int]$Response.status -ne 200) {
            $Failed.Add("$($App.displayName) ($($Response.body.error.message ?? $Response.status))")
            continue
        }
        foreach ($Credential in @($Response.body.value)) {
            if (-not $Credential.id) { continue }
            [PSCustomObject]@{
                id                       = "$($App.id)|$($Credential.id)"
                applicationId            = [string]$App.id
                appId                    = [string]$App.appId
                appDisplayName           = [string]$App.displayName
                credentialId             = [string]$Credential.id
                name                     = [string]$Credential.name
                issuer                   = [string]$Credential.issuer
                subject                  = [string]$Credential.subject
                audiences                = @($Credential.audiences)
                description              = [string]$Credential.description
                claimsMatchingExpression = [string]$Credential.claimsMatchingExpression.value
            }
        }
    }
    if ($Failed.Count -gt 0) {
        throw "Federated credentials could not be read for $($Failed.Count) of $($Apps.Count) app registrations: $(($Failed | Select-Object -First 3) -join '; ')"
    }
    @($Rows)
}
