function Test-CIPPGDAPRelationships {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Access Check',
        $Headers
    )

    $GDAPissues = [System.Collections.Generic.List[object]]@()
    $MissingGroups = [System.Collections.Generic.List[object]]@()
    $RoleMappingResults = [System.Collections.Generic.List[object]]@()
    try {
        #Get graph request to list all relationships.
        $Relationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'" -tenantid $env:TenantID -NoAuthCheck $true
        #Group relationships by tenant. The tenant information is in $relationships.customer.TenantId.
        $RelationshipsByTenant = $Relationships | Group-Object -Property { $_.customer.TenantId }
        foreach ($Tenant in $RelationshipsByTenant) {
            if ($Tenant.Group.displayName.count -le 1 -and $Tenant.Group.displayName -like 'MLT_*') {
                $GDAPissues.add([PSCustomObject]@{
                        Type         = 'Error'
                        Issue        = 'This tenant only has a MLT(Microsoft Led Transition) relationship. This is a read-only relationship. You must migrate this tenant to GDAP.'
                        Tenant       = [string]$Tenant.Group.customer.displayName
                        Relationship = [string]$Tenant.Group.displayName
                        Link         = 'https://docs.cipp.app/setup/installation/gdap-invite-wizard'
                    }) | Out-Null
            }
            foreach ($Group in $Tenant.Group) {
                if ('62e90394-69f5-4237-9190-012177145e10' -in $Group.accessDetails.unifiedRoles.roleDefinitionId) {
                    $GDAPissues.add([PSCustomObject]@{
                            Type         = 'Warning'
                            Issue        = 'The relationship has global administrator access. Auto-Extend is not available.'
                            Tenant       = [string]$Group.customer.displayName
                            Relationship = [string]$Group.displayName
                            Link         = 'https://docs.cipp.app/setup/maintaining-cipp/recommended-roles'

                        }) | Out-Null
                }
            }

        }
        $me = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/me?$select=UserPrincipalName' -NoAuthCheck $true).UserPrincipalName
        $CIPPGroupCount = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/`$count?`$filter=startsWith(displayName,'M365 GDAP')" -NoAuthCheck $true -ComplexFilter
        $SAMUserMemberships = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/me/memberOf?$select=id,displayName,isAssignableToRole' -NoAuthCheck $true
        $ExpectedGroups = @(
            'AdminAgents',
            'M365 GDAP Application Administrator',
            'M365 GDAP User Administrator',
            'M365 GDAP Intune Administrator',
            'M365 GDAP Exchange Administrator',
            'M365 GDAP Security Administrator',
            'M365 GDAP Cloud App Security Administrator',
            'M365 GDAP Cloud Device Administrator',
            'M365 GDAP Teams Administrator',
            'M365 GDAP SharePoint Administrator',
            'M365 GDAP Authentication Policy Administrator',
            'M365 GDAP Privileged Role Administrator',
            'M365 GDAP Privileged Authentication Administrator',
            'M365 GDAP Billing Administrator',
            'M365 GDAP Global Reader',
            'M365 GDAP Domain Name Administrator'
        )
        $RoleAssignableGroups = $SAMUserMemberships | Where-Object { $_.isAssignableToRole }
        $NestedGroups = [System.Collections.Generic.List[object]]::new()
        foreach ($RoleGroup in $RoleAssignableGroups) {
            Write-Information "Getting nested group memberships for $($RoleGroup.displayName)"
            $NestedGroups.AddRange(@(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($RoleGroup.id)/memberOf?`$select=id,displayName" -NoAuthCheck $true))
        }
        foreach ($ExpectedGroup in $ExpectedGroups) {
            $GroupFound = $false
            foreach ($Membership in ($SAMUserMemberships + $NestedGroups)) {
                if ($Membership.displayName -match $ExpectedGroup) {
                    Write-Information "Found $ExpectedGroup in group memberships"
                    $GroupFound = $true
                }
            }
            if (-not $GroupFound) {
                if ($ExpectedGroup -eq 'AdminAgents') { $Type = 'Error' } else { $Type = 'Warning' }
                $GDAPissues.add([PSCustomObject]@{
                        Type         = $Type
                        Issue        = "$($ExpectedGroup) is not assigned to the SAM user $me. If you have migrated outside of CIPP this is to be expected. Please perform an access check to make sure you have the correct set of permissions."
                        Tenant       = '*Partner Tenant'
                        Relationship = 'None'
                        Link         = 'https://docs.cipp.app/setup/maintaining-cipp/recommended-roles'

                    }) | Out-Null
                $MissingGroups.Add([PSCustomObject]@{
                        Name = $ExpectedGroup
                        Type = 'SAM User Membership'
                    }) | Out-Null
            }
        }
        if ($CIPPGroupCount -lt 15) {
            $GDAPissues.add([PSCustomObject]@{
                    Type         = 'Warning'
                    Issue        = "We only found $($CIPPGroupCount) of the 15 required groups. If you have migrated outside of CIPP this is to be expected. Please perform an access check to make sure you have the correct set of permissions."
                    Tenant       = '*Partner Tenant'
                    Relationship = 'None'
                    Link         = 'https://docs.cipp.app/setup/maintaining-cipp/recommended-roles'

                }) | Out-Null
        }

        # GDAP invites/onboarding call the Partner Center API with delegated auth, so obtain a token for that
        # audience and confirm the user_impersonation scope is in it, the same way the access permissions check
        # inspects the Graph token. The token request itself fails with AADSTS65001 when the scope was never
        # consented for the SAM app in the partner tenant.
        try {
            $PartnerCenterToken = Get-GraphToken -tenantid $env:TenantID -scope 'https://api.partnercenter.microsoft.com/.default' -returnRefresh $true -SkipCache $true
            $PartnerCenterTokenDetails = Read-JwtAccessDetails -Token $PartnerCenterToken.access_token
            if ($PartnerCenterTokenDetails.Scope -notcontains 'user_impersonation') {
                $GDAPissues.add([PSCustomObject]@{
                        Type         = 'Error'
                        Issue        = "The Partner Center API token for the SAM application does not contain the 'user_impersonation' scope. This permission is part of the CIPP defaults, so this usually indicates a wider problem with the SAM application's permissions. Run the Permissions check and repair permissions, then refresh this check. GDAP invites and tenant onboarding will fail until this is resolved."
                        Tenant       = '*Partner Tenant'
                        Relationship = 'None'
                        Link         = 'https://docs.cipp.app/setup/installation/permissions'
                    }) | Out-Null
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            # The Partner Center consent is part of the CIPP defaults, so a missing grant rarely happens in
            # isolation - a failure here usually points at a wider SAM application or token problem.
            if ($ErrorMessage.NormalizedError -match 'AADSTS65001|consent') {
                $Issue = "The Partner Center API 'user_impersonation' delegated permission is not consented for the SAM application. This permission is part of the CIPP defaults, so this usually indicates a wider problem with the SAM application's permissions. Run the Permissions check and repair permissions, then refresh this check. GDAP invites and tenant onboarding will fail until this is resolved."
            } else {
                $Issue = "Could not obtain a Partner Center API token: $($ErrorMessage.NormalizedError). This usually indicates a problem with the SAM application or its tokens rather than the Partner Center permission itself - run the Permissions check for details. GDAP invites and tenant onboarding will fail until this is resolved."
            }
            $GDAPissues.add([PSCustomObject]@{
                    Type         = 'Error'
                    Issue        = $Issue
                    Tenant       = '*Partner Tenant'
                    Relationship = 'None'
                    Link         = 'https://docs.cipp.app/setup/installation/permissions'
                }) | Out-Null
        }

        # Validate that every stored GDAP role mapping still points at a group that exists in the partner tenant.
        # A drifted/deleted GroupId is what causes the "access container does not exist" error during onboarding.
        # Problems are added to GDAPIssues as errors (so they count toward the Errors total) and tagged with
        # Category 'RoleMapping' so the frontend can keep them out of the GDAP Issues table (the detail/repair view
        # lives in RoleMappingResults).
        $RolesTable = Get-CIPPTable -TableName 'GDAPRoles'
        $StoredRoleMappings = Get-CIPPAzDataTableEntity @RolesTable -Filter "PartitionKey eq 'Roles'"
        if (($StoredRoleMappings | Measure-Object).Count -gt 0) {
            # Read-only check: do not write back or recreate groups from the access check card
            $MappingCheck = Test-CIPPGDAPGroupMappings -RoleMappings $StoredRoleMappings -Headers $Headers
            $RoleMappingResults.AddRange(@($MappingCheck.Results))
            foreach ($MappingResult in $MappingCheck.Results) {
                if ($MappingResult.Status -eq 'Missing') {
                    $GDAPissues.add([PSCustomObject]@{
                            Type         = 'Error'
                            Category     = 'RoleMapping'
                            Issue        = "The GDAP role mapping for '$($MappingResult.GroupName)' references a security group that no longer exists in the partner tenant. Onboarding group mapping will fail until the GDAP roles are recreated."
                            Tenant       = '*Partner Tenant'
                            Relationship = 'None'
                            Link         = 'https://docs.cipp.app/setup/maintaining-cipp/recommended-roles'
                        }) | Out-Null
                } elseif ($MappingResult.Status -eq 'Stale') {
                    $GDAPissues.add([PSCustomObject]@{
                            Type         = 'Error'
                            Category     = 'RoleMapping'
                            Issue        = "The GDAP role mapping for '$($MappingResult.GroupName)' points at a stale group id but a matching group still exists. Use 'Repair Role Mappings' under Details to correct the stored group id."
                            Tenant       = '*Partner Tenant'
                            Relationship = 'None'
                            Link         = 'https://docs.cipp.app/setup/maintaining-cipp/recommended-roles'
                        }) | Out-Null
                }
            }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APINAME -message "Failed to run GDAP check for $($TenantFilter): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    $GDAPRelationships = [PSCustomObject]@{
        GDAPIssues         = @($GDAPissues)
        MissingGroups      = @($MissingGroups)
        Memberships        = @($SAMUserMemberships + $NestedGroups)
        CIPPGroupCount     = $CIPPGroupCount
        RoleMappingResults = @($RoleMappingResults)
    }

    $Table = Get-CIPPTable -TableName AccessChecks
    $Data = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AccessCheck' and RowKey eq 'GDAPRelationships'"

    if ($Data) {
        $Data.Data = [string](ConvertTo-Json -InputObject $GDAPRelationships -Depth 10 -Compress)
    } else {
        $Data = @{
            PartitionKey = 'AccessCheck'
            RowKey       = 'GDAPRelationships'
            Data         = [string](ConvertTo-Json -InputObject $GDAPRelationships -Depth 10 -Compress)
        }
    }
    try {
        Add-CIPPAzDataTableEntity @Table -Entity $Data -Force
    } catch {}

    return $GDAPRelationships
}
