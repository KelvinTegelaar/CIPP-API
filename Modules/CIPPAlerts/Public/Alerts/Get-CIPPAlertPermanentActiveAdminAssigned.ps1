function Get-CIPPAlertPermanentActiveAdminAssigned {
    <#
    .FUNCTIONALITY
        Entrypoint
    .SYNOPSIS
        Alerts when a principal gains a permanent (no end date) active admin role assignment.
    .DESCRIPTION
        Compares the tenant's current permanent active role assignments with the set seen on the
        previous run (DeltaCompare table) and alerts on new ones that are not in the approved
        allow list. Entra ID P2 tenants are read through PIM (roleAssignmentScheduleInstances, so
        time-bound and activated assignments are excluded); other tenants through unified RBAC,
        where every assignment is permanent.

        Inputs: ApprovedAdmins - comma separated UPN prefixes, UPNs or display names that may hold
        permanent assignments (break-glass accounts); PrivilegedRolesOnly - limit to CIPP's
        privileged role list (default on).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $Approved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $PrivilegedRolesOnly = $true
        $ApprovedRaw = $null
        if ($InputValue -is [System.Collections.IDictionary] -or $InputValue -is [pscustomobject]) {
            $ApprovedRaw = $InputValue.ApprovedAdmins
            if ($null -ne $InputValue.PrivilegedRolesOnly) { $PrivilegedRolesOnly = [bool]($InputValue.PrivilegedRolesOnly -eq $true -or "$($InputValue.PrivilegedRolesOnly)" -eq 'true') }
        } elseif ($null -ne $InputValue) {
            $ApprovedRaw = $InputValue
        }
        foreach ($Entry in @("$ApprovedRaw" -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { $null = $Approved.Add($Entry) }

        $Rows = @(Get-CIPPPIMRoleAssignments -TenantFilter $TenantFilter | Where-Object { $_.AssignmentType -eq 'Permanent' -and $_.MemberType -ne 'Group' })
        if ($PrivilegedRolesOnly) {
            $Rows = @($Rows | Where-Object { $_.IsPrivilegedRole })
        }

        $Current = @($Rows | ForEach-Object {
                [PSCustomObject]@{
                    Key               = "$($_.PrincipalId)|$($_.RoleDefinitionId)|$($_.DirectoryScopeId)"
                    PrincipalId       = $_.PrincipalId
                    DisplayName       = $_.PrincipalDisplayName
                    UserPrincipalName = $_.PrincipalUserPrincipalName
                    PrincipalType     = $_.PrincipalType
                    Role              = $_.RoleDisplayName
                    Scope             = $_.Scope
                }
            })

        $DeltaTable = Get-CIPPTable -Table DeltaCompare
        $Filter = "PartitionKey eq 'PermanentAdminDelta' and RowKey eq '{0}'" -f $TenantFilter
        $Previous = (Get-CIPPAzDataTableEntity @DeltaTable -Filter $Filter).delta | ConvertFrom-Json -ErrorAction SilentlyContinue
        $PreviousKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Previous.Key | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)

        Add-CIPPAzDataTableEntity @DeltaTable -Entity @{
            PartitionKey = 'PermanentAdminDelta'
            RowKey       = [string]$TenantFilter
            delta        = "$(ConvertTo-Json -InputObject @($Current) -Depth 5 -Compress)"
        } -Force

        # First run only seeds the baseline; alerting on everything that already existed would be noise.
        if ($null -eq $Previous) { return }

        $AlertData = foreach ($Item in $Current) {
            if ($PreviousKeys.Contains($Item.Key)) { continue }
            $Candidates = @($Item.PrincipalId, $Item.DisplayName, $Item.UserPrincipalName)
            if ($Item.UserPrincipalName) { $Candidates += ($Item.UserPrincipalName -split '@')[0] }
            $IsApproved = $false
            foreach ($Candidate in $Candidates) { if ($Candidate -and $Approved.Contains("$Candidate")) { $IsApproved = $true; break } }
            if ($IsApproved) { continue }
            $Label = @($Item.UserPrincipalName, $Item.DisplayName, $Item.PrincipalId) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
            [PSCustomObject]@{
                Message           = "$Label was given a permanent (no end date) active assignment to the $($Item.Role) role."
                UserPrincipalName = $Item.UserPrincipalName
                DisplayName       = $Item.DisplayName
                PrincipalType     = $Item.PrincipalType
                Role              = $Item.Role
                Scope             = $Item.Scope
                Tenant            = $TenantFilter
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not check permanent admin assignments for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
