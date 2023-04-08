using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$Groups = $Request.body.gdapRoles
$Table = Get-CIPPTable -TableName 'GDAPRoles' 

$Results = [System.Collections.Generic.List[string]]::new()
$ExistingGroups = New-GraphGetRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/groups' -tenantid $env:TenantID

$RoleMappings = foreach ($group in $Groups) {
      $randomSleep = Get-Random -Minimum 10 -Maximum 500
      Start-Sleep -Milliseconds $randomSleep
      
      try {
            if ("M365 GDAP $($Group.Name)" -in $ExistingGroups.displayName) {
                  @{
                        PartitionKey     = 'Roles'
                        RowKey           = ($ExistingGroups | Where-Object -Property displayName -EQ "M365 GDAP $($Group.Name)").id
                        RoleName         = $Group.Name
                        GroupName        = "M365 GDAP $($Group.Name)"
                        GroupId          = ($ExistingGroups | Where-Object -Property displayName -EQ "M365 GDAP $($Group.Name)").id
                        roleDefinitionId = $group.ObjectId
                  }
                  $Results.Add("M365 GDAP $($Group.Name) already exists")
            }
            else {
                  $BodyToship = [pscustomobject] @{'displayName' = "M365 GDAP $($Group.Name)"; 'description' = "This group is used to manage M365 partner tenants at the $($group.name) level."; securityEnabled = $true; mailEnabled = $false; mailNickname = "M365GDAP$(($Group.Name).replace(' ',''))" } | ConvertTo-Json
                  $GraphRequest = New-GraphPostRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/groups' -tenantid $env:TenantID -type POST -body $BodyToship -verbose
                  @{
                        PartitionKey     = 'Roles'
                        RowKey           = $GraphRequest.Id
                        RoleName         = $Group.Name
                        GroupName        = "M365 GDAP $($Group.Name)"
                        GroupId          = $GraphRequest.Id 
                        roleDefinitionId = $group.ObjectId
                  }
                  $Results.Add("M365 GDAP $($Group.Name) added successfully")
            }
      }
      catch {
            $Results.Add("Could not create GDAP group M365 GDAP $($Group.Name): $($_.Exception.Message)")
      }
}

Add-AzDataTableEntity @Table -Entity $RoleMappings -Force

$body = @{Results = @($Results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
      })