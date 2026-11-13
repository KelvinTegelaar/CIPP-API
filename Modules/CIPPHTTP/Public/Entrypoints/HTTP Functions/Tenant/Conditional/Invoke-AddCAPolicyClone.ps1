function Invoke-AddCAPolicyClone {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    .DESCRIPTION
        Duplicates a Conditional Access policy within the same tenant under a new display name, with the chosen state.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Tenant the source policy lives in; the copy is created in the same tenant.
    # Resolved in the same order as Test-CIPPAccess, so the tenant acted on is the tenant RBAC checked.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    # ID of the Conditional Access policy to duplicate.
    $ID = $Request.Body.ID
    # Display name for the new policy; must differ from every existing policy name in the tenant.
    $NewDisplayName = "$($Request.Body.newDisplayName)".Trim()
    # State of the new policy: disabled, enabledForReportingButNotEnforced, enabled or sameAsSource. Defaults to disabled.
    $State = $Request.Body.state.value ?? $Request.Body.state
    if ([string]::IsNullOrWhiteSpace($State)) { $State = 'disabled' }

    # Without a tenant, Graph calls fall back to the partner tenant, so reject before any request.
    $ValidationError = if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        'tenantFilter is required and must be a single tenant'
    } elseif ([string]::IsNullOrWhiteSpace($ID) -or -not (Test-IsGuid -String $ID)) {
        'ID must be the GUID of the policy to duplicate'
    } elseif ([string]::IsNullOrWhiteSpace($NewDisplayName)) {
        'You must enter a display name for the duplicated policy'
    } elseif ($State -notin 'disabled', 'enabledForReportingButNotEnforced', 'enabled', 'sameAsSource') {
        "Unsupported state '$State'. Use disabled, enabledForReportingButNotEnforced, enabled or sameAsSource"
    }
    if ($ValidationError) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ 'Results' = "Error: $ValidationError" }
            })
    }

    try {
        # One list read serves both the source lookup and the name collision check.
        $AllPolicies = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999' -tenantid $TenantFilter -asApp $true)
        $Source = $AllPolicies | Where-Object -Property id -EQ $ID | Select-Object -First 1
        if (-not $Source) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ 'Results' = "Error: Conditional Access policy $ID was not found in $TenantFilter" }
                })
        }
        $SourceName = $Source.displayName
        # -in is case-insensitive, so a copy that differs only by case is refused too. The list can lag a
        # create by a few seconds, so an immediate resubmit of the same name may still get through.
        if ($NewDisplayName -in @($AllPolicies.displayName)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ 'Results' = "Error: A Conditional Access policy named '$NewDisplayName' already exists in $TenantFilter" }
                })
        }

        # Same-tenant copy: keep every id as-is. The template deploy path (New-CIPPCAPolicy) is deliberately
        # not used, its service principal filtering and name-based auth strength lookup can change the copy.
        $Policy = ConvertTo-Json -InputObject $Source -Depth 100 | ConvertFrom-Json
        $Policy = $Policy | Select-Object -Property * -ExcludeProperty id, templateId, createdDateTime, modifiedDateTime, deletedDateTime, '@odata.context'
        $Policy.displayName = $NewDisplayName
        $Policy.state = if ($State -eq 'sameAsSource') { $Source.state } else { $State }
        if ($Policy.grantControls) {
            $Policy.grantControls.PSObject.Properties.Remove('authenticationStrength@odata.context')
            # Graph links a strength by id only; the expanded object it returns is read-only.
            if ($Policy.grantControls.authenticationStrength.id) {
                $Policy.grantControls.authenticationStrength = [pscustomobject]@{ id = $Policy.grantControls.authenticationStrength.id }
            }
        }
        if ($Policy.sessionControls -and $Policy.sessionControls.disableResilienceDefaults -ne $true) {
            $Policy.sessionControls.PSObject.Properties.Remove('disableResilienceDefaults')
        }
        Format-CIPPCAPolicy -Policy $Policy
        $RawJSON = ConvertTo-Json -InputObject $Policy -Depth 100 -Compress

        $NewPolicy = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $TenantFilter -type POST -body $RawJSON -asApp $true

        $Result = "Successfully duplicated CA policy '$($SourceName)' to '$($NewDisplayName)'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "$Result (new id $($NewPolicy.id), state $($Policy.state))" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to duplicate CA policy $($SourceName ?? $ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}
