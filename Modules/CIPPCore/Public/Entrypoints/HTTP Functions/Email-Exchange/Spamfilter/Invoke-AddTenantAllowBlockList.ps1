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
    $BlockListObject = $Request.Body
    if ($Request.Body.tenantId -eq 'AllTenants') { $Tenants = (Get-Tenants).defaultDomainName } else { $Tenants = @($Request.body.tenantId) }
    $Results = [System.Collections.Generic.List[string]]::new()
    $Entries = @()
    if ($BlockListObject.entries -is [array]) {
        $Entries = $BlockListObject.entries
    } else {
        $Entries = @($BlockListObject.entries -split "[,;]" | Where-Object { $_ -ne "" } | ForEach-Object { $_.Trim() })
    }
    foreach ($Tenant in $Tenants) {
        try {
            $ExoRequest = @{
                tenantid  = $Tenant
                cmdlet    = 'New-TenantAllowBlockListItems'
                cmdParams = @{
                    Entries                     = $Entries
                    ListType                    = [string]$BlockListObject.listType
                    Notes                       = [string]$BlockListObject.notes
                    $BlockListObject.listMethod = [bool]$true
                }
            }

            if ($BlockListObject.NoExpiration -eq $true) {
                $ExoRequest.cmdParams.NoExpiration = $true
            } elseif ($BlockListObject.RemoveAfter -eq $true) {
                $ExoRequest.cmdParams.RemoveAfter = 45
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
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                'Results' = $results
                'Request' = $ExoRequest
            }
        })
}
