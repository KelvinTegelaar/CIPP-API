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
    $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter).id.Split('.')[0]
    $AdminUrl = "https://$($tenantName)-admin.sharepoint.com"

    try {
        $Request = New-GraphPostRequest -scope "$AdminURL/.default" -tenantid $TenantFilter -Uri "$AdminURL/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml'
        if (!$Request.IsComplete) { throw }
        Write-LogMessage -headers $Headers -API $APIName -message "Requested personal site for $($UserEmails -join ', ')" -Sev 'Info' -tenant $TenantFilter
        return "Requested personal site for $($UserEmails -join ', ')"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not request personal site for $($UserEmails -join ', '). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not request personal site for $($UserEmails -join ', '). Error: $($ErrorMessage.NormalizedError)"
    }
}
