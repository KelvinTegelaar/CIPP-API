function Save-CIPPOffboardingSnapshot {
    <#
    .SYNOPSIS
        Records a user's licences, groups, admin roles and manager before offboarding strips them.

    .DESCRIPTION
        Writes one row per user to the OffboardingSnapshots table (PartitionKey = tenant customerId,
        RowKey = user object id) so the onboarding scan can offer to put a returning user back the
        way they were. Licences are the directly assigned ones only: a licence inherited from a
        group comes back with the group.

        A snapshot with no groups and no licences never replaces an existing row, so a second
        offboarding of an already stripped account keeps the useful one.

        Never throws: a failure is logged as a warning and the offboarding carries on.

    .OUTPUTS
        $true when a row was written, otherwise $false.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$UserID,

        [string]$Username,
        $APIName = 'Offboarding snapshot',
        $Headers
    )

    try {
        $Requests = @(
            @{ id = 'user'; method = 'GET'; url = "users/$($UserID)?`$select=id,userPrincipalName,displayName,onPremisesImmutableId,assignedLicenses,licenseAssignmentStates" }
            @{ id = 'groups'; method = 'GET'; url = "users/$UserID/memberOf/microsoft.graph.group?`$select=id,displayName,groupTypes,mailEnabled,securityEnabled&`$top=999" }
            @{ id = 'manager'; method = 'GET'; url = "users/$UserID/manager?`$select=id,userPrincipalName,displayName" }
            @{ id = 'skus'; method = 'GET'; url = 'subscribedSkus?$select=skuId,skuPartNumber' }
        )
        $Bulk = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $Requests)
        $UserResult = $Bulk | Where-Object { $_.id -eq 'user' }
        $GroupResult = $Bulk | Where-Object { $_.id -eq 'groups' }
        # A failed read must not be saved as "had nothing".
        if ($UserResult.status -ne 200 -or $GroupResult.status -ne 200) {
            throw "Could not read the user's licences and groups (user: HTTP $($UserResult.status), groups: HTTP $($GroupResult.status))."
        }
        $User = $UserResult.body
        $Skus = @(($Bulk | Where-Object { $_.id -eq 'skus' }).body.value)
        $ManagerResult = $Bulk | Where-Object { $_.id -eq 'manager' }

        # A SKU with assignment states that all point at a group is inherited, not direct.
        $SkuIds = @(foreach ($SkuId in @($User.assignedLicenses.skuId | Where-Object { $_ } | Select-Object -Unique)) {
                $States = @($User.licenseAssignmentStates | Where-Object { $_.skuId -eq $SkuId })
                if ($States.Count -eq 0 -or @($States | Where-Object { -not $_.assignedByGroup }).Count -gt 0) { $SkuId }
            })
        $SkuNames = if ($SkuIds.Count -gt 0) { @(Get-CIPPLicenseSkuName -SkuIds $SkuIds -TenantFilter $TenantFilter) } else { @() }
        $Licenses = @(foreach ($SkuId in $SkuIds) {
                $PartNumber = ($Skus | Where-Object { $_.skuId -eq $SkuId } | Select-Object -First 1).skuPartNumber
                $Name = ($SkuNames | Where-Object { $_.skuId -eq $SkuId } | Select-Object -First 1).displayName
                [pscustomobject]@{ skuId = $SkuId; skuPartNumber = $PartNumber; displayName = ($Name ?? $PartNumber ?? $SkuId) }
            })

        $Groups = @(foreach ($Group in @($GroupResult.body.value | Where-Object { $_.id })) {
                # Same classification as Get-CIPPGroupType.
                $GroupType = if ($Group.groupTypes -contains 'Unified') { 'Microsoft 365' }
                elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'Mail-Enabled Security' }
                elseif ($Group.mailEnabled) { 'Distribution List' }
                else { 'Security' }
                [pscustomobject]@{ id = $Group.id; displayName = $Group.displayName; groupType = $GroupType }
            })

        $Manager = if ($ManagerResult.status -eq 200 -and $ManagerResult.body.id) {
            [pscustomobject]@{ id = $ManagerResult.body.id; userPrincipalName = $ManagerResult.body.userPrincipalName; displayName = $ManagerResult.body.displayName }
        }

        # Roles are a separate read; losing them must not lose the licences and groups.
        $Roles = @()
        try {
            $Roles = @(Get-CIPPPIMRoleAssignments -TenantFilter $TenantFilter -PrincipalId $User.id | Where-Object { $_.RoleDefinitionId -and $_.MemberType -ne 'Group' } |
                    Sort-Object -Property RoleDefinitionId -Unique | ForEach-Object { [pscustomobject]@{ id = $_.RoleDefinitionId; displayName = ($_.RoleDisplayName ?? $_.RoleDefinitionId) } })
        } catch {
            Write-Information "Offboarding snapshot: could not read role assignments for $($User.userPrincipalName): $($_.Exception.Message)"
        }

        $CustomerId = @(Get-Tenants -TenantFilter $TenantFilter)[0].customerId
        if (-not $CustomerId) { throw "Could not resolve the tenant id for $TenantFilter." }
        $Table = Get-CIPPTable -TableName 'OffboardingSnapshots'

        if ($Groups.Count -eq 0 -and $Licenses.Count -eq 0) {
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$(ConvertTo-CIPPODataFilterValue -Value $CustomerId)' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $User.id)'" -Property @('PartitionKey', 'RowKey')
            if ($Existing) {
                Write-Information "Offboarding snapshot: $($User.userPrincipalName) has no groups or licences now; keeping the existing snapshot."
                return $false
            }
        }

        $Entity = @{
            PartitionKey      = [string]$CustomerId
            RowKey            = [string]$User.id
            UserPrincipalName = [string]$User.userPrincipalName
            DisplayName       = [string]$User.displayName
            OffboardedAt      = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            Snapshot          = [string](ConvertTo-Json -Compress -Depth 5 -InputObject @{ Licenses = $Licenses; Groups = $Groups; Roles = $Roles; Manager = $Manager; HadImmutableId = [bool]$User.onPremisesImmutableId })
        }
        # Add-CIPPAzDataTableEntity splits a Snapshot over the property size limit; Get-CIPPAzDataTableEntity joins it again.
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        return $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not save the offboarding snapshot for $($Username ? $Username : $UserID). The offboarding continues, but onboarding will not be able to offer the previous licences and groups: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
        return $false
    }
}
