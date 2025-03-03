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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $BlockListObject = $Request.Body
    if ($Request.Body.tenantId -eq 'AllTenants') { $Tenants = (Get-Tenants).defaultDomainName } else { $Tenants = @($Request.body.tenantId) }
    $Results = [System.Collections.Generic.List[string]]::new()
    foreach ($Tenant in $Tenants) {
        try {
            $ExoRequest = @{
                tenantid  = $Tenant
                cmdlet    = 'New-TenantAllowBlockListItems'
                cmdParams = @{
                    Entries                     = [string[]]$BlockListObject.entries
                    ListType                    = [string]$BlockListObject.listType
                    Notes                       = [string]$BlockListObject.notes
                    $BlockListObject.listMethod = [bool]$true
                }
            }

            if ($BlockListObject.NoExpiration -eq $true) {
                $ExoRequest.cmdParams.NoExpiration = $true
            }

            New-ExoRequest @ExoRequest

            $results.add("Successfully added $($BlockListObject.Entries) as type $($BlockListObject.ListType) to the $($BlockListObject.listMethod) list for $tenant")
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
