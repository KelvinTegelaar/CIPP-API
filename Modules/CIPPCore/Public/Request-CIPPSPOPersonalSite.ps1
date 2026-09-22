function Request-CIPPSPOPersonalSite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$UserEmails,
        [string]$Headers = 'CIPP',
        [string]$APIName = 'Request-CIPPSPOPersonalSite'
    )
    $UserList = [System.Collections.Generic.List[string]]::new()
    foreach ($User in $UserEmails) {
        $UserList.Add("<Object Type='String'>$User</Object>")
    }

    $XML = @"
<Request xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009" AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName=".NET Library">
    <Actions>
        <ObjectPath Id="4" ObjectPathId="3" />
        <ObjectPath Id="6" ObjectPathId="5" />
        <Query Id="7" ObjectPathId="5">
            <Query SelectAllProperties="true">
                <Properties />
            </Query>
        </Query>
    </Actions>
    <ObjectPaths>
        <Constructor Id="3" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" />
        <Method Id="5" ParentId="3" Name="RequestPersonalSites">
            <Parameters>
                <Parameter Type="Array">
                    $($UserList -join '')
                </Parameter>
            </Parameters>
        </Method>
    </ObjectPaths>
</Request>
"@

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    try {
        # OneDrive pre-provisioning (ProfileLoader.RequestPersonalSites) is a User Profile Service
        # operation, so it must run app-only with the SAM certificate: a GDAP delegated token has no
        # licensed user object in the customer tenant and SharePoint refuses it with a bare 401. App-only
        # here needs the SharePoint 'User.ReadWrite.All' application permission (declared in
        # SAMManifest.json, applied on CPV consent) on top of Sites.FullControl.All.
        $Request = New-GraphPostRequest -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -Uri "$($SharePointInfo.AdminUrl)/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AsApp $true -UseCertificate

        # ProcessQuery answers HTTP 200 even when the request was refused - the reason rides in the CSOM
        # ErrorInfo node (e.g. an "access to profile information" denial when the permission above is not
        # yet consented). Surface it so a refusal is not reported back as success.
        $CsomError = ($Request | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
        if ($CsomError) { throw $CsomError }
        if (!$Request.IsComplete) { throw 'SharePoint did not confirm the personal site request.' }
        Write-LogMessage -headers $Headers -API $APIName -message "Requested personal site for $($UserEmails -join ', ')" -Sev 'Info' -tenant $TenantFilter
        return "Successfully requested personal site for $($UserEmails -join ', ')"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Detail = $ErrorMessage.NormalizedError
        # A "profile information" denial means the SAM app has not been granted the SharePoint
        # User.ReadWrite.All application permission in this tenant yet - refreshing CPV consent fixes it.
        if ($Detail -match 'profile information') {
            $Detail = "$Detail - CIPP is missing the SharePoint 'User.ReadWrite.All' application permission in $TenantFilter. Refresh the tenant's CPV permissions and try again."
        }
        $Result = "Failed to request personal site for $($UserEmails -join ', '). Error: $Detail"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
