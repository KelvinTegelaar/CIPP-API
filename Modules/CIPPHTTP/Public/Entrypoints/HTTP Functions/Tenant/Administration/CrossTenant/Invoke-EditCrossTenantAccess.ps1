function Invoke-EditCrossTenantAccess {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    .DESCRIPTION
        Updates a tenant's default cross-tenant access settings, or adds or updates a partner organisation. Leave partnerTenantId empty to edit the default settings. Settings left out, or set to 'unchanged', are not touched.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Partner organisation tenant ID or one of its domains. Empty edits the default settings.
    $Partner = "$($Request.Body.partnerTenantId)".Trim()

    $Requested = [ordered]@{
        # allowed or blocked for all users and applications, inherit (partners only) to use the default settings, or unchanged
        b2bCollaborationInbound             = $Request.Body.b2bCollaborationInbound
        b2bCollaborationOutbound            = $Request.Body.b2bCollaborationOutbound
        b2bDirectConnectInbound             = $Request.Body.b2bDirectConnectInbound
        b2bDirectConnectOutbound            = $Request.Body.b2bDirectConnectOutbound
        # inherit (partners only) clears the partner's own trust settings
        inboundTrust                        = $Request.Body.inboundTrust
        # Accept MFA, compliant devices and hybrid-joined devices from the other tenant
        isMfaAccepted                       = $Request.Body.isMfaAccepted
        isCompliantDeviceAccepted           = $Request.Body.isCompliantDeviceAccepted
        isHybridAzureADJoinedDeviceAccepted = $Request.Body.isHybridAzureADJoinedDeviceAccepted
        # Automatically redeem invitations (partners only)
        inboundAllowed                      = $Request.Body.inboundAllowed
        outboundAllowed                     = $Request.Body.outboundAllowed
    }
    $Settings = @{}
    foreach ($Key in $Requested.Keys) {
        $Value = $Requested[$Key]
        if ($null -ne $Value -and "$Value" -notin '', 'unchanged') { $Settings[$Key] = $Value }
    }
    if ("$($Settings['inboundTrust'])" -eq 'inherit') {
        foreach ($Flag in 'isMfaAccepted', 'isCompliantDeviceAccepted', 'isHybridAzureADJoinedDeviceAccepted') { $Settings.Remove($Flag) }
    } else {
        $Settings.Remove('inboundTrust')
    }

    try {
        $PartnerTenantId = $Partner
        $ParsedId = [guid]::Empty
        if ($Partner -and -not [guid]::TryParse($Partner, [ref]$ParsedId)) {
            $Lookup = try {
                New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/tenantRelationships/findTenantInformationByDomainName(domainName='$([uri]::EscapeDataString($Partner))')" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
            } catch { $null }
            if (-not $Lookup.tenantId) { throw [System.ArgumentException]::new("No Microsoft 365 tenant found for '$Partner'.") }
            $PartnerTenantId = $Lookup.tenantId
        }
        $Result = Set-CIPPCrossTenantAccess -TenantFilter $TenantFilter -PartnerTenantId $PartnerTenantId -Settings $Settings
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Result = "Failed to update cross-tenant access settings: $ErrorMessage"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
