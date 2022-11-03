# Input bindings are passed in via param block.
param( $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"
$TenantFilter = $env:TenantID
$Groups = $QueueItem.gdapRoles
$tenant = $queueitem.tenant
$Table = Get-CIPPTable -TableName 'gdapmigration'
Write-Host ($QueueItem.tenant | ConvertTo-Json -Compress)
$logRequest = @{
    status       = 'Started migration'
    tenant       = "$($tenant.displayName)"
    RowKey       = "$($tenant.customerId)"
    PartitionKey = 'alert'
    startAt      = "$((Get-Date).ToString('s'))"
}

Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null

$RoleMappings = foreach ($group in $Groups) {
    $randomSleep = Get-Random -Minimum 10 -Maximum 500
    Start-Sleep -Milliseconds $randomSleep
    $ExistingGroups = New-GraphGetRequest -NoAuthCheck $True -asApp $true -uri "https://graph.microsoft.com/beta/groups" -tenantid $TenantFilter
    try {
        if ("M365 GDAP $($Group.Name)" -in $ExistingGroups.displayName) {
            @{
                GroupId          = ($ExistingGroups | Where-Object -Property displayName -EQ "M365 GDAP $($Group.Name)").id
                roleDefinitionId = $group.ObjectId
            }
        }
        else {
            $BodyToship = [pscustomobject] @{"displayName" = "M365 GDAP $($Group.Name)"; "description" = "This group is used to manage M365 partner tenants at the $($group.name) level."; securityEnabled = $true; mailEnabled = $false; mailNickname = "M365GDAP$(($Group.Name).replace(' ',''))" } | ConvertTo-Json
            $GraphRequest = New-GraphPostRequest -NoAuthCheck $True -AsApp $true -uri "https://graph.microsoft.com/beta/groups" -tenantid $env:TenantID -type POST -body $BodyToship  -verbose
            @{
                GroupId          = $GraphRequest.Id 
                roleDefinitionId = $group.ObjectId
            }
        }
    }
    catch {
        $LogRequest['status'] = "Migration Failed. could not create GDAP group M365 GDAP $($Group.Name): $($_.Exception.Message)"
        Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null
        exit 1
    }
}

if ($RoleMappings) {
    $LogRequest['status'] = "Step 2: Groups created, creating new GDAP relationship."
    Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null
}
else {
    $LogRequest['status'] = "Migration failed at Step 2: No role mappings created."
    Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null
    exit 1
}
try {
    $JSONBody = @{
        "displayName"   = "$((New-Guid).GUID)"
        "partner"       = @{
            "tenantId" = "$env:tenantid"
        }

        "customer"      = @{
            "displayName" = "$($tenant.displayName)"
            "tenantId"    = "$($tenant.customerId)"
        }
        "accessDetails" = @{
            "unifiedRoles" = @($RoleMappings | Select-Object roleDefinitionId)
        }
        "duration"      = "P730D"
    } | ConvertTo-Json -Depth 5 -Compress
    Write-Host  $JSONBody
    $MigrateRequest = New-GraphPostRequest -NoAuthCheck $True -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/migrate" -type POST -body $JSONBody -verbose -tenantid $env:TenantID -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
    Start-Sleep -Milliseconds 100
    do {
        $CheckActive = New-GraphGetRequest -NoAuthCheck $True -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/$($MigrateRequest.id)" -tenantid $env:TenantID -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
        Start-Sleep -Milliseconds 200
    } until ($CheckActive.status -eq "Active")
}
catch {
    $LogRequest['status'] = "Migration Failed. Could not create relationship: $($_.Exception.Message)"
    Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null
}


if ($CheckActive.status -eq "Active") {
    $LogRequest['status'] = "Step 3: GDAP Relationship active. Mapping groups."
    Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null
    foreach ($role in $RoleMappings) {
        try {
            $Mappingbody = ConvertTo-Json -Depth 10 -InputObject @{
                "accessContainer" = @{ 
                    "accessContainerId"   = "$($Role.GroupId)"
                    "accessContainerType" = "securityGroup" 
                }
                "accessDetails"   = @{ 
                    "unifiedRoles" = @(@{ 
                            "roleDefinitionId" = "$($Role.roleDefinitionId)" 
                        }) 
                }
            }
            $RoleActiveID = New-GraphPostRequest -NoAuthCheck $True -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/$($MigrateRequest.id)/accessAssignments" -tenantid $env:TenantID -type POST -body $MappingBody  -verbose  -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
            Start-Sleep -Milliseconds 400
            $LogRequest['status'] = "Step 3: GDAP Relationship active. Mapping group: $($Role.GroupId)"
            Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null
        }
        catch {
            $LogRequest['status'] = "Migration Failed. Could not create group mapping for group $($role.GroupId): $($_.Exception.Message)"
            Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null
            exit 1
        }
        #$CheckActiveRole = New-GraphGetRequest -NoAuthCheck $True -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/$($MigrateRequest.id)/accessAssignments/$($RoleActiveID.id)" -tenantid $env:TenantId  -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
    }
    $LogRequest['status'] = "Migration Complete"
    Add-AzDataTableEntity @Table -Entity $logRequest -Force | Out-Null

}

