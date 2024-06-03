using namespace System.Net

Function Invoke-ListPhishPolicies {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $AntiPhishRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishRule'
    $AntiPhishPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishPolicy'

    $GraphRequest = $AntiPhishPolicies | Select-Object name,
    @{Name = 'GUID'; Expression = { $(( -join (( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 13 | ForEach-Object { [char]$_ }) )) } },
    @{ Name = 'ExcludedDomains'; Expression = { $($_.ExcludedDomains) -join '<br />' } },
    @{ Name = 'ExcludedSenders'; Expression = { $($_.ExcludedSenders) -join '<br />' } },
    @{ Name = 'PhishThresholdLevel'; Expression = {
            switch ($_.PhishThresholdLevel) {
                1 { $result = 'Standard' }
                2 { $result = 'Aggressive' }
                3 { $result = 'More Aggressive' }
                4 { $result = 'Most Aggressive' }
                Default { $result = 'Unknown' }
            }
            $result
        }
    },
    @{ Name = 'ExcludedDomainCount'; Expression = { $_.ExcludedDomains | Measure-Object | Select-Object -ExpandProperty Count } },
    @{ Name = 'ExcludedSenderCount'; Expression = { $_.ExcludedSenders | Measure-Object | Select-Object -ExpandProperty Count } }, Enabled, WhenChangedUTC,
    @{ Name = 'Priority'; Expression = { foreach ($item in $AntiPhishRules) { if ($item.name -eq $_.name) { $item.priority } } } }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
