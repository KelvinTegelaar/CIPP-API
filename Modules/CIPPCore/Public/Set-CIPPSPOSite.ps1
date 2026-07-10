function Set-CIPPSPOSite {
    <#
    .SYNOPSIS
    Set SharePoint Site properties via CSOM

    .DESCRIPTION
    Sets properties on an individual SharePoint site using the CSOM GetSitePropertiesByUrl + SetProperty + Update pattern.

    .PARAMETER TenantFilter
    Tenant to apply settings to

    .PARAMETER SiteUrl
    Full URL of the SharePoint site to modify

    .PARAMETER Properties
    Hashtable of site properties to change. Supported value types: Boolean, String, Int32.

    .EXAMPLE
    $Properties = @{
        InheritVersionPolicyFromTenant    = $false
        EnableAutoExpirationVersionTrim   = $false
        ApplyToNewDocumentLibraries       = $true
        ApplyToExistingDocumentLibraries  = $true
        MajorVersionLimit                 = 50
        ExpireVersionsAfterDays           = 365
    }
    Set-CIPPSPOSite -TenantFilter 'contoso.onmicrosoft.com' -SiteUrl 'https://contoso.sharepoint.com/sites/MySite' -Properties $Properties

    .FUNCTIONALITY
    Internal

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminUrl = $SharePointInfo.AdminUrl

    $AllowedTypes = @('Boolean', 'String', 'Int32', 'Int64')
    # Properties that are CSOM enums; their (numeric) value must be sent as Type="Enum".
    $EnumProperties = @('SharingCapability', 'DefaultSharingLinkType', 'DefaultLinkPermission', 'SharingDomainRestrictionMode', 'ConditionalAccessPolicy')
    $SetProperty = [System.Collections.Generic.List[string]]::new()
    $x = 106
    foreach ($Property in $Properties.Keys) {
        $PropertyType = $Properties[$Property].GetType().Name
        if ($Property -in $EnumProperties) {
            $SetProperty.Add("<SetProperty Id=`"$x`" ObjectPathId=`"104`" Name=`"$Property`"><Parameter Type=`"Enum`">$([int]$Properties[$Property])</Parameter></SetProperty>")
            $x++
        } elseif ($PropertyType -in $AllowedTypes) {
            $PropertyToSet = if ($PropertyType -eq 'Boolean') { $Properties[$Property].ToString().ToLower() } else { [System.Security.SecurityElement]::Escape([string]$Properties[$Property]) }
            $SetProperty.Add("<SetProperty Id=`"$x`" ObjectPathId=`"104`" Name=`"$Property`"><Parameter Type=`"$PropertyType`">$PropertyToSet</Parameter></SetProperty>")
            $x++
        }
    }

    if ($SetProperty.Count -eq 0) {
        Write-Error 'No valid properties found'
        return
    }

    # CSOM pattern: Tenant Constructor → GetSitePropertiesByUrl → SetProperty(s) → Update
    $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions>$($SetProperty -join '')<ObjectPath Id="$x" ObjectPathId="113" /><ObjectIdentityQuery Id="$($x + 1)" ObjectPathId="104" /></Actions><ObjectPaths><Method Id="104" ParentId="102" Name="GetSitePropertiesByUrl"><Parameters><Parameter Type="String">$([System.Security.SecurityElement]::Escape($SiteUrl))</Parameter><Parameter Type="Boolean">false</Parameter></Parameters></Method><Method Id="113" ParentId="104" Name="Update" /><Constructor Id="102" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /></ObjectPaths></Request>
"@

    $AdditionalHeaders = @{
        'Accept' = 'application/json;odata=verbose'
    }

    if ($PSCmdlet.ShouldProcess($SiteUrl, 'Set Site Properties')) {
        New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders
    }
}
