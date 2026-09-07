function Get-CIPPPIMRoleAssignments {
    <#
    .SYNOPSIS
        Lists a tenant's directory role assignments with their PIM assignment type.

    .DESCRIPTION
        One row per principal x role x scope x assignment kind, merged from:
          - roleAssignmentScheduleInstances (v1.0, $expand=principal): every ACTIVE assignment,
            including ones made outside PIM (those show as assignmentType 'Assigned', memberType
            'Direct', endDateTime null). 'Activated' = activated from an eligibility.
          - roleEligibilitySchedules (v1.0, $expand=principal): ELIGIBLE assignments.
        Both need -AsApp: RoleManagement.*.Directory is an application permission.

        Tenants without Entra ID P2 have no PIM API; there the unified roleManagement/directory/
        roleAssignments list is used and every row is Permanent/Direct (PIMCapable = $false).

        AssignmentType values:
          Permanent             active, no end date (what the PermanentActiveAdminAssigned alert watches)
          Active                active, time-bound (endDateTime set)
          ActivatedFromEligible active because the principal activated an eligibility
          Eligible              eligible; EligibilityPermanent tells whether the eligibility itself expires

        MemberType 'Group' rows are inherited through a role-assignable group: the principal shown
        is the member, and the assignment to act on belongs to the group.

    .PARAMETER PrincipalId
        Restrict to one principal (pushed into the Graph filter - cheap for the user page).

    .PARAMETER RoleDefinitionId
        Restrict to one role template id.

    .PARAMETER FromCache
        Read the CIPPDB cache (RoleAssignmentScheduleInstances / RoleEligibilitySchedules, falling
        back to the directoryRoles 'Roles' cache for tenants without PIM rows). Used for AllTenants.

    .PARAMETER IncludePolicy
        Attach the role's PIM policy summary (PolicySummary, PolicyBelowFloor) to every row.

    .PARAMETER IncludeUnassignedRoles
        Live reads only: also return one row per role definition that has no assignment at all
        (AssignmentType 'Unassigned', no principal), so the result doubles as the role catalogue.
        Ignored when -PrincipalId is given.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$PrincipalId,

        [string]$RoleDefinitionId,

        [switch]$FromCache,

        [switch]$IncludePolicy,

        [switch]$IncludeUnassignedRoles
    )

    $PrivilegedCatalog = Get-CIPPPrivilegedRoleTemplateIds -WithNames
    $PrivilegedIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($PrivilegedCatalog.Id), [System.StringComparer]::OrdinalIgnoreCase)
    $RoleNames = @{}
    # Description / built-in flag per role id, filled from the definitions (live) or the Roles cache.
    $RoleInfo = @{}
    foreach ($Entry in $PrivilegedCatalog) { $RoleNames[$Entry.Id] = $Entry.DisplayName }

    function ConvertTo-PrincipalType {
        param([string]$ODataType)
        switch -Wildcard ($ODataType) {
            '*user' { 'User' }
            '*group' { 'Group' }
            '*servicePrincipal' { 'ServicePrincipal' }
            default { 'Unknown' }
        }
    }

    function ConvertTo-DateTime {
        param($Value)
        if ($null -eq $Value -or "$Value" -eq '') { return $null }
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        try { return ([datetime]$Value).ToUniversalTime() } catch { return $null }
    }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $ScopeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function ConvertTo-Row {
        param(
            $Principal, [string]$PrincipalObjectId, [string]$RoleId, [string]$AssignmentType, [string]$MemberType,
            [string]$ScopeId, $Start, $End, [string]$Source, [string]$ScheduleId, [string]$RoleAssignmentId,
            [bool]$PIMCapable, [bool]$EligibilityPermanent = $false
        )
        if ([string]::IsNullOrWhiteSpace($ScopeId)) { $ScopeId = '/' }
        $null = $ScopeIds.Add($ScopeId)
        $Type = ConvertTo-PrincipalType ($Principal.'@odata.type')
        [PSCustomObject]@{
            Tenant                     = $TenantFilter
            Id                         = "$PrincipalObjectId|$RoleId|$ScopeId|$AssignmentType"
            PrincipalId                = $PrincipalObjectId
            PrincipalDisplayName       = $Principal.displayName
            PrincipalUserPrincipalName = $Principal.userPrincipalName
            PrincipalType              = $Type
            PrincipalAppId             = $Principal.appId
            RoleDefinitionId           = $RoleId
            RoleDisplayName            = $RoleNames[$RoleId] ?? $RoleId
            RoleDescription            = $null
            RoleIsBuiltIn              = $null
            IsPrivilegedRole           = $PrivilegedIds.Contains($RoleId)
            AssignmentType             = $AssignmentType
            IsAssigned                 = ($AssignmentType -ne 'Unassigned')
            IsPermanent                = ($AssignmentType -eq 'Permanent')
            EligibilityPermanent       = $EligibilityPermanent
            MemberType                 = $MemberType
            DirectoryScopeId           = $ScopeId
            Scope                      = if ($ScopeId -eq '/') { 'Directory' } else { $ScopeId }
            StartDateTime              = ConvertTo-DateTime $Start
            EndDateTime                = ConvertTo-DateTime $End
            Source                     = $Source
            ScheduleId                 = $ScheduleId
            RoleAssignmentId           = $RoleAssignmentId
            PIMCapable                 = $PIMCapable
            PolicySummary              = $null
            PolicyBelowFloor           = $null
        }
    }

    function Add-InstanceRows {
        param($Instances, [bool]$PIMCapable = $true)
        foreach ($Instance in @($Instances)) {
            if (-not $Instance.principalId -or -not $Instance.roleDefinitionId) { continue }
            $End = ConvertTo-DateTime $Instance.endDateTime
            $Type = if ($Instance.assignmentType -eq 'Activated') {
                'ActivatedFromEligible'
            } elseif ($null -eq $End) {
                'Permanent'
            } else {
                'Active'
            }
            $Source = if ($Type -eq 'Permanent' -and $Instance.memberType -ne 'Group') { 'Direct' } else { 'PIM' }
            $Principal = $Instance.principal ?? [PSCustomObject]@{ displayName = $null; userPrincipalName = $null; '@odata.type' = $null; appId = $null }
            $Rows.Add((ConvertTo-Row -Principal $Principal -PrincipalObjectId $Instance.principalId -RoleId $Instance.roleDefinitionId -AssignmentType $Type -MemberType ($Instance.memberType ?? 'Direct') -ScopeId $Instance.directoryScopeId -Start $Instance.startDateTime -End $Instance.endDateTime -Source $Source -ScheduleId $Instance.roleAssignmentScheduleId -RoleAssignmentId $Instance.roleAssignmentOriginId -PIMCapable $PIMCapable))
        }
    }

    function Add-EligibilityRows {
        param($Schedules)
        foreach ($Schedule in @($Schedules)) {
            if (-not $Schedule.principalId -or -not $Schedule.roleDefinitionId) { continue }
            if ($Schedule.status -and $Schedule.status -notin @('Provisioned', 'PendingProvisioning', 'ScheduleCreated')) { continue }
            $Principal = $Schedule.principal ?? [PSCustomObject]@{ displayName = $null; userPrincipalName = $null; '@odata.type' = $null; appId = $null }
            $Expiration = $Schedule.scheduleInfo.expiration
            $EligibilityPermanent = ($null -eq $Expiration -or $Expiration.type -eq 'noExpiration')
            $Rows.Add((ConvertTo-Row -Principal $Principal -PrincipalObjectId $Schedule.principalId -RoleId $Schedule.roleDefinitionId -AssignmentType 'Eligible' -MemberType ($Schedule.memberType ?? 'Direct') -ScopeId $Schedule.directoryScopeId -Start $Schedule.scheduleInfo.startDateTime -End $Expiration.endDateTime -Source 'PIM' -ScheduleId $Schedule.id -RoleAssignmentId $null -PIMCapable $true -EligibilityPermanent $EligibilityPermanent))
        }
    }

    if ($FromCache.IsPresent) {
        $Instances = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'RoleAssignmentScheduleInstances')
        $Eligibilities = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'RoleEligibilitySchedules')
        $CachedRoles = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Roles')
        foreach ($Role in $CachedRoles) {
            if ($Role.roleTemplateId -and $Role.displayName) { $RoleNames[$Role.roleTemplateId] = $Role.displayName }
            if ($Role.roleTemplateId) { $RoleInfo[$Role.roleTemplateId] = @{ Description = $Role.description; IsBuiltIn = $null } }
        }

        if ($Instances.Count -gt 0 -or $Eligibilities.Count -gt 0) {
            Add-InstanceRows -Instances $Instances -PIMCapable $true
            Add-EligibilityRows -Schedules $Eligibilities
        } else {
            # No PIM data cached (non-P2 tenant or PIM never onboarded): directoryRoles members are
            # all permanent, direct assignments.
            foreach ($Role in $CachedRoles) {
                foreach ($Member in @($Role.members)) {
                    if (-not $Member.id) { continue }
                    $Rows.Add((ConvertTo-Row -Principal $Member -PrincipalObjectId $Member.id -RoleId ($Role.roleTemplateId ?? $Role.id) -AssignmentType 'Permanent' -MemberType 'Direct' -ScopeId '/' -Start $null -End $null -Source 'Direct' -ScheduleId $null -RoleAssignmentId $null -PIMCapable $false))
                }
            }
        }
    } else {
        $PIMCapable = [bool](Test-CIPPStandardLicense -StandardName 'PIMRoleAssignments' -TenantFilter $TenantFilter -Preset EntraP2 -SkipLog)

        # Role names come from the tenant's definitions (custom roles included); PIM's
        # roleDefinitionId equals the template id for built-in roles and the definition id otherwise.
        # beta: isPrivileged is not on the v1.0 unifiedRoleDefinition and a $select of it fails the
        # whole request, which left every row showing the template GUID.
        $Definitions = @()
        try {
            $Definitions = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions?$select=id,templateId,displayName,description,isBuiltIn,isPrivileged' -tenantid $TenantFilter)
            foreach ($Definition in @($Definitions)) {
                $Info = @{ Description = $Definition.description; IsBuiltIn = [bool]$Definition.isBuiltIn }
                if ($Definition.id) { $RoleNames[$Definition.id] = $Definition.displayName; $RoleInfo[$Definition.id] = $Info }
                if ($Definition.templateId) { $RoleNames[$Definition.templateId] = $Definition.displayName; $RoleInfo[$Definition.templateId] = $Info }
                if ($Definition.isPrivileged -eq $true) {
                    $null = $PrivilegedIds.Add($Definition.id)
                    if ($Definition.templateId) { $null = $PrivilegedIds.Add($Definition.templateId) }
                }
            }
        } catch {
            Write-Information "Could not list role definitions for $TenantFilter`: $($_.Exception.Message)"
        }

        $Filters = [System.Collections.Generic.List[string]]::new()
        if ($PrincipalId) { $Filters.Add("principalId eq '$PrincipalId'") }
        if ($RoleDefinitionId) { $Filters.Add("roleDefinitionId eq '$RoleDefinitionId'") }
        $FilterClause = if ($Filters.Count -gt 0) { "&`$filter=$($Filters -join ' and ')" } else { '' }

        if ($PIMCapable) {
            $Instances = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal$FilterClause" -tenantid $TenantFilter -AsApp $true)
            Add-InstanceRows -Instances $Instances -PIMCapable $true
            $Eligibilities = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?`$expand=principal$FilterClause" -tenantid $TenantFilter -AsApp $true)
            Add-EligibilityRows -Schedules $Eligibilities
        } else {
            $Assignments = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$select=id,principalId,roleDefinitionId,directoryScopeId&`$top=999$FilterClause" -tenantid $TenantFilter)
            # Resolve principals in bulk; getByIds returns in milliseconds where $expand costs seconds.
            $Principals = @{}
            $PrincipalIds = @($Assignments.principalId | Where-Object { $_ } | Sort-Object -Unique)
            for ($i = 0; $i -lt $PrincipalIds.Count; $i += 1000) {
                $Body = ConvertTo-Json -InputObject @{ ids = @($PrincipalIds[$i..([Math]::Min($i + 999, $PrincipalIds.Count - 1))]) } -Compress
                $Resolved = New-GraphPOSTRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,displayName,userPrincipalName,appId' -body $Body
                foreach ($Principal in @($Resolved.value)) { $Principals[$Principal.id] = $Principal }
            }
            foreach ($Assignment in $Assignments) {
                if (-not $Assignment.principalId) { continue }
                $Principal = $Principals[$Assignment.principalId] ?? [PSCustomObject]@{ displayName = $null; userPrincipalName = $null; '@odata.type' = $null; appId = $null }
                $Rows.Add((ConvertTo-Row -Principal $Principal -PrincipalObjectId $Assignment.principalId -RoleId $Assignment.roleDefinitionId -AssignmentType 'Permanent' -MemberType 'Direct' -ScopeId $Assignment.directoryScopeId -Start $null -End $null -Source 'Direct' -ScheduleId $null -RoleAssignmentId $Assignment.id -PIMCapable $false))
            }
        }

        # The role catalogue: one row per definition nobody holds, so the PIM page can list every
        # role the way the old Roles page did. Skipped for a single-principal read.
        if ($IncludeUnassignedRoles.IsPresent -and -not $PrincipalId) {
            $AssignedRoleIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Rows.RoleDefinitionId | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Definition in $Definitions) {
                $RoleId = $Definition.templateId ?? $Definition.id
                if (-not $RoleId) { continue }
                if ($RoleDefinitionId -and $RoleId -ne $RoleDefinitionId -and $Definition.id -ne $RoleDefinitionId) { continue }
                if ($AssignedRoleIds.Contains($RoleId) -or ($Definition.id -and $AssignedRoleIds.Contains($Definition.id))) { continue }
                $NoPrincipal = [PSCustomObject]@{ displayName = $null; userPrincipalName = $null; '@odata.type' = $null; appId = $null }
                $Row = ConvertTo-Row -Principal $NoPrincipal -PrincipalObjectId '' -RoleId $RoleId -AssignmentType 'Unassigned' -MemberType '' -ScopeId '/' -Start $null -End $null -Source '' -ScheduleId $null -RoleAssignmentId $null -PIMCapable $PIMCapable
                $Row.PrincipalId = $null
                $Row.PrincipalType = 'None'
                $Rows.Add($Row)
            }
        }

        # Administrative-unit scopes: show the unit's name instead of its id.
        $UnitIds = @($ScopeIds | Where-Object { $_ -match '^/administrativeUnits/' } | ForEach-Object { $_ -replace '^/administrativeUnits/', '' })
        if ($UnitIds.Count -gt 0) {
            try {
                $UnitRequests = @(foreach ($UnitId in $UnitIds) {
                        @{ id = $UnitId; method = 'GET'; url = "/directory/administrativeUnits/$UnitId`?`$select=id,displayName" }
                    })
                $UnitResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests $UnitRequests -Version 'v1.0'
                $UnitNames = @{}
                foreach ($Result in @($UnitResults)) {
                    if ($Result.body.displayName) { $UnitNames["/administrativeUnits/$($Result.id)"] = "AU: $($Result.body.displayName)" }
                }
                foreach ($Row in $Rows) {
                    if ($UnitNames.ContainsKey($Row.DirectoryScopeId)) { $Row.Scope = $UnitNames[$Row.DirectoryScopeId] }
                }
            } catch {
                Write-Information "Could not resolve administrative unit names for $TenantFilter`: $($_.Exception.Message)"
            }
        }
    }

    # Names for rows whose role was not resolvable earlier (cache path, roles never activated).
    foreach ($Row in $Rows) {
        if ($Row.RoleDisplayName -eq $Row.RoleDefinitionId -and $RoleNames.ContainsKey($Row.RoleDefinitionId)) {
            $Row.RoleDisplayName = $RoleNames[$Row.RoleDefinitionId]
        }
        if (-not $Row.IsPrivilegedRole -and $PrivilegedIds.Contains($Row.RoleDefinitionId)) { $Row.IsPrivilegedRole = $true }
        $Info = $RoleInfo[$Row.RoleDefinitionId]
        if ($Info) {
            $Row.RoleDescription = $Info.Description
            $Row.RoleIsBuiltIn = $Info.IsBuiltIn
        }
    }

    if ($IncludePolicy.IsPresent -and $Rows.Count -gt 0) {
        try {
            $Policies = @(Get-CIPPPIMRolePolicies -TenantFilter $TenantFilter -FromCache:$FromCache)
            $PolicyByRole = @{}
            foreach ($Policy in $Policies) { $PolicyByRole[$Policy.RoleDefinitionId] = $Policy }
            foreach ($Row in $Rows) {
                $Policy = $PolicyByRole[$Row.RoleDefinitionId]
                if ($Policy) {
                    $Row.PolicySummary = $Policy.Summary.SummaryText
                    $Row.PolicyBelowFloor = $Policy.Summary.BelowFloor
                }
            }
        } catch {
            Write-Information "Could not load PIM policies for $TenantFilter`: $($_.Exception.Message)"
        }
    }

    return @($Rows)
}
