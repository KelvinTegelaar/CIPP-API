function Invoke-CIPPBaselineOauthConsent {
    <#
    .SYNOPSIS
        OauthConsent executor: builds the CIPP consent policy and routes user consent
        through it.
    .DESCRIPTION
        The classic's write, whole and in order: create the cipp-consent-policy when the
        tenant has none, ensure the fixed Office 365 Management delegated include, ensure a
        delegated AND an application include per allowed app (only the missing ones - the
        POSTs are add-only), then PATCH the authorization policy to hand the default user
        role ManagePermissionGrantsForSelf.cipp-consent-policy. Everything DELEGATED - the
        authorization policy write returns 403 app-only, which is why the classic never
        used -AsApp here.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $PolicyUri = 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies'
    if ($Current.policyExists -ne $true) {
        $Existing = @(New-GraphGetRequest -uri "$PolicyUri/" -tenantid $TenantFilter) | Where-Object { $_.id -eq 'cipp-consent-policy' }
        if (-not $Existing) {
            $null = New-GraphPostRequest -tenantid $TenantFilter -uri $PolicyUri -type POST -body '{ "id":"cipp-consent-policy", "displayName":"Application Consent Policy", "description":"This policy controls the current application consent policies."}' -ContentType 'application/json'
        }
    }

    foreach ($Key in @($Current.missingIncludes)) {
        $Type, $AppId = "$Key" -split '\|'
        $Body = @{ permissionClassification = 'all'; permissionType = $Type; clientApplicationIds = @($AppId) } | ConvertTo-Json -Compress
        try {
            $null = New-GraphPostRequest -tenantid $TenantFilter -uri "$PolicyUri/cipp-consent-policy/includes" -type POST -body $Body -ContentType 'application/json'
        } catch {
            # An include that already exists fails the POST harmlessly - the classic
            # continued past exactly this.
            Write-Information "Baselines: consent include $Key on $TenantFilter continued past: $($_.Exception.Message)"
        }
    }

    if ($Current.consentPolicyAssigned -ne $true) {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -type PATCH -body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["ManagePermissionGrantsForSelf.cipp-consent-policy"]}' -ContentType 'application/json'
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Routed user app consent through the CIPP consent policy.' -Sev 'Info'
}
