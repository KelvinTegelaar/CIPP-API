function Invoke-CIPPBaselineDisableSelfServiceLicenses {
    <#
    .SYNOPSIS
        DisableSelfServiceLicenses executor: writes the self-service purchase posture.
    .DESCRIPTION
        One write per offender the hook found, each on its own endpoint - the classic's
        exact routing: trial autoclaim to the admin.microsoft.com licensing API, email
        subscriptions as an authorization policy PATCH on Graph, and every product to the
        licensing.m365.microsoft.com policy API under its dedicated token scope. Partial
        failures log and continue; a round where everything failed throws.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Offenders = @($Current.offenders | Where-Object { $_ })
    if ($Offenders.Count -eq 0) { return }

    $Failures = 0
    foreach ($Item in $Offenders) {
        try {
            $Id = "$($Item.productId)"
            if ($Id -eq 'autoclaim') {
                $Body = @{ policyValue = "$($Item.policyValue)" } | ConvertTo-Json -Compress
                $null = New-GraphPostRequest -scope 'https://admin.microsoft.com/.default' -tenantid $TenantFilter -uri 'https://admin.microsoft.com/fd/m365licensing/v1/policies/autoclaim' -body $Body
            } elseif ($Id -eq 'allowedToSignUpEmailBasedSubscriptions') {
                $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -type PATCH -body '{"allowedToSignUpEmailBasedSubscriptions":false}'
            } else {
                $Body = @{ policyValue = "$($Item.policyValue)" } | ConvertTo-Json -Compress
                $null = New-GraphPostRequest -scope 'aeb86249-8ea3-49e2-900b-54cc8e308f85/.default' -tenantid $TenantFilter -uri "https://licensing.m365.microsoft.com/v1.0/policies/AllowSelfServicePurchase/products/$Id" -type PUT -body $Body
            }
        } catch {
            $Failures++
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Self-service license write failed for '$($Item.productName)': $($_.Exception.Message)" -Sev 'Error'
        }
    }
    if ($Failures -ge $Offenders.Count) { throw "Every self-service license write failed for $TenantFilter - see the log for the first error." }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Self-service licenses: aligned $($Offenders.Count - $Failures) of $($Offenders.Count) product(s)." -Sev 'Info'
}
