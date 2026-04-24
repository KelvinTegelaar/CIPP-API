function Invoke-AddTenantAllowBlockList {
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

    $BlockListObject = $Request.Body
    $TenantID = $Request.Body.tenantID.value ?? $Request.Body.tenantID

    if ($TenantID -eq 'AllTenants') {
        $Tenants = (Get-Tenants).defaultDomainName
    } elseif ($TenantID -is [array]) {
        $Tenants = $TenantID
    } else {
        $Tenants = @($TenantID)
    }
    $Results = [System.Collections.Generic.List[string]]::new()
    $Entries = @()
    if ($BlockListObject.entries -is [array]) {
        $Entries = $BlockListObject.entries
    } else {
        $Entries = @($BlockListObject.entries -split '[,;]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
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
            $Result = "Successfully added $($BlockListObject.Entries) as type $($BlockListObject.ListType) to the $($BlockListObject.listMethod) list for $tenant"
            $Results.Add($Result)
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message $Result -Sev 'Info'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Result = "Failed to create blocklist. Error: $($ErrorMessage.NormalizedError)"
            $Results.Add($Result)
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message $Result -Sev 'Error' -LogData $ErrorMessage
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                'Results' = $Results
                'Request' = $ExoRequest
            }
        })
}
