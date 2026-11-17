function Invoke-ListIntuneAssignments {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .SYNOPSIS
        Lists the Intune assignments that apply to one user, group or device.
    .DESCRIPTION
        Shows every Intune policy, app, script and enrollment profile assigned to a user, group or Intune device, and
        whether it applies, is excluded or depends on an assignment filter. Policies come from the Intune reporting
        cache; group memberships are read live so nested and dynamic groups count.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # What to look up: user, group or device
    $PrincipalType = $Request.Query.type
    # The user's id or UPN, the group's id, or the Intune managed device id
    $PrincipalId = $Request.Query.id
    # Group lookups only: also include assignments to the groups this group is nested in
    $IncludeNested = $Request.Query.includeNested -eq $true -or $Request.Query.includeNested -eq 'true'

    if ($PrincipalType -notin @('user', 'group', 'device') -or [string]::IsNullOrWhiteSpace($PrincipalId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'type (user, group or device) and id are required' }
            })
    }

    try {
        $CountRow = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceConfigurations' -CountsOnly)[0]
        if (-not $CountRow) {
            throw [System.Management.Automation.ItemNotFoundException]::new('No Intune data is cached for this tenant yet. Refresh the Intune cache and try again.')
        }

        # groupId -> the ways the principal belongs to it. Dimension decides whether an exclusion can cancel an inclusion.
        $Memberships = @{}
        $AddGroups = {
            param($Groups, $Dimension, $Suffix)
            foreach ($Group in @($Groups)) {
                if (-not $Group.id) { continue }
                if (-not $Memberships.ContainsKey([string]$Group.id)) { $Memberships[[string]$Group.id] = [System.Collections.Generic.List[object]]::new() }
                $Memberships[[string]$Group.id].Add([PSCustomObject]@{ Dimension = $Dimension; Label = "$($Group.displayName)$Suffix" })
            }
        }
        $MemberOf = { param($Path) New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/$Path/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName&`$top=999" -tenantid $TenantFilter }
        $AllUsers = $null
        $AllDevices = $null
        $DevicePlatform = $null
        $PlatformOf = {
            param($Text)
            switch -Regex ($Text) {
                'mac' { 'macOS'; break }
                'ios|ipad' { 'iOS'; break }
                'android|aosp' { 'Android'; break }
                'linux' { 'Linux'; break }
                'windows|win32|winGet|microsoftStore|officeSuite' { 'Windows'; break }
            }
        }

        switch ($PrincipalType) {
            'user' {
                $User = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$PrincipalId`?`$select=id" -tenantid $TenantFilter
                & $AddGroups (& $MemberOf "users/$($User.id)") 'user' ''
                $AllUsers = [PSCustomObject]@{ Dimension = 'user'; Label = 'All users' }
            }
            'device' {
                $Device = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$PrincipalId`?`$select=id,azureADDeviceId,userId,operatingSystem" -tenantid $TenantFilter
                $DevicePlatform = & $PlatformOf $Device.operatingSystem
                if ($Device.azureADDeviceId -and $Device.azureADDeviceId -ne '00000000-0000-0000-0000-000000000000') {
                    $EntraDevice = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$($Device.azureADDeviceId)'&`$select=id" -tenantid $TenantFilter)[0]
                    if ($EntraDevice.id) { & $AddGroups (& $MemberOf "devices/$($EntraDevice.id)") 'device' '' }
                }
                $AllDevices = [PSCustomObject]@{ Dimension = 'device'; Label = 'All devices' }
                if ($Device.userId) {
                    & $AddGroups (& $MemberOf "users/$($Device.userId)") 'user' ' (primary user)'
                    $AllUsers = [PSCustomObject]@{ Dimension = 'user'; Label = 'All users (primary user)' }
                }
            }
            'group' {
                $Group = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$PrincipalId`?`$select=id,displayName" -tenantid $TenantFilter
                & $AddGroups $Group 'group' ''
                if ($IncludeNested) { & $AddGroups (& $MemberOf "groups/$($Group.id)") 'group' ' (parent group)' }
            }
        }

        $FilterNames = @{}
        foreach ($Filter in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'IntuneAssignmentFilters' -Fields 'id', 'displayName')) {
            if ($Filter.id) { $FilterNames[[string]$Filter.id] = $Filter.displayName }
        }

        $Sources = Get-CIPPIntuneAssignmentSources
        $SeenPolicies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Rows = foreach ($CacheType in $Sources.Keys) {
            foreach ($Policy in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $CacheType -Fields 'id', 'displayName', 'name', 'assignments', '@odata.type', 'platforms')) {
                if (-not $Policy.id -or -not $SeenPolicies.Add([string]$Policy.id)) { continue }
                $Includes = [ordered]@{}
                $Excludes = [System.Collections.Generic.List[object]]::new()
                foreach ($Assignment in @($Policy.assignments)) {
                    $Target = $Assignment.target
                    $Matched = switch ($Target.'@odata.type') {
                        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $AllUsers }
                        '#microsoft.graph.allDevicesAssignmentTarget' { $AllDevices }
                        default { if ($Target.groupId) { $Memberships[[string]$Target.groupId] } }
                    }
                    if (-not $Matched) { continue }
                    if ($Target.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget') {
                        foreach ($Match in @($Matched)) { $Excludes.Add($Match) }
                        continue
                    }
                    $FilterId = [string]$Target.deviceAndAppManagementAssignmentFilterId
                    $FilterLabel = if ($FilterId -and $FilterId -ne '00000000-0000-0000-0000-000000000000' -and $Target.deviceAndAppManagementAssignmentFilterType -in @('include', 'exclude')) {
                        '{0} ({1})' -f ($FilterNames[$FilterId] ?? $FilterId), $Target.deviceAndAppManagementAssignmentFilterType
                    }
                    $Intent = [string]$Assignment.intent
                    if (-not $Includes.Contains($Intent)) { $Includes[$Intent] = [System.Collections.Generic.List[object]]::new() }
                    foreach ($Match in @($Matched)) {
                        $Includes[$Intent].Add([PSCustomObject]@{ Dimension = $Match.Dimension; Label = $Match.Label; Filter = $FilterLabel })
                    }
                }
                if ($Includes.Count -eq 0 -and $Excludes.Count -eq 0) { continue }

                $ExcludedDimensions = @($Excludes.Dimension)
                $ExcludedVia = (@($Excludes.Label) | Select-Object -Unique) -join ', '
                $Type = if ($Policy.platforms) { [string]$Policy.platforms } else { ([string]$Policy.'@odata.type') -replace '^#microsoft\.graph\.', '' }
                $Platform = & $PlatformOf $Type
                if ($DevicePlatform -and $Platform -and $Platform -ne $DevicePlatform) { continue }
                $IntentsToReport = if ($Includes.Count -gt 0) { @($Includes.Keys) } else { @('') }
                foreach ($Intent in $IntentsToReport) {
                    $Entries = if ($Includes.Count -gt 0) { @($Includes[$Intent]) } else { @() }
                    # An exclusion only cancels an inclusion of the same kind; Intune does not reliably apply a user-group exclusion to a device-group inclusion or the other way round.
                    $Open = @($Entries.Where({ $_.Dimension -notin $ExcludedDimensions }))
                    $Status = if ($Open.Count -eq 0) {
                        'Excluded'
                    } elseif ($Excludes.Count -gt 0) {
                        'Unclear (user and device groups mixed)'
                    } elseif (@($Open.Where({ -not $_.Filter })).Count -eq 0) {
                        'Applies if the filter matches'
                    } else {
                        'Applies'
                    }
                    [PSCustomObject]@{
                        category       = $Sources[$CacheType]
                        displayName    = $Policy.displayName ?? $Policy.name
                        type           = $Type
                        platform       = $Platform
                        intent         = switch ($Intent) {
                            'required' { 'Required' }
                            'available' { 'Available' }
                            'uninstall' { 'Uninstall' }
                            'availableWithoutEnrollment' { 'Available without enrollment' }
                            default { '' }
                        }
                        status         = $Status
                        assignedVia    = (@($Entries.Label) | Select-Object -Unique) -join ', '
                        excludedVia    = $ExcludedVia
                        filter         = (@($Entries.Filter | Where-Object { $_ }) | Select-Object -Unique) -join ', '
                        policyId       = [string]$Policy.id
                        CacheTimestamp = $CountRow.Timestamp
                    }
                }
            }
        }
        $Body = @($Rows | Sort-Object category, displayName)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = Get-NormalizedError -Message $_.Exception.Message }
        $StatusCode = if ($_.Exception.Message -match 'does not exist|ResourceNotFound') { [HttpStatusCode]::NotFound } else { Get-CippErrorStatusCode -ErrorRecord $_ }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
