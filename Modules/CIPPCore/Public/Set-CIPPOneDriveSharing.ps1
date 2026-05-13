function Set-CIPPOneDriveSharing {
    [CmdletBinding()]
    param (
        $UserId,
        $TenantFilter,
        [ValidateSet('Disabled', 'ExternalUserSharingOnly', 'ExternalUserAndGuestSharing', 'ExistingExternalUserSharingOnly')]
        [string]$SharingCapability = 'Disabled',
        $APIName = 'Set OneDrive Sharing',
        $Headers,
        $URL
    )

    $SharingCapabilityMap = @{
        'Disabled'                         = 0
        'ExternalUserSharingOnly'          = 1
        'ExternalUserAndGuestSharing'      = 2
        'ExistingExternalUserSharingOnly'  = 3
    }
    $EnumValue = $SharingCapabilityMap[$SharingCapability]

    try {
        if (!$URL) {
            #Grab url, get root level, strip /documents
            $URL = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)/drive" -asapp $true -tenantid $TenantFilter).webUrl -replace '/documents', ''
        }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter

        $XML = @"
<Request xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009" AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName=".NET Library">
  <Actions>
    <SetProperty Id="7" ObjectPathId="4" Name="SharingCapability">
      <Parameter Type="Enum">$EnumValue</Parameter>
    </SetProperty>
    <Method Name="Update" Id="9" ObjectPathId="4"/>
  </Actions>
  <ObjectPaths>
    <Method Id="4" ParentId="1" Name="GetSitePropertiesByUrl">
      <Parameters>
        <Parameter Type="String">$URL</Parameter>
        <Parameter Type="Boolean">false</Parameter>
      </Parameters>
    </Method>
    <Constructor Id="1" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}"/>
  </ObjectPaths>
</Request>
"@
        $Request = New-GraphPostRequest -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -Uri "$($SharePointInfo.AdminUrl)/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml'

        if (!$Request.ErrorInfo.ErrorMessage) {
            $Message = "Successfully set OneDrive sharing to '$SharingCapability' for $UserId ($URL)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Info -tenant $TenantFilter
            return $Message
        } else {
            $Message = "Failed to set OneDrive sharing for $UserId : $($Request.ErrorInfo.ErrorMessage)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Error -tenant $TenantFilter
            return $Message
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set OneDrive sharing for $UserId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
