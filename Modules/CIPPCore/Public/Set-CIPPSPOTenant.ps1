function Set-CIPPSPOTenant {
    <#
    .SYNOPSIS
    Set SharePoint Tenant properties

    .DESCRIPTION
    Set SharePoint Tenant properties via SPO API

    .PARAMETER TenantFilter
    Tenant to apply settings to

    .PARAMETER Identity
    Tenant Identity (Get from Get-CIPPSPOTenant)

    .PARAMETER Properties
    Hashtable of tenant properties to change

    .PARAMETER SharepointPrefix
    Prefix for the sharepoint tenant

    .EXAMPLE
    $Properties = @{
        'EnableAIPIntegration' = $true
    }
    Get-CippSPOTenant -TenantFilter 'contoso.onmicrosoft.com' | Set-CIPPSPOTenant -Properties $Properties

    .FUNCTIONALITY
    Internal

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Alias('_ObjectIdentity_')]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$SharepointPrefix
    )

    process {
        if (!$SharepointPrefix) {
            # get sharepoint admin site
            $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter).id.Split('.')[0]
        } else {
            $tenantName = $SharepointPrefix
        }
        $Identity = $Identity -replace "`n", '&#xA;'
        $AdminUrl = "https://$($tenantName)-admin.sharepoint.com"
        $AllowedTypes = @('Boolean', 'String', 'Int32')
        $SetProperty = [System.Collections.Generic.List[string]]::new()
        $x = 114
        foreach ($Property in $Properties.Keys) {
            # Get property type
            $PropertyType = $Properties[$Property].GetType().Name
            if ($PropertyType -in $AllowedTypes) {
                if ($PropertyType -eq 'Boolean') {
                    $PropertyToSet = $Properties[$Property].ToString().ToLower()
                } else {
                    $PropertyToSet = $Properties[$Property]
                }
                $xml = @"
    <SetProperty Id="$x" ObjectPathId="110" Name="$Property">
        <Parameter Type="Boolean">$($PropertyToSet)</Parameter>
    </SetProperty>
"@
                $SetProperty.Add($xml)
                $x++
            }
        }

        if (($SetProperty | Measure-Object).Count -eq 0) {
            Write-Error 'No valid properties found'
            return
        }

        # Query tenant settings
        $XML = @"
    <Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions>$($SetProperty -join '')</Actions><ObjectPaths><Identity Id="110" Name="$Identity" /></ObjectPaths></Request>
"@
        $AdditionalHeaders = @{
            'Accept' = 'application/json;odata=verbose'
        }

        if ($PSCmdlet.ShouldProcess(($Properties.Keys -join ', '), 'Set Tenant Properties')) {
            New-GraphPostRequest -scope "$AdminURL/.default" -tenantid $TenantFilter -Uri "$AdminURL/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders
        }
    }
}
