function Invoke-CIPPBaselineSPFileRequests {
    <#
    .SYNOPSIS
        SPFileRequests executor: the SPOTenant write, refused while sharing is below 'Anyone'.
    .DESCRIPTION
        SharePoint accepts the File Requests properties at any sharing level but only applies
        them at 'External Users and Guests (Anyone)', so an unguarded write reports Remediated
        on every run while the setting never changes.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $SharingCapability = "$($Current.SharingCapability)"
    if ($Remediate.properties.CoreRequestFilesLinkEnabled -eq $true -and $SharingCapability -and $SharingCapability -ne '2') {
        $SharingLevel = @{ '0' = 'Disabled'; '1' = 'External Users Only'; '3' = 'Existing External Users Only' }[$SharingCapability] ?? $SharingCapability
        throw [System.ArgumentException]::new("File Requests cannot be enabled while the tenant sharing level is '$SharingLevel'. Set it to 'External Users and Guests (Anyone)' first; another standard may be holding it lower.")
    }

    Invoke-CIPPBaselineSPOTenant -Remediate $Remediate -TenantFilter $TenantFilter -Current $Current
}
