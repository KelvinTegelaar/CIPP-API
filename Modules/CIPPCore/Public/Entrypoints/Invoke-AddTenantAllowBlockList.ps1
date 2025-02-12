using namespace System.Net

Function Invoke-AddTenantAllowBlockList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $blocklistobj = $Request.body
    if ($Request.body.tenantId -eq 'AllTenants') { $Tenants = (Get-Tenants).defaultDomainName } else { $Tenants = @($Request.body.tenantId) }
    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Results = [System.Collections.Generic.List[string]]::new()
    foreach ($Tenant in $Tenants) {
        try {
            $ExoRequest = @{
                tenantid  = $Tenant
                cmdlet    = 'New-TenantAllowBlockListItems'
                cmdParams = @{
                    Entries                  = [string[]]$blocklistobj.entries
                    ListType                 = [string]$blocklistobj.listType
                    Notes                    = [string]$blocklistobj.notes
                    $blocklistobj.listMethod = [bool]$true
                }
            }

            if ($blocklistobj.NoExpiration -eq $true) {
                $ExoRequest.cmdParams.NoExpiration = $true
            }

            New-ExoRequest @ExoRequest

            $results.add("Successfully added $($blocklistobj.Entries) as type $($blocklistobj.ListType) to the $($blocklistobj.listMethod) list for $tenant")
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Tenant -message $result -Sev 'Info'
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $results.add("Failed to create blocklist. Error: $ErrorMessage")
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Tenant -message $result -Sev 'Error'
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                'Results' = $results
                'Request' = $ExoRequest
            }
        })
}
