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

    # CreatePersonalSiteEnqueueBulk accepts at most 200 users per call.
    $BatchSize = 200
    $Routes = [ordered]@{
        'ProfileLoader.CreatePersonalSiteEnqueueBulk' = '<Request xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009" AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName=".NET Library"><Actions><ObjectPath Id="5" ObjectPathId="4" /><Method Name="CreatePersonalSiteEnqueueBulk" Id="6" ObjectPathId="4"><Parameters><Parameter Type="Array">{0}</Parameter></Parameters></Method></Actions><ObjectPaths><StaticMethod Id="4" Name="GetProfileLoader" TypeId="{{9c42543a-91b3-4902-b2fe-14ccdefb6e2b}}" /></ObjectPaths></Request>'
        'Tenant.RequestPersonalSites'                 = '<Request xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009" AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName=".NET Library"><Actions><ObjectPath Id="4" ObjectPathId="3" /><ObjectPath Id="6" ObjectPathId="5" /><Query Id="7" ObjectPathId="5"><Query SelectAllProperties="true"><Properties /></Query></Query></Actions><ObjectPaths><Constructor Id="3" TypeId="{{268004ae-ef6b-4e9b-8425-127220d84719}}" /><Method Id="5" ParentId="3" Name="RequestPersonalSites"><Parameters><Parameter Type="Array">{0}</Parameter></Parameters></Method></ObjectPaths></Request>'
    }

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Uri = "$($SharePointInfo.AdminUrl)/_vti_bin/client.svc/ProcessQuery"
    $Scope = "$($SharePointInfo.AdminUrl)/.default"

    try {
        for ($Offset = 0; $Offset -lt $UserEmails.Count; $Offset += $BatchSize) {
            $Batch = $UserEmails[$Offset..([Math]::Min($Offset + $BatchSize, $UserEmails.Count) - 1)]
            $UserList = [System.Collections.Generic.List[string]]::new()
            foreach ($User in $Batch) {
                $UserList.Add("<Object Type='String'>$([System.Security.SecurityElement]::Escape($User))</Object>")
            }
            $UserArray = $UserList -join ''

            $Failures = [System.Collections.Generic.List[string]]::new()
            $Accepted = $false
            foreach ($RouteName in $Routes.Keys) {
                try {
                    $Request = New-GraphPostRequest -scope $Scope -tenantid $TenantFilter -Uri $Uri -Type POST -Body ($Routes[$RouteName] -f $UserArray) -ContentType 'text/xml'
                    # ProcessQuery answers HTTP 200 even when the request was refused - the reason rides in
                    # the CSOM ErrorInfo node. Surface it so a refusal is not reported back as success.
                    $CsomError = ($Request | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo
                    if ($CsomError) { throw "$($CsomError.ErrorMessage) [$($CsomError.ErrorTypeName)]" }
                    if (!$Request.IsComplete) { throw 'SharePoint did not confirm the personal site request.' }
                    $Accepted = $true
                    break
                } catch {
                    $Failures.Add("$RouteName - $($_.Exception.Message)")
                    Write-LogMessage -headers $Headers -API $APIName -message "$RouteName refused the personal site request for $($Batch -join ', '): $($_.Exception.Message)" -Sev 'Warning' -tenant $TenantFilter
                }
            }
            if (-not $Accepted) { throw ($Failures -join ' | ') }
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Requested personal site for $($UserEmails -join ', ')" -Sev 'Info' -tenant $TenantFilter
        return "Successfully requested personal site for $($UserEmails -join ', ')"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Detail = $ErrorMessage.NormalizedError
        # Delegated SharePoint admin calls need the CIPP user to hold SharePoint Administrator in the
        # tenant (via the GDAP relationship); a bare 401 or an unauthorized-operation refusal is that.
        if ($Detail -match '\b401\b|unauthorized') {
            $Detail = "$Detail - The CIPP user needs the SharePoint Administrator role in $TenantFilter (through the GDAP relationship) to request personal sites."
        }
        $Result = "Failed to request personal site for $($UserEmails -join ', '). Error: $Detail"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
