function Invoke-ListSafeAttachmentsFilters {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentPolicy' | Select-Object -Property *
    $Rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentRule' | Select-Object -Property *

    $Output = $Policies | Select-Object -Property *,
    @{ Name = 'RuleName'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.Name } } } },
    @{ Name = 'Priority'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.Priority } } } },
    @{ Name = 'RecipientDomainIs'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.RecipientDomainIs } } } },
    @{ Name = 'State'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.State } } } }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Output
        })
}
