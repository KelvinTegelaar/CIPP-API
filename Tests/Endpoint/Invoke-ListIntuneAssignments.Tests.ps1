# Pester tests for Invoke-ListIntuneAssignments: which cached Intune assignments apply to a user, group or device.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CippErrorStatusCode { param($ErrorRecord) if ($ErrorRecord.Exception -is [System.Management.Automation.ItemNotFoundException]) { 404 } else { 500 } }

    . (& $Find 'Get-CIPPIntuneAssignmentSources.ps1')
    . (& $Find 'Invoke-ListIntuneAssignments.ps1')

    $script:Group = { param($Id) [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $Id } }
    $script:Exclude = { param($Id) [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = $Id } }
    $script:AllUsers = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' }
    $script:AllDevices = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
    $script:Policy = {
        param($Id, $Name, $Type, $Targets, $Intent)
        [pscustomobject]@{
            id            = $Id
            displayName   = $Name
            '@odata.type' = "#microsoft.graph.$Type"
            assignments   = @(foreach ($Target in $Targets) { [pscustomobject]@{ intent = $Intent; target = $Target } })
        }
    }
    function Invoke-Lookup {
        param($Type, $Id, $Nested)
        $Request = [pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; type = $Type; id = $Id; includeNested = $Nested } }
        Invoke-ListIntuneAssignments -Request $Request
    }
}

