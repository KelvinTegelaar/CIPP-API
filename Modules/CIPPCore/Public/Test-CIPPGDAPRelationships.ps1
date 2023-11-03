function Test-CIPPGDAPRelationships {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = "Access Check",
        $ExecutingUser
    )

    $GDAPissues = [System.Collections.ArrayList]@()
    try {
        #Get graph request to list all relationships.
        $Relationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'" -tenantid $ENV:TenantID -NoAuthCheck $true
        #Group relationships by tenant. The tenant information is in $relationships.customer.TenantId.
        $RelationshipsByTenant = $Relationships | Group-Object -Property { $_.customer.TenantId }
        foreach ($Tenant in $RelationshipsByTenant) {
            if ($Tenant.Group.displayName.count -le 1 -and $Tenant.Group.displayName -like 'MLT_*') {
                $GDAPissues.add([PSCustomObject]@{
                        Type         = "Error"
                        Issue        = "This tenant only has a MLT(Microsoft Led Transition) relationship. This is a read-only relationship. You must migrate this tenant to GDAP."
                        Tenant       = $Tenant.Group.customer.displayName
                        Relationship = $Tenant.Group.displayName
                    }) | Out-Null
            }
            foreach ($Group in $Tenant.Group) {
                if ("62e90394-69f5-4237-9190-012177145e10" -in $Group.accessDetails) {
                    $GDAPissues.add([PSCustomObject]@{
                            Type         = "Warning"
                            Issue        = "The relationship for $($Tenant.Group.customer.displayName) has global administrator access. This relationship is not available for auto-extend."
                            Tenant       = $Tenant.Group.customer.displayName
                            Relationship = $group.displayName
                        }) | Out-Null
                }
            }
            
        }
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
            'M365 GDAP Sharepoint Administrator',
            'M365 GDAP Authentication Policy Administrator',
            'M365 GDAP Privileged Role Administrator',
            'M365 GDAP Privileged Authentication Administrator'
        )
        $RoleAssignableGroups = $SAMUserMemberships | Where-Object { $_.isAssignableToRole }
        $NestedGroups = foreach ($Group in $RoleAssignableGroups) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($Group.id)/memberOf?`$select=id,displayName" -NoAuthCheck $true
        }
        foreach ($Group in $ExpectedGroups) {
            $GroupFound = $false
            foreach ($Membership in ($SAMUserMemberships + $NestedGroups)) {
                if ($Membership.displayName -match $Group -and (($CIPPGroupCount -gt 0 -and $Group -match 'M365 GDAP') -or $Group -notmatch 'M365 GDAP')) {
                    $GroupFound = $true
                }
            }
            if (-not $GroupFound) {
                $GDAPissues.add([PSCustomObject]@{
                        Type         = "Warning"
                        Issue        = "$($Group) cannot be found in your tenant. If you have migrated outside of CIPP this is to be expected. Please perform an access check to make sure you have the correct set of permissions."
                        Tenant       = "*Partner Tenant"
                        Relationship = "None"
                    }) | Out-Null
            }
        }

    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APINAME  -message "Failed to run GDAP check for $($TenantFilter): $($_.Exception.Message)" -Sev "Error"
    }

    return [PSCustomObject]@{
        GDAPIssues     = @($GDAPissues)
        MissingGroups  = @($MissingGroups)
        Memberships    = @($SAMUserMemberships)
        CIPPGroupCount = $CIPPGroupCount
    }
}
