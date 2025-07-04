using namespace System.Net

function Invoke-ListGlobalAddressList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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

    return @{
        StatusCode = $StatusCode
        Body       = @($GAL)
    }

}