Describe 'Invoke-ListIntuneAssignments' {
    BeforeEach {
        $script:Cache = @{}
        Mock Get-CIPPDbItem { [pscustomobject]@{ RowKey = 'IntuneDeviceConfigurations-Count'; Timestamp = [datetime]'2026-11-16' } }
        Mock New-CIPPDbRequest { $script:Cache[$Type] }
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                'users/u1/transitiveMemberOf' { @([pscustomobject]@{ id = 'g1'; displayName = 'Sales' }) }
                'devices/dobj1/transitiveMemberOf' { @([pscustomobject]@{ id = 'dg1'; displayName = 'Kiosks' }) }
                'groups/g1/transitiveMemberOf' { @([pscustomobject]@{ id = 'p1'; displayName = 'All Staff' }) }
                'users/u1\?' { [pscustomobject]@{ id = 'u1' } }
                'managedDevices/d1' { [pscustomobject]@{ id = 'd1'; azureADDeviceId = 'aad1'; userId = 'u1'; operatingSystem = 'Windows' } }
                'devices\?\$filter=deviceId eq ''aad1''' { [pscustomobject]@{ id = 'dobj1' } }
                'groups/g1\?' { [pscustomobject]@{ id = 'g1'; displayName = 'Sales' } }
                'users/missing' { throw "Resource 'missing' does not exist or one of its queried reference-property objects are not present." }
            }
        }
    }

    It 'rejects an unknown principal type' {
        (Invoke-Lookup 'computer' 'x').StatusCode | Should -Be 400
    }

    It 'returns 404 when the tenant has no Intune cache yet' {
        Mock Get-CIPPDbItem {}
        (Invoke-Lookup 'user' 'u1').StatusCode | Should -Be 404
    }

    It 'returns 404 for a principal that does not exist' {
        (Invoke-Lookup 'user' 'missing').StatusCode | Should -Be 404
    }

    It 'resolves a user through group membership and All users, honouring exclusions and filters' {
        $script:Cache['IntuneAssignmentFilters'] = @([pscustomobject]@{ id = 'f1'; displayName = 'Corporate only' })
        $Filtered = & $script:Group 'g1'
        $Filtered | Add-Member -NotePropertyName deviceAndAppManagementAssignmentFilterId -NotePropertyValue 'f1'
        $Filtered | Add-Member -NotePropertyName deviceAndAppManagementAssignmentFilterType -NotePropertyValue 'include'
        $script:Cache['IntuneConfigurationPolicies'] = @(
            & $script:Policy 'p-group' 'Via group' 'deviceManagementConfigurationPolicy' @((& $script:Group 'g1'))
            & $script:Policy 'p-excluded' 'All users but Sales' 'deviceManagementConfigurationPolicy' @($script:AllUsers, (& $script:Exclude 'g1'))
            & $script:Policy 'p-other' 'Other group' 'deviceManagementConfigurationPolicy' @((& $script:Group 'g9'))
            & $script:Policy 'p-filter' 'Filtered' 'deviceManagementConfigurationPolicy' @($Filtered)
        )
        $script:Cache['IntuneApplications'] = @(
            [pscustomobject]@{ id = 'app1'; displayName = 'Teams'; '@odata.type' = '#microsoft.graph.win32LobApp'; assignments = @(
                    [pscustomobject]@{ intent = 'required'; target = $script:AllUsers }
                    [pscustomobject]@{ intent = 'uninstall'; target = (& $script:Group 'g1') }
                )
            }
        )

        $Rows = @((Invoke-Lookup 'user' 'u1').Body)

        $Rows.displayName | Should -Not -Contain 'Other group'
        ($Rows | Where-Object displayName -EQ 'Via group').status | Should -Be 'Applies'
        ($Rows | Where-Object displayName -EQ 'Via group').assignedVia | Should -Be 'Sales'
        ($Rows | Where-Object displayName -EQ 'All users but Sales').status | Should -Be 'Excluded'
        ($Rows | Where-Object displayName -EQ 'All users but Sales').excludedVia | Should -Be 'Sales'
        ($Rows | Where-Object displayName -EQ 'Filtered').status | Should -Be 'Applies if the filter matches'
        ($Rows | Where-Object displayName -EQ 'Filtered').filter | Should -Be 'Corporate only (include)'
        @($Rows | Where-Object displayName -EQ 'Teams').intent | Sort-Object | Should -Be @('Required', 'Uninstall')
    }

    It 'resolves a device through its own groups and its primary user, and skips other platforms' {
        $script:Cache['IntuneDeviceConfigurations'] = @(
            & $script:Policy 'p-mac' 'Mac profile' 'macOSCustomConfiguration' @($script:AllDevices)
            & $script:Policy 'p-win' 'Windows profile' 'windows10GeneralConfiguration' @($script:AllDevices)
            & $script:Policy 'p-mixed' 'User include, device exclude' 'windows10GeneralConfiguration' @((& $script:Group 'g1'), (& $script:Exclude 'dg1'))
            & $script:Policy 'p-devex' 'Device include and exclude' 'windows10GeneralConfiguration' @((& $script:Group 'dg1'), (& $script:Exclude 'dg1'))
        )

        $Rows = @((Invoke-Lookup 'device' 'd1').Body)

        $Rows.displayName | Should -Not -Contain 'Mac profile'
        ($Rows | Where-Object displayName -EQ 'Windows profile').assignedVia | Should -Be 'All devices'
        ($Rows | Where-Object displayName -EQ 'User include, device exclude').status | Should -Be 'Unclear (user and device groups mixed)'
        ($Rows | Where-Object displayName -EQ 'User include, device exclude').assignedVia | Should -Be 'Sales (primary user)'
        ($Rows | Where-Object displayName -EQ 'Device include and exclude').status | Should -Be 'Excluded'
    }

    It 'includes parent groups for a group only when asked' {
        $script:Cache['IntuneConfigurationPolicies'] = @(& $script:Policy 'p-parent' 'Staff policy' 'deviceManagementConfigurationPolicy' @((& $script:Group 'p1')))

        @((Invoke-Lookup 'group' 'g1').Body) | Should -BeNullOrEmpty
        ((Invoke-Lookup 'group' 'g1' 'true').Body).assignedVia | Should -Be 'All Staff (parent group)'
    }

    It 'lists a policy cached under two types once, under the more specific label' {
        $Script = & $script:Policy 'p-linux' 'Linux script' 'deviceManagementConfigurationPolicy' @($script:AllUsers)
        $script:Cache['IntuneLinuxScripts'] = @($Script)
        $script:Cache['IntuneConfigurationPolicies'] = @($Script)

        $Rows = @((Invoke-Lookup 'user' 'u1').Body)

        $Rows.Count | Should -Be 1
        $Rows[0].category | Should -Be 'Intune Platform Script'
    }
}
