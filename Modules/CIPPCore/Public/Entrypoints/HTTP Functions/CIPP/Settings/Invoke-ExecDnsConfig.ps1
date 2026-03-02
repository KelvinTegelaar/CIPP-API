function Invoke-ExecDnsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Domains.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # List of supported resolvers
    $ValidResolvers = @(
        'Google'
        'Cloudflare'
    )


    $StatusCode = [HttpStatusCode]::OK
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $Domain = $Request.Query.Domain ?? $Request.Body.Domain
    $Resolver = $Request.Query.Resolver ?? $Request.Body.Resolver
    $Selector = $Request.Query.Selector ?? $Request.Body.Selector
    try {
        $ConfigTable = Get-CippTable -tablename Config
        $Filter = "PartitionKey eq 'Domains' and RowKey eq 'Domains'"
        $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter

        $DomainTable = Get-CippTable -tablename 'Domains'

        if ($ValidResolvers -notcontains $Config.Resolver) {
            $Config = @{
                PartitionKey = 'Domains'
                RowKey       = 'Domains'
                Resolver     = 'Google'
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force
        }

        $updated = $false

        switch ($Action) {
            'SetConfig' {
                if ($Resolver) {
                    if ($ValidResolvers -contains $Resolver) {
                        try {
                            $Config.Resolver = $Resolver
                        } catch {
                            $Config = @{
                                Resolver = $Resolver
                            }
                        }
                        $updated = $true
                    }
                }
                if ($updated) {
                    Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force
                    Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message 'DNS configuration updated' -Sev 'Info'
                    $body = [pscustomobject]@{'Results' = 'Success: DNS configuration updated.' }
                } else {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $body = [pscustomobject]@{'Results' = 'Error: No DNS resolver provided.' }
                }
            }
            'SetDkimConfig' {
                $Domain = $Domain
                $Selector = ($Selector).trim() -split '\s*,\s*'
                $DomainTable = Get-CIPPTable -Table 'Domains'
                $Filter = "RowKey eq '{0}'" -f $Domain
                $DomainInfo = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter
                $DkimSelectors = [string]($Selector | ConvertTo-Json -Compress)
                if ($DomainInfo) {
                    $DomainInfo.DkimSelectors = $DkimSelectors
                } else {
                    $DomainInfo = @{
                        'RowKey'         = $Domain
                        'PartitionKey'   = 'ManualEntry'
                        'TenantId'       = 'NoTenant'
                        'MailProviders'  = ''
                        'TenantDetails'  = ''
                        'DomainAnalyser' = ''
                        'DkimSelectors'  = $DkimSelectors
                    }
                }
                Add-CIPPAzDataTableEntity @DomainTable -Entity $DomainInfo -Force
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message "Updated DKIM selectors for domain: $Domain - Selectors: $($Selector -join ', ')" -Sev 'Info'
                $body = [pscustomobject]@{ 'Results' = "Success: DKIM selectors updated for $Domain. Selectors: $($Selector -join ', ')" }
            }
            'GetConfig' {
                $body = [pscustomobject]$Config
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message 'Retrieved DNS configuration' -Sev 'Debug'
            }
            'RemoveDomain' {
                $Filter = "RowKey eq '{0}'" -f $Domain
                $DomainRow = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter -Property PartitionKey, RowKey
                Remove-AzDataTableEntity -Force @DomainTable -Entity $DomainRow
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message "Removed Domain - $Domain " -Sev 'Info'
                $body = [pscustomobject]@{ 'Results' = "Domain removed - $Domain" }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $($name) -headers $Headers -message "DNS Config API failed. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed. $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
