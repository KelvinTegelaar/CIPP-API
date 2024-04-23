function Invoke-CIPPStandardGroupTemplate {
  <#
    .FUNCTIONALITY
    Internal
    #>
  param($Tenant, $Settings)
  If ($Settings.remediate) {
        
    foreach ($Template in $Settings.TemplateList) {
      try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'GroupTemplate' and RowKey eq '$($Template.value)'" 
        $groupobj = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
        $email = if ($groupobj.domain) { "$($groupobj.username)@$($groupobj.domain)" } else { "$($groupobj.username)@$($Tenant)" }
        $CheckExististing = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $tenant | Where-Object -Property displayName -EQ $groupobj.displayname
        if (!$CheckExististing) {
          if ($groupobj.groupType -in 'Generic', 'azurerole', 'dynamic') {
        
            $BodyToship = [pscustomobject] @{
              'displayName'      = $groupobj.Displayname
              'description'      = $groupobj.Description
              'mailNickname'     = $groupobj.username
              mailEnabled        = [bool]$false
              securityEnabled    = [bool]$true
              isAssignableToRole = [bool]($groupobj | Where-Object -Property groupType -EQ 'AzureRole')

            } 
            if ($groupobj.membershipRules) {
              $BodyToship | Add-Member -NotePropertyName 'membershipRule' -NotePropertyValue ($groupobj.membershipRules)
              $BodyToship | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('DynamicMembership')
              $BodyToship | Add-Member -NotePropertyName 'membershipRuleProcessingState' -NotePropertyValue 'On'
            }
            $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $tenant -type POST -body (ConvertTo-Json -InputObject $BodyToship -Depth 10) -verbose
          } else {
            if ($groupobj.groupType -eq 'dynamicdistribution') {
              $Params = @{ 
                Name               = $groupobj.Displayname
                RecipientFilter    = $groupobj.membershipRules
                PrimarySmtpAddress = $email
              }
              $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'New-DynamicDistributionGroup' -cmdParams $params
            } else {
              $Params = @{ 
                Name                               = $groupobj.Displayname
                Alias                              = $groupobj.username
                Description                        = $groupobj.Description
                PrimarySmtpAddress                 = $email
                Type                               = $groupobj.groupType
                RequireSenderAuthenticationEnabled = [bool]!$groupobj.AllowExternal
              }
              $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'New-DistributionGroup' -cmdParams $params
            }
          }
          Write-LogMessage -user $request.headers.'x-ms-client-principal' -API 'Standards' -tenant $tenant -message "Created group $($groupobj.displayname) with id $($GraphRequest.id) " -Sev 'Info'

        } else {
          Write-LogMessage -user $request.headers.'x-ms-client-principal' -API 'Standards' -tenant $tenant -message "Group exists $($groupobj.displayname). Did not create" -Sev 'Info'

        }
      } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create group: $($_.exception.message)" -sev 'Error'
      }
    }


  }
}
