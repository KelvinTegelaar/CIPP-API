function Set-CIPPSharePointPerms {
    [CmdletBinding()]
    param (
        $UserId, # The UPN or ID of the users OneDrive we are changing permissions on
        [array]$OnedriveAccessUser, # The UPN(s) of the user(s) we are adding or removing permissions for - can be single value or array
        $TenantFilter,
        $APIName = 'Manage SharePoint Owner',
        $RemovePermission,
        $Headers,
        $URL
    )

    # Ensure OnedriveAccessUser is always an array
    if ($OnedriveAccessUser -isnot [array]) {
        $OnedriveAccessUser = @($OnedriveAccessUser)
    }

    # Extract values if objects with .value property (from frontend)
    $OnedriveAccessUser = $OnedriveAccessUser | ForEach-Object {
        if ($_ -is [PSCustomObject] -and $_.value) { $_.value } else { $_ }
    }

    $SiteAdmin = if ($RemovePermission -eq $true) { 'false' } else { 'true' }
    $Results = [system.collections.generic.list[string]]::new()

    try {
        if (!$URL) {
            Write-Information 'No URL provided, getting URL from Graph'
            $URL = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)/Drives" -asapp $true -tenantid $TenantFilter).WebUrl
        }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter

        # Process each access user
        foreach ($AccessUser in $OnedriveAccessUser) {
            try {
                $XML = @"
<Request xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009" AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName=".NET Library">
  <Actions>
    <ObjectPath Id="249" ObjectPathId="248"/>
  </Actions>
  <ObjectPaths>
    <Method Id="248" ParentId="242" Name="SetSiteAdmin">
      <Parameters>
        <Parameter Type="String">$URL</Parameter>
        <Parameter Type="String">$AccessUser</Parameter>
        <Parameter Type="Boolean">$SiteAdmin</Parameter>
      </Parameters>
    </Method>
    <Constructor Id="242" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}"/>
  </ObjectPaths>
</Request>
"@
                $request = New-GraphPostRequest -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -Uri "$($SharePointInfo.AdminUrl)/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml'

                if (!$request.ErrorInfo.ErrorMessage) {
                    $Message = "Successfully $($RemovePermission ? 'removed' : 'added') $($AccessUser) as an owner of $URL"
                    Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Info -tenant $TenantFilter
                    $Results.Add($Message)
                } else {
                    $Message = "Failed to change access for $($AccessUser): $($request.ErrorInfo.ErrorMessage)"
                    Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Error -tenant $TenantFilter
                    $Results.Add($Message)
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to change access for $($AccessUser) on $URL. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
                $Results.Add($Message)
            }
        }

        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to process SharePoint permissions. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
