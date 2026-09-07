function New-CIPPGDAPRoleMapping {
    <#
    .SYNOPSIS
    Creates or reuses the partner tenant security groups backing a set of GDAP roles

    .DESCRIPTION
    For each role a group named 'M365 GDAP <RoleName>' (optionally suffixed) is reused when it
    already exists in the partner tenant, otherwise created. The resulting mappings are upserted
    into the GDAPRoles table and returned for template writes.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $Roles,
        [string]$CustomSuffix
    )

    $Table = Get-CIPPTable -TableName 'GDAPRoles'

    $Results = [System.Collections.Generic.List[string]]::new()
    $Requests = [System.Collections.Generic.List[object]]::new()
    $ExistingGroups = New-GraphGetRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/groups' -tenantid $env:TenantID -AsApp $true

    $ExistingRoleMappings = foreach ($Role in $Roles) {
        $RoleName = $Role.label ?? $Role.Name
        $Value = $Role.value ?? $Role.ObjectId

        if ($CustomSuffix) {
            $GroupName = "M365 GDAP $($RoleName) - $CustomSuffix"
            $MailNickname = "M365GDAP$(($RoleName).replace(' ',''))$($CustomSuffix.replace(' ',''))"
        } else {
            $GroupName = "M365 GDAP $($RoleName)"
            $MailNickname = "M365GDAP$(($RoleName).replace(' ',''))"
        }

        if ($GroupName -in $ExistingGroups.displayName) {
            @{
                PartitionKey     = 'Roles'
                RowKey           = ($ExistingGroups | Where-Object -Property displayName -EQ $GroupName | Select-Object -First 1).id
                RoleName         = $RoleName
                GroupName        = $GroupName
                GroupId          = ($ExistingGroups | Where-Object -Property displayName -EQ $GroupName | Select-Object -First 1).id
                roleDefinitionId = $Value
            }
            $Results.Add("$GroupName already exists")
        } else {
            $Requests.Add(@{
                    id      = $Value
                    url     = '/groups'
                    method  = 'POST'
                    headers = @{
                        'Content-Type' = 'application/json'
                    }
                    body    = @{
                        displayName     = $GroupName
                        description     = "This group is used to manage M365 partner tenants at the $($RoleName) level."
                        securityEnabled = $true
                        mailEnabled     = $false
                        mailNickname    = $MailNickname
                    }
                })
        }
    }

    if ($ExistingRoleMappings) {
        Add-CIPPAzDataTableEntity @Table -Entity $ExistingRoleMappings -Force
    }

    if ($Requests) {
        $ReturnedData = New-GraphBulkRequest -Requests $Requests -tenantid $env:TenantID -NoAuthCheck $True -asapp $true
        $NewRoleMappings = foreach ($Return in $ReturnedData) {
            if ($Return.body.error) {
                $Results.Add("Could not create GDAP group: $($Return.body.error.message)")
            } else {
                $GroupName = $Return.body.displayName
                @{
                    PartitionKey     = 'Roles'
                    RowKey           = $Return.body.id
                    RoleName         = $Return.body.displayName -replace '^M365 GDAP ', '' -replace " - $CustomSuffix$", ''
                    GroupName        = $Return.body.displayName
                    GroupId          = $Return.body.id
                    roleDefinitionId = $Return.id
                }
                $Results.Add("Created $($GroupName)")
            }
        }
        Write-Information ($NewRoleMappings | ConvertTo-Json -Depth 10 -Compress)
        if ($NewRoleMappings) {
            Add-CIPPAzDataTableEntity @Table -Entity $NewRoleMappings -Force
        }
    }

    $RoleMappings = [System.Collections.Generic.List[object]]::new()
    foreach ($Mapping in @($ExistingRoleMappings) + @($NewRoleMappings)) {
        if (!$Mapping) { continue }
        $RoleMappings.Add([PSCustomObject]@{
                RoleName         = $Mapping.RoleName
                GroupName        = $Mapping.GroupName
                GroupId          = $Mapping.GroupId
                roleDefinitionId = $Mapping.roleDefinitionId
            })
    }

    return [PSCustomObject]@{
        RoleMappings = $RoleMappings
        Results      = $Results
    }
}
