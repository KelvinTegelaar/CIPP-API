using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$Groups = $Request.body.gdapRoles
$CustomSuffix = $Request.body.customSuffix
$Table = Get-CIPPTable -TableName 'GDAPRoles' 

$Results = [System.Collections.Generic.List[string]]::new()
$ExistingGroups = New-GraphGetRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/groups' -tenantid $env:TenantID

$RoleMappings = foreach ($group in $Groups) {
      if ($CustomSuffix) {
            $GroupName = "M365 GDAP $($Group.Name) - $CustomSuffix"
            $MailNickname = "M365GDAP$(($Group.Name).replace(' ',''))$($CustomSuffix)"
      }
      else {
            $GroupName = "M365 GDAP $($Group.Name)"
            $MailNickname = "M365GDAP$(($Group.Name).replace(' ',''))"
      }
      try {
            if ($GroupName -in $ExistingGroups.displayName) {
                  @{
                        PartitionKey     = 'Roles'
                        RowKey           = ($ExistingGroups | Where-Object -Property displayName -EQ $GroupName).id
                        RoleName         = $Group.Name
                        GroupName        = $GroupName
                        GroupId          = ($ExistingGroups | Where-Object -Property displayName -EQ $GroupName).id
                        roleDefinitionId = $group.ObjectId
                  }
                  $Results.Add("M365 GDAP $($Group.Name) already exists")
            }
            else {
                  $BodyToship = [pscustomobject] @{'displayName' = $GroupName; 'description' = "This group is used to manage M365 partner tenants at the $($group.name) level."; securityEnabled = $true; mailEnabled = $false; mailNickname = $MailNickname } | ConvertTo-Json
                  $GraphRequest = New-GraphPostRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/groups' -tenantid $env:TenantID -type POST -body $BodyToship -verbose
                  @{
                        PartitionKey     = 'Roles'
                        RowKey           = $GraphRequest.Id
                        RoleName         = $Group.Name
                        GroupName        = $GroupName
                        GroupId          = $GraphRequest.Id 
                        roleDefinitionId = $group.ObjectId
                  }
                  $Results.Add("$GroupName added successfully")
            }
      }
      catch {
            $Results.Add("Could not create GDAP group $($GroupName): $($_.Exception.Message)")
      }
}

Add-CIPPAzDataTableEntity @Table -Entity $RoleMappings -Force

$body = @{Results = @($Results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
      })