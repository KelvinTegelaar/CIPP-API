function Invoke-AddEnrollmentRestriction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    .DESCRIPTION
        Creates or updates an enrollment (device type) restriction with its priority and group assignment (AssignTo with customGroup names, as Intune templates use). Creating fans out over selectedTenants (or a tenantFilter list) and can take its settings from a saved template (TemplateId, or TemplateList from the deploy drawer). replacename sets how groups are handled, as for conditional access templates: displayName (default) assigns the template's groups by name, leave keeps each restriction's current assignment, AllUsers assigns all users. CreateGroups creates the named groups a tenant does not have. Editing sends one tenantFilter with the restriction's ConfigurationIds, and may pass GroupIds picked in that tenant instead of group names.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body

    $ConfigurationIds = @($Body.ConfigurationIds | Where-Object { $_ })
    $Editing = $ConfigurationIds.Count -gt 0
    $TenantInput = $(if ($Editing) { $Body.tenantFilter } else { $Body.selectedTenants ?? $Body.tenantFilter })
    $Tenants = @(@($TenantInput) | ForEach-Object { $_.value ?? $_ } | Where-Object { $_ })
    if ($Tenants -contains 'AllTenants') { $Tenants = @((Get-Tenants).defaultDomainName) }

    # Tenant scope: a scoped role must not reach tenants outside its allowed set through the tenant list.
    $AllowedTenants = Test-CippAccess -Request $Request -TenantList
    if ($AllowedTenants -ne 'AllTenants') {
        $AllowedTenantList = (Get-Tenants -IncludeErrors) | Where-Object { $_.customerId -in $AllowedTenants }
        $Tenants = @($Tenants | Where-Object { $_ -in $AllowedTenantList.defaultDomainName })
    }

    # Editing reaches restrictions for specific groups only; the default restriction is managed by
    # the DefaultPlatformRestrictions standard, and an edit sent for it would create a new restriction.
    $BadRequest = $(if (@($ConfigurationIds | Where-Object { "$_" -notmatch '_SinglePlatformRestriction$' }).Count -gt 0) {
            'Only restrictions for specific groups can be edited here. The default restriction is managed by the DefaultPlatformRestrictions standard.'
        })
    $Source = $Body
    $TemplateId = "$($Body.TemplateId.value ?? $Body.TemplateId ?? $Body.TemplateList.value ?? $Body.TemplateList)"
    if (-not $BadRequest -and -not $Editing -and -not [string]::IsNullOrWhiteSpace($TemplateId)) {
        $Table = Get-CippTable -tablename 'templates'
        $SafeId = ConvertTo-CIPPODataFilterValue -Value $TemplateId
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'EnrollmentRestrictionTemplate' and RowKey eq '$SafeId'" | Select-Object -First 1
        if ($Entity.JSON) { $Source = $Entity.JSON | ConvertFrom-Json } else { $BadRequest = "Enrollment restriction template $TemplateId was not found." }
    }
    if (-not $BadRequest) {
        try {
            $Settings = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject $Source
            $null = New-CIPPEnrollmentRestrictionBody -Settings $Settings
        } catch {
            $BadRequest = "$($_.Exception.Message)"
        }
    }
    # How a deploy handles groups, with AddCAPolicy's replacename values: displayName (or none) keeps
    # the template's assignment, its groups looked up by name; leave keeps each restriction's current
    # assignment, so a new one is unassigned; AllUsers assigns all users.
    if (-not $BadRequest -and -not $Editing) {
        switch ("$($Body.replacename.value ?? $Body.replacename)") {
            'leave' { $Settings.AssignTo = 'On'; $Settings.customGroup = '' }
            'AllUsers' { $Settings.AssignTo = 'allLicensedUsers'; $Settings.customGroup = '' }
        }
    }
    if (-not $BadRequest) {
        $BadRequest = $(if ($Tenants.Count -eq 0) {
                'Select at least one tenant.'
            } elseif ([string]::IsNullOrWhiteSpace($Settings.displayName)) {
                'A restriction name is required.'
            } elseif ($Settings.AssignTo -eq 'customGroup' -and -not $Body.GroupIds -and [string]::IsNullOrWhiteSpace($Settings.customGroup)) {
                'Choose the groups to assign the restriction to.'
            })
    }
    if ($BadRequest) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = $BadRequest }
            })
    }

    # Group ids picked in the drawer (applyPickedGroups) only exist in that one tenant.
    $GroupIds = @($(if ($Tenants.Count -eq 1) { $Body.GroupIds | Where-Object { $_ } }))

    $Failed = 0
    $Results = foreach ($Tenant in $Tenants) {
        $SetParams = @{
            TenantFilter = $Tenant
            Settings     = $Settings
            GroupIds     = $GroupIds
            Headers      = $Headers
            APIName      = $APIName
        }
        if ($Editing) {
            $SetParams.ConfigurationIds = $ConfigurationIds
            $SetParams.PriorityMode = 'Always'
        }
        if ("$($Body.CreateGroups)" -eq 'true') { $SetParams.CreateGroups = $true }
        try {
            Set-CIPPEnrollmentRestriction @SetParams
        } catch {
            $Failed++
            "$($_.Exception.Message)"
        }
    }

    $StatusCode = $(if ($Failed -eq 0) { [HttpStatusCode]::OK } elseif ($Failed -lt $Tenants.Count) { [HttpStatusCode]::MultiStatus } else { [HttpStatusCode]::InternalServerError })
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
