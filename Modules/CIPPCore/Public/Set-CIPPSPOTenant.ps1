function Set-CIPPSPOTenant {
    <#
    .SYNOPSIS
    Set SharePoint Tenant properties or invoke methods

    .DESCRIPTION
    Set SharePoint Tenant properties via SPO CSOM API, or invoke a CSOM method on the Tenant object.

    .PARAMETER TenantFilter
    Tenant to apply settings to

    .PARAMETER Identity
    Tenant Identity (Get from Get-CIPPSPOTenant)

    .PARAMETER Properties
    Hashtable of tenant properties to change (uses SetProperty actions)

    .PARAMETER MethodName
    Name of the CSOM method to invoke on the Tenant object

    .PARAMETER MethodParameters
    Ordered array of parameter hashtables for the method call. Each entry must have 'Type' and 'Value' keys.
    Supported types: Boolean, String, Int32, Int64.

    .PARAMETER SharepointPrefix
    Prefix for the sharepoint tenant

    .PARAMETER SharepointDomain
    SharePoint domain that goes with the prefix (sharepoint.com, sharepoint.de, ...). Supplied by
    Get-CIPPSPOTenant over the pipeline; without it the prefix alone is re-resolved rather than
    assumed to be sharepoint.com.

    .EXAMPLE
    $Properties = @{
        'EnableAIPIntegration' = $true
    }
    Get-CippSPOTenant -TenantFilter 'contoso.onmicrosoft.com' | Set-CIPPSPOTenant -Properties $Properties

    .EXAMPLE
    $MethodParams = @(
        @{ Type = 'Boolean'; Value = $false }
        @{ Type = 'Int32'; Value = 50 }
        @{ Type = 'Int32'; Value = 365 }
    )
    Get-CIPPSPOTenant -TenantFilter 'contoso.onmicrosoft.com' | Set-CIPPSPOTenant -MethodName 'SetFileVersionPolicy' -MethodParameters $MethodParams

    .FUNCTIONALITY
    Internal

    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Properties')]
    param(
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'Properties')]
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'Method')]
        [string]$TenantFilter,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'Properties')]
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'Method')]
        [Alias('_ObjectIdentity_')]
        [string]$Identity,
        [Parameter(Mandatory = $true, ParameterSetName = 'Properties')]
        [hashtable]$Properties,
        [Parameter(Mandatory = $true, ParameterSetName = 'Method')]
        [string]$MethodName,
        [Parameter(Mandatory = $true, ParameterSetName = 'Method')]
        [array]$MethodParameters,
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Properties')]
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Method')]
        [string]$SharepointPrefix,
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Properties')]
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Method')]
        [string]$SharepointDomain,
        # SharePoint app-only auth requires a certificate (secret app-only is rejected by SPO). When
        # set, authenticate app-only with the SAM certificate instead of the delegated context.
        [Parameter(ParameterSetName = 'Properties')]
        [Parameter(ParameterSetName = 'Method')]
        [switch]$UseCertificate
    )

    process {
        # Threaded onto the ProcessQuery call below; empty = unchanged delegated behaviour.
        $AuthSplat = @{}
        if ($UseCertificate) { $AuthSplat['AsApp'] = $true; $AuthSplat['UseCertificate'] = $true }

        if (!$SharepointPrefix) {
            # get sharepoint admin site
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $AdminUrl = $SharePointInfo.AdminUrl
        } elseif ($SharepointDomain) {
            # Prefix and domain both came off the pipeline (Get-CIPPSPOTenant) - rebuild from them.
            $AdminUrl = "https://$($SharepointPrefix)-admin.$SharepointDomain"
        } else {
            # A prefix with no domain cannot be trusted to be sharepoint.com, and this object may
            # have come from a cache row predating SharepointDomain. Resolve the real one.
            $AdminUrl = (Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter).AdminUrl
        }
        $Identity = $Identity -replace "`n", '&#xA;'

        if ($PSCmdlet.ParameterSetName -eq 'Properties') {
            $AllowedTypes = @('Boolean', 'String', 'Int32')
            $SetProperty = [System.Collections.Generic.List[string]]::new()
            $x = 114
            foreach ($Property in $Properties.Keys) {
                $Value = $Properties[$Property]
                if ($null -eq $Value) { throw "Property '$Property' has no value" }

                # Values that came through JSON arrive as Int64 (or a whole Double); CSOM only
                # takes Int32 for numeric tenant properties, so coerce rather than drop them.
                if ($Value -is [int64] -or $Value -is [int16] -or $Value -is [byte] -or ($Value -is [double] -and $Value -eq [math]::Truncate($Value))) {
                    $Value = [int]$Value
                }

                $PropertyType = $Value.GetType().Name
                if ($PropertyType -notin $AllowedTypes) {
                    # Silently skipping leaves the caller logging success for a write that never
                    # happened - surface it instead.
                    throw "Property '$Property' has unsupported type '$PropertyType'. Supported: $($AllowedTypes -join ', ')"
                }

                if ($PropertyType -eq 'Boolean') {
                    $PropertyToSet = $Value.ToString().ToLower()
                } else {
                    $PropertyToSet = [System.Security.SecurityElement]::Escape([string]$Value)
                }
                $xml = @"
    <SetProperty Id="$x" ObjectPathId="110" Name="$Property">
        <Parameter Type="$PropertyType">$($PropertyToSet)</Parameter>
    </SetProperty>
"@
                $SetProperty.Add($xml)
                $x++
            }

            if (($SetProperty | Measure-Object).Count -eq 0) {
                Write-Error 'No valid properties found'
                return
            }

            $ActionsXml = $SetProperty -join ''
            $Description = $Properties.Keys -join ', '
        } else {
            # Method call
            $Params = foreach ($Param in $MethodParameters) {
                $ParamValue = if ($Param.Type -eq 'Boolean') { $Param.Value.ToString().ToLower() } else { $Param.Value }
                "<Parameter Type=`"$($Param.Type)`">$ParamValue</Parameter>"
            }
            $ActionsXml = "<Method Name=`"$MethodName`" Id=`"114`" ObjectPathId=`"110`"><Parameters>$($Params -join '')</Parameters></Method>"
            $Description = $MethodName
        }

        # Build CSOM request
        $XML = @"
    <Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions>$ActionsXml</Actions><ObjectPaths><Identity Id="110" Name="$Identity" /></ObjectPaths></Request>
"@
        $AdditionalHeaders = @{
            'Accept' = 'application/json;odata=verbose'
        }

        if ($PSCmdlet.ShouldProcess($Description, 'Set Tenant Properties')) {
            $Response = New-GraphPostRequest -scope "$AdminURL/.default" -tenantid $TenantFilter -Uri "$AdminURL/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders @AuthSplat
            # CSOM reports a rejected write as HTTP 200 with ErrorInfo in the body
            $CsomError = (@($Response).Where({ $_.ErrorInfo }) | Select-Object -First 1).ErrorInfo.ErrorMessage
            if ($CsomError) { throw $CsomError }

            # Invalidate cached tenant data so subsequent reads reflect the change
            $Table = Get-CIPPTable -tablename 'cachespotenant'
            $SafeTenantFilter = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
            $CacheEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Tenant' and RowKey eq '$SafeTenantFilter'"
            if ($CacheEntity) {
                Remove-CIPPAzDataTableEntity @Table -Entity $CacheEntity
            }
            $Response
        }
    }
}
