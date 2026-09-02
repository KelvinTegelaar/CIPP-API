function Resolve-CIPPIntuneTargetedMobileApps {
    <#
    .SYNOPSIS
        Resolves an app configuration template's targeted apps to the target tenant's mobile app ids.
    .DESCRIPTION
        A managed-device app configuration policy (deviceAppManagement/mobileAppConfigurations) names
        the apps it applies to by mobileApp id, and those ids exist only in the tenant the policy was
        captured from. Deploying the template's ids into another tenant fails with an unknown app.

        New-CIPPIntuneTemplate records each targeted app's identity alongside the ids
        (targetedMobileAppsDetails: bundle id, package id, display name, type). This function turns
        that into the matching app ids in the tenant being deployed to: bundle id or package id first,
        then display name plus app type. Any app that cannot be found is reported by name rather than
        silently dropped, because a configuration policy that targets nothing is not the policy that
        was asked for.

        Templates captured before the identity was recorded carry only ids. Those are kept when the
        target tenant has an app with that id (the same tenant, or a re-deploy), and rejected with an
        explanation otherwise.
    .PARAMETER PolicyFile
        The template payload, parsed from the template's RAWJson.
    .PARAMETER TenantFilter
        The tenant the policy is being deployed to.
    .OUTPUTS
        The resolved mobileApp ids for the target tenant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $PolicyFile,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        $Headers,
        $APIName = 'Resolve-CIPPIntuneTargetedMobileApps'
    )

    $TemplateAppIds = @($PolicyFile.targetedMobileApps | Where-Object { $_ })
    $Details = @($PolicyFile.targetedMobileAppsDetails | Where-Object { $_ })

    if ($TemplateAppIds.Count -eq 0 -and $Details.Count -eq 0) {
        return @()
    }

    $TenantApps = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$top=999' -tenantid $TenantFilter)
    $TenantAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($App in $TenantApps) { if ($App.id) { [void]$TenantAppIds.Add([string]$App.id) } }

    $Resolved = [System.Collections.Generic.List[string]]::new()
    $Unresolved = [System.Collections.Generic.List[string]]::new()

    if ($Details.Count -gt 0) {
        foreach ($Detail in $Details) {
            # Same id present in the target tenant: the template came from this tenant.
            if ($Detail.id -and $TenantAppIds.Contains([string]$Detail.id)) {
                if (-not $Resolved.Contains([string]$Detail.id)) { $Resolved.Add([string]$Detail.id) }
                continue
            }

            $Match = $null
            foreach ($IdentityProperty in 'bundleId', 'packageId', 'packageIdentifier') {
                $Identity = [string]$Detail.$IdentityProperty
                if ([string]::IsNullOrWhiteSpace($Identity)) { continue }
                $Match = $TenantApps | Where-Object { [string]$_.$IdentityProperty -eq $Identity } | Select-Object -First 1
                if ($Match) { break }
            }
            if (-not $Match -and $Detail.displayName) {
                # Name plus type: a store app and a line-of-business app can share a name and
                # cannot substitute for one another in a configuration policy.
                $Match = $TenantApps | Where-Object {
                    $_.displayName -eq $Detail.displayName -and (-not $Detail.'@odata.type' -or $_.'@odata.type' -eq $Detail.'@odata.type')
                } | Select-Object -First 1
            }

            if ($Match.id) {
                if (-not $Resolved.Contains([string]$Match.id)) { $Resolved.Add([string]$Match.id) }
            } else {
                $Identifier = $Detail.bundleId ?? $Detail.packageId ?? $Detail.packageIdentifier ?? $Detail.id
                $Unresolved.Add("'$($Detail.displayName ?? 'unknown app')' ($Identifier)")
            }
        }
    } else {
        foreach ($AppId in $TemplateAppIds) {
            if ($TenantAppIds.Contains([string]$AppId)) {
                if (-not $Resolved.Contains([string]$AppId)) { $Resolved.Add([string]$AppId) }
            } else {
                $Unresolved.Add("app id $AppId")
            }
        }
        if ($Unresolved.Count -gt 0) {
            $Message = "App configuration '$($PolicyFile.displayName)' targets apps that do not exist in $TenantFilter ($($Unresolved -join ', ')). This template was captured before CIPP recorded which apps those ids belong to, so they cannot be matched to this tenant's apps. Re-create the template from the source tenant and deploy it again."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev Error
            throw $Message
        }
    }

    if ($Unresolved.Count -gt 0) {
        $Message = "App configuration '$($PolicyFile.displayName)' targets apps that are not present in $TenantFilter : $($Unresolved -join ', '). Add these apps to Intune in this tenant, then deploy the template again."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev Error
        throw $Message
    }

    return @($Resolved)
}
