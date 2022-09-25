using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
$TenantFilter = $ENV:TenantId
$Groups = $Request.body.gdapRoles
$Tenants = $Request.body.selectedTenants
$Results = [System.Collections.ArrayList]@()
#Create new groups if required, collect IDs of these groups

$ExistingGroups = New-GraphGetRequest -asApp $true -uri "https://graph.microsoft.com/beta/groups" -tenantid $TenantFilter
$RoleMappings = foreach ($group in $Groups) {
      try {
            if ("M365 GDAP $($Group.Name)" -in $ExistingGroups.displayName) {
                  @{
                        GroupId          = ($ExistingGroups | Where-Object -Property displayName -EQ "M365 GDAP $($Group.Name)").id
                        roleDefinitionId = $group.ObjectId
                  }
                  $results.add("Group M365 GDAP $($Group.Name) already exists, using this group.") | Out-Null
            }
            else {
                  $BodyToship = [pscustomobject] @{"displayName" = "M365 GDAP $($Group.Name)"; "description" = "This group is used to manage M365 partner tenants at the $($group.name) level."; securityEnabled = $true; mailEnabled = $false; mailNickname = "M365GDAP$(($Group.Name).replace(' ',''))" } | ConvertTo-Json
                  $GraphRequest = New-GraphPostRequest -AsApp $true -uri "https://graph.microsoft.com/beta/groups" -tenantid $ENV:TenantId -type POST -body $BodyToship  -verbose
                  $results.add("Created group M365 GDAP $($Group.Name).") | Out-Null
                  @{
                        GroupId          = $GraphRequest.Id 
                        roleDefinitionId = $group.ObjectId
                  }
            }
      }
      catch {
            $results.add("Could not create group: M365 GDAP $($Group.Name). $($_.Exception.Message)")
      }
}

foreach ($Tenant in $Tenants) {
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
      $MigrateRequest = New-GraphPostRequest -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/migrate" -type POST -body $JSONBody -verbose -tenantid $ENV:TenantId -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
      do {
            $CheckActive = New-GraphGetRequest -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/$($MigrateRequest.id)" -tenantid $ENV:TenantId  -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
            Start-Sleep -Milliseconds 600
      } until ($CheckActive.status -eq "Active")

      if ($CheckActive.status -eq "Active") {

            $results.add("GDAP Migration Succesful. Enabling groups for $($tenant.displayName)") | Out-Null

            #Map groups to roles
            foreach ($role in $RoleMappings) {
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
                  $RoleActiveID = New-GraphPOSTRequest -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/$($MigrateRequest.id)/accessAssignments" -tenantid $ENV:TenantId -type POST -body $MappingBody  -verbose  -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
                  Write-Host "Enabled Groups"
                  #$CheckActiveRole = New-GraphGetRequest -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web//v1/delegatedAdminRelationships/$($MigrateRequest.id)/accessAssignments/$($RoleActiveID.id)" -tenantid $ENV:TenantId  -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
                  $results.add("Migration complete for $($tenant.displayName)") | Out-Null

            }
      }
}

$body = @{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
      })