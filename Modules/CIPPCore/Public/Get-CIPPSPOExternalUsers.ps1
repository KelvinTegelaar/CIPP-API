function Get-CIPPSPOExternalUsers {
    <#
    .SYNOPSIS
    List the SharePoint tenant external users store via CSOM

    .DESCRIPTION
    Enumerates every external user SharePoint Online knows about (the store behind
    Get-SPOExternalUser), using the CSOM Office365Tenant.GetExternalUsers method against the
    admin endpoint. This includes legacy email-authenticated guests (urn:spo:guest) that have
    no backing Entra object, and B2B guests whose Entra user may since have been deleted.

    .PARAMETER TenantFilter
    Tenant to query

    .EXAMPLE
    Get-CIPPSPOExternalUsers -TenantFilter 'contoso.onmicrosoft.com'

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl
    $AdditionalHeaders = @{ 'Accept' = 'application/json;odata=verbose' }

    $AllUsers = [System.Collections.Generic.List[object]]::new()
    $Position = 0
    $PageSize = 50

    do {
        # Office365Tenant (TenantManagement) constructor -> GetExternalUsers(position, pageSize, filter, sortOrder)
        $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="1" ObjectPathId="0" /><ObjectPath Id="3" ObjectPathId="2" /><Query Id="4" ObjectPathId="2"><Query SelectAllProperties="true"><Properties><Property Name="ExternalUserCollection"><Query SelectAllProperties="true"><Properties /></Query><ChildItemQuery SelectAllProperties="true"><Properties /></ChildItemQuery></Property></Properties></Query></Query></Actions><ObjectPaths><Constructor Id="0" TypeId="{e45fd516-a408-4ca4-b6dc-268e2f1f0f83}" /><Method Id="2" ParentId="0" Name="GetExternalUsers"><Parameters><Parameter Type="Int32">$Position</Parameter><Parameter Type="Int32">$PageSize</Parameter><Parameter Type="String"></Parameter><Parameter Type="Enum">0</Parameter></Parameters></Method></ObjectPaths></Request>
"@

        $Results = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

        $CsomError = ($Results | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
        if ($CsomError) { throw $CsomError }

        $ResultObject = $Results | Where-Object { $null -ne $_.TotalUserCount } | Select-Object -First 1
        $Batch = @($ResultObject.ExternalUserCollection._Child_Items_)
        foreach ($User in $Batch) {
            [void]$AllUsers.Add($User)
        }
        $Position = $ResultObject.UserCollectionPosition
        # Continue while SPO reports more users beyond the current position.
    } while ($Batch.Count -eq $PageSize -and $Position -ge 0 -and $AllUsers.Count -lt [int]$ResultObject.TotalUserCount)

    return $AllUsers
}
