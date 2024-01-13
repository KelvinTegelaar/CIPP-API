function Set-CIPPOnedriveAccess {
  [CmdletBinding()]
  param (
    $userid,
    $OnedriveAccessUser,
    $TenantFilter,
    $APIName = 'Manage OneDrive Access',
    $ExecutingUser
  )

  try {
    $URL = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)/Drives" -asapp $true -tenantid $TenantFilter).WebUrl
    $OnMicrosoft = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $TenantFilter | Where-Object -Property isInitial -EQ $true).id.split('.') | Select-Object -First 1
    $AdminUrl = "https://$($OnMicrosoft)-admin.sharepoint.com"
    $XML = @"
<Request xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009" AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName=".NET Library">
  <Actions>
    <ObjectPath Id="249" ObjectPathId="248"/>
  </Actions>
  <ObjectPaths>
    <Method Id="248" ParentId="242" Name="SetSiteAdmin">
      <Parameters>
        <Parameter Type="String">$URL</Parameter>
        <Parameter Type="String">$OnedriveAccessUser</Parameter>
        <Parameter Type="Boolean">true</Parameter>
      </Parameters>
    </Method>
    <Constructor Id="242" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}"/>
  </ObjectPaths>
</Request>
"@
    $request = New-GraphPostRequest -scope "$AdminURL/.default" -tenantid $TenantFilter -Uri "$AdminURL/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml'
    if (!$request.ErrorInfo.ErrorMessage) {
      Write-LogMessage -user $ExecutingUser -API $APIName -message "Gave $($OnedriveAccessUser) access to $($userid) OneDrive" -Sev 'Info' -tenant $TenantFilter
      return "User's OneDrive URL is $URL. Access has been given to $($OnedriveAccessUser)"
    } else {
      Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to give OneDrive Access: $($request.ErrorInfo.ErrorMessage)" -Sev 'Info' -tenant $TenantFilter
      return "Failed to give OneDrive Access: $($request.ErrorInfo.ErrorMessage)"
    }
  } catch {
    Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add new owner to OneDrive $($OnedriveAccessUser) on $($userid)" -Sev 'Error' -tenant $TenantFilter
    return "Could not add owner to OneDrive for $($userid). Error: $($_.Exception.Message)"
  }
}
