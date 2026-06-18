function Test-CIPPGDAPGroupMappings {
    <#
    .SYNOPSIS
    Validate (and optionally repair) the security groups referenced by GDAP role mappings in the partner tenant.

    .DESCRIPTION
    GDAP access assignments link a security group in the partner (CSP) tenant to a unified role. If the GroupId
    stored in a role mapping no longer points at a real group, Graph rejects the access assignment with an
    "access container does not exist" error. This helper fetches the partner tenant security groups once and, for
    each mapping:

      1. GroupId still resolves to a group  -> kept as-is (Valid).
      2. GroupId is gone but a group with the expected name ("M365 GDAP <RoleName>" / the stored GroupName) exists
         -> the mapping is resolved to that group's id (Stale - the stored id was stale).
      3. Neither exists -> recreated via the standard "M365 GDAP" group when -CreateMissing is set (Created),
         otherwise reported as Missing with an actionable message instead of letting the raw Graph error surface.

    Corrections/creations can be persisted back to the GDAPRoles table (-WriteBack), a GDAP role template
    (-TemplateId) and/or a GDAP invite entry (-InviteRowKey) so subsequent syncs use the corrected GroupIds.

    Returns the corrected mapping set, a per-mapping result list, the still-missing groups and an overall Valid flag.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $RoleMappings,
        $PartnerGroups,
        [switch]$CreateMissing,
        [switch]$WriteBack,
        $TemplateId,
        $InviteRowKey,
        $APIName = 'GDAP Group Check',
        $Headers
    )

    # Normalise input into a mutable copy so we never mutate the caller's objects in place
    $Mappings = @(foreach ($Mapping in $RoleMappings) {
            [PSCustomObject]@{
                RoleName         = $Mapping.RoleName
                GroupName        = $Mapping.GroupName
                GroupId          = $Mapping.GroupId
                roleDefinitionId = $Mapping.roleDefinitionId
            }
        })

    if (($Mappings | Measure-Object).Count -eq 0) {
        return [PSCustomObject]@{
            RoleMappings  = @()
            Results       = @()
            Valid         = $true
            MissingGroups = @()
        }
    }

    # Fetch partner tenant security groups once if the caller did not already hand them to us
    if (-not $PartnerGroups) {
        $PartnerGroups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$filter=securityEnabled eq true&$select=id,displayName&$top=999' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $MissingGroups = [System.Collections.Generic.List[object]]::new()
    $Corrections = [System.Collections.Generic.List[object]]::new()
    $CreateRequests = [System.Collections.Generic.List[object]]::new()
    $CreateLookup = @{}

    foreach ($Mapping in $Mappings) {
        $ExpectedName = if ($Mapping.GroupName) { $Mapping.GroupName } else { "M365 GDAP $($Mapping.RoleName)" }

        # 1. GroupId still valid in the partner tenant
        if ($Mapping.GroupId -and $PartnerGroups.id -contains $Mapping.GroupId) {
            $Results.Add([PSCustomObject]@{
                    RoleName   = $Mapping.RoleName
                    GroupName  = $ExpectedName
                    GroupId    = $Mapping.GroupId
                    Status     = 'Valid'
                    Message    = ''
                    OldGroupId = $null
                })
            continue
        }

        # 2. Remap to an existing group that matches the expected name
        $MatchByName = $PartnerGroups | Where-Object { $_.displayName -eq $ExpectedName } | Select-Object -First 1
        if ($MatchByName) {
            $OldGroupId = $Mapping.GroupId
            $Mapping.GroupId = $MatchByName.id
            $Mapping.GroupName = $MatchByName.displayName
            $Results.Add([PSCustomObject]@{
                    RoleName   = $Mapping.RoleName
                    GroupName  = $MatchByName.displayName
                    GroupId    = $MatchByName.id
                    Status     = 'Stale'
                    Message    = "Group '$ExpectedName' exists but the stored group id '$OldGroupId' is stale; the correct group id is '$($MatchByName.id)'"
                    OldGroupId = $OldGroupId
                })
            $Corrections.Add([PSCustomObject]@{ OldGroupId = $OldGroupId; Mapping = $Mapping })
            continue
        }

        # 3. Neither the id nor a matching group exists - recreate or report as missing
        if ($CreateMissing) {
            $MailNickname = 'M365GDAP{0}' -f (($ExpectedName -replace '^M365 GDAP ', '') -replace '[^a-zA-Z0-9]', '')
            $RequestId = "create-$($Mapping.roleDefinitionId)"
            $CreateLookup[$RequestId] = $Mapping
            $CreateRequests.Add(@{
                    id      = $RequestId
                    url     = '/groups'
                    method  = 'POST'
                    headers = @{ 'Content-Type' = 'application/json' }
                    body    = @{
                        displayName     = $ExpectedName
                        description     = "This group is used to manage M365 partner tenants at the $($Mapping.RoleName) level."
                        securityEnabled = $true
                        mailEnabled     = $false
                        mailNickname    = $MailNickname
                    }
                })
        } else {
            $Results.Add([PSCustomObject]@{
                    RoleName   = $Mapping.RoleName
                    GroupName  = $ExpectedName
                    GroupId    = $Mapping.GroupId
                    Status     = 'Missing'
                    Message    = "Group '$ExpectedName' is missing in the partner tenant, recreate the GDAP roles before retrying"
                    OldGroupId = $Mapping.GroupId
                })
            $MissingGroups.Add([PSCustomObject]@{ Name = $ExpectedName; Type = 'Role Mapping' })
        }
    }

    # Execute any group recreations and fold the new ids back into the mappings
    if ($CreateRequests.Count -gt 0 -and $PSCmdlet.ShouldProcess('Partner tenant', "Recreate $($CreateRequests.Count) missing GDAP group(s)")) {
        $CreateResults = New-GraphBulkRequest -Requests @($CreateRequests) -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
        foreach ($Result in $CreateResults) {
            $Mapping = $CreateLookup[$Result.id]
            if (-not $Mapping) { continue }
            $ExpectedName = if ($Mapping.GroupName) { $Mapping.GroupName } else { "M365 GDAP $($Mapping.RoleName)" }
            if ($Result.body.error) {
                $Results.Add([PSCustomObject]@{
                        RoleName   = $Mapping.RoleName
                        GroupName  = $ExpectedName
                        GroupId    = $Mapping.GroupId
                        Status     = 'Missing'
                        Message    = "Failed to recreate group '$ExpectedName': $($Result.body.error.message)"
                        OldGroupId = $Mapping.GroupId
                    })
                $MissingGroups.Add([PSCustomObject]@{ Name = $ExpectedName; Type = 'Role Mapping' })
            } else {
                $OldGroupId = $Mapping.GroupId
                $Mapping.GroupId = $Result.body.id
                $Mapping.GroupName = $Result.body.displayName
                $Results.Add([PSCustomObject]@{
                        RoleName   = $Mapping.RoleName
                        GroupName  = $Result.body.displayName
                        GroupId    = $Result.body.id
                        Status     = 'Created'
                        Message    = "Recreated missing group '$($Result.body.displayName)' as '$($Result.body.id)'"
                        OldGroupId = $OldGroupId
                    })
                $Corrections.Add([PSCustomObject]@{ OldGroupId = $OldGroupId; Mapping = $Mapping })
            }
        }
    }

    # Persist corrected/created GroupIds back to the GDAPRoles registry (RowKey is the GroupId)
    if ($WriteBack -and $Corrections.Count -gt 0) {
        try {
            $RolesTable = Get-CIPPTable -TableName 'GDAPRoles'
            foreach ($Correction in $Corrections) {
                $Mapping = $Correction.Mapping
                if ($Correction.OldGroupId -and $Correction.OldGroupId -ne $Mapping.GroupId) {
                    $OldEntity = Get-CIPPAzDataTableEntity @RolesTable -Filter "PartitionKey eq 'Roles' and RowKey eq '$($Correction.OldGroupId)'"
                    if ($OldEntity) {
                        Remove-AzDataTableEntity -Force @RolesTable -Entity $OldEntity
                    }
                }
                Add-CIPPAzDataTableEntity @RolesTable -Entity @{
                    PartitionKey     = 'Roles'
                    RowKey           = [string]$Mapping.GroupId
                    RoleName         = [string]$Mapping.RoleName
                    GroupName        = [string]$Mapping.GroupName
                    GroupId          = [string]$Mapping.GroupId
                    roleDefinitionId = [string]$Mapping.roleDefinitionId
                } -Force
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to write corrected GDAP group mappings to GDAPRoles: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    # Optionally push the corrected mappings back to the source template/invite
    if ($Corrections.Count -gt 0) {
        if ($TemplateId) {
            try {
                Add-CIPPGDAPRoleTemplate -TemplateId $TemplateId -RoleMappings ($Mappings | Select-Object -Property RoleName, GroupName, GroupId, roleDefinitionId) -Overwrite
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to write corrected GDAP group mappings to template '$TemplateId': $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
        }
        if ($InviteRowKey) {
            try {
                $InviteTable = Get-CIPPTable -TableName 'GDAPInvites'
                $Invite = Get-CIPPAzDataTableEntity @InviteTable -Filter "RowKey eq '$InviteRowKey'"
                if ($Invite) {
                    $Invite.RoleMappings = [string](@($Mappings | Select-Object -Property RoleName, GroupName, GroupId, roleDefinitionId) | ConvertTo-Json -Depth 10 -Compress)
                    Add-CIPPAzDataTableEntity @InviteTable -Entity $Invite -Force
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to write corrected GDAP group mappings to invite '$InviteRowKey': $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
        }
    }

    return [PSCustomObject]@{
        RoleMappings  = @($Mappings)
        Results       = @($Results)
        Valid         = (($MissingGroups | Measure-Object).Count -eq 0)
        MissingGroups = @($MissingGroups)
    }
}
