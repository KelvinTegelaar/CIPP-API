Function Invoke-ListGlobalAddressList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GAL = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Recipient' -cmdParams @{ResultSize = 'unlimited'; SortBy = 'DisplayName' } `
            -Select 'Identity, DisplayName, Alias, PrimarySmtpAddress, ExternalDirectoryObjectId, HiddenFromAddressListsEnabled, EmailAddresses, IsDirSynced, SKUAssigned, RecipientType, RecipientTypeDetails, AddressListMembership' |
            Select-Object -ExcludeProperty *odata*, *data.type*
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::Forbidden
        $GAL = $ErrorMessage.NormalizedError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GAL)
        })

}
