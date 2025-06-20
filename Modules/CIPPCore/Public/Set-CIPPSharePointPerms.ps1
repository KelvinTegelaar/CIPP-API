function Set-CIPPSharePointPerms {
    [CmdletBinding()]
    param (
        $UserId, # The UPN or ID of the users OneDrive we are changing permissions on
        $OnedriveAccessUser, # The UPN of the user we are adding or removing permissions for
        $TenantFilter,
        $APIName = 'Manage SharePoint Owner',
        $RemovePermission,
        $Headers,
        $URL
    )
    if ($RemovePermission -eq $true) {
        $SiteAdmin = 'false'
    } else {
        $SiteAdmin = 'true'
    }

    try {
        if (!$URL) {
            Write-Information 'No URL provided, getting URL from Graph'
            $URL = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)/Drives" -asapp $true -tenantid $TenantFilter).WebUrl
        }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
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
        $request = New-GraphPostRequest -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -Uri "$($SharePointInfo.AdminUrl)/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml'
        # Write-Host $($request)
        if (!$request.ErrorInfo.ErrorMessage) {
            $Message = "$($OnedriveAccessUser) has been $($RemovePermission ? 'removed from' : 'given') access to $URL"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Info -tenant $TenantFilter
            return $Message
        } else {
            $message = "Failed to change access: $($request.ErrorInfo.ErrorMessage)"
            Write-LogMessage -headers $Headers -API $APIName -message $message -Sev Error -tenant $TenantFilter
            throw $Message
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not add new owner to $($OnedriveAccessUser) on $URL. Error: $($ErrorMessage.NormalizedError)" -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not add owner for $($URL). Error: $($ErrorMessage.NormalizedError)"
    }
}
