function Set-CIPPSharePointPerms {
  [CmdletBinding()]
  param (
    $userid,
    $OnedriveAccessUser,
    $TenantFilter,
    $APIName = 'Manage SharePoint Owner',
    $RemovePermission,
    $ExecutingUser,
    $URL
  )
  if ($RemovePermission -eq $true) {
    $SiteAdmin = 'false'
  } else {
    $SiteAdmin = 'true'
  }

  try {
    if (!$URL) {
      $URL = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)/Drives" -asapp $true -tenantid $TenantFilter).WebUrl
    }
    $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter).id.Split('.')[0]
    $AdminUrl = "https://$($tenantName)-admin.sharepoint.com"
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
        <Parameter Type="Boolean">$SiteAdmin</Parameter>
      </Parameters>
    </Method>
    <Constructor Id="242" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}"/>
  </ObjectPaths>
</Request>
"@
    $request = New-GraphPostRequest -scope "$AdminURL/.default" -tenantid $TenantFilter -Uri "$AdminURL/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml'
    Write-Host $($request)
    if (!$request.ErrorInfo.ErrorMessage) {
      $Message = "$($OnedriveAccessUser) has been $($RemovePermission ? 'removed from' : 'given') access to $URL"
      Write-LogMessage -user $ExecutingUser -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
      return $Message
    } else {
      $message = "Failed to change access: $($request.ErrorInfo.ErrorMessage)"
      Write-LogMessage -user $ExecutingUser -API $APIName -message $message -Sev 'Info' -tenant $TenantFilter
      return $message
    }
  } catch {
    Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add new owner to  $($OnedriveAccessUser) on $URL" -Sev 'Error' -tenant $TenantFilter
    return "Could not add owner for $($URL). Error: $($_.Exception.Message)"
  }
}
