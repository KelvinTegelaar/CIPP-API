function Invoke-CIPPBaselineRestrictThirdPartyStorageServices {
    <#
    .SYNOPSIS
        RestrictThirdPartyStorageServices executor: disables the Microsoft 365 on the web
        service principal.
    .DESCRIPTION
        The classic's write: one PATCH against the appId-addressed upsert endpoint with the
        'Prefer: create-if-missing' header - the plain /servicePrincipals/{appId} path does
        not resolve this principal, and the upsert also creates-then-disables it on tenants
        where it never existed.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Body = @{ accountEnabled = $false } | ConvertTo-Json -Compress
    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='c1f33bc0-bdb4-4248-ba9b-096807ddb43e')" -body $Body -tenantid $TenantFilter -type PATCH -AddedHeaders @{ 'Prefer' = 'create-if-missing' }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Restricted third-party storage services in Microsoft 365 on the web.' -Sev 'Info'
}
