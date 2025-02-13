function Invoke-ListAntiPhishingFilters {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $Policys = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishPolicy' | Select-Object -Property *
    $Rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishRule' | Select-Object -Property *

    $Output = $Policys | Select-Object -Property *,
        @{ Name = 'RuleName'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.Name } } } },
        @{ Name = 'Priority'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.Priority } } } },
        @{ Name = 'RecipientDomainIs'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.RecipientDomainIs } } } },
        @{ Name = 'State'; Expression = { foreach ($item in $Rules) { if ($item.AntiPhishPolicy -eq $_.Name) { $item.State } } } }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Output
    })
}
