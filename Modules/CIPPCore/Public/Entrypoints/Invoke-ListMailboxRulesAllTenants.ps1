using namespace System.Net

Function Invoke-ListMailboxRulesAllTenants {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenants = if ($QueueItem -ne 'AllTenants') {
        [PSCustomObject]@{
            defaultDomainName = $QueueItem
        }
    } else {
        Get-Tenants
    }
    $Tenants | ForEach-Object -Parallel { 
        $domainName = $_.defaultDomainName
        Import-Module '.\Modules\CIPPcore'
        Import-Module '.\Modules\AzBobbyTables'

        try {
        
            $Rules = New-ExoRequest -tenantid $domainName -cmdlet 'Get-Mailbox' | ForEach-Object -Parallel {
                New-ExoRequest -Anchor $_.UserPrincipalName -tenantid $domainName -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $_.GUID }
            }
            foreach ($Rule in $Rules) {
                $GraphRequest = @{
                    Rules        = [string]($Rule | ConvertTo-Json)
                    RowKey       = [string](New-Guid).guid
                    Tenant       = [string]$domainName
                    PartitionKey = 'mailboxrules'
                }
                $Table = Get-CIPPTable -TableName cachembxrules
                Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
            }
        } catch {
            $Rules = @{
                Name = "Could not connect to tenant $($_.Exception.message)"
            } | ConvertTo-Json
            $GraphRequest = @{
                Rules        = [string]$Rules
                RowKey       = [string]$domainName
                Tenant       = [string]$domainName

                PartitionKey = 'mailboxrules'
            }
            $Table = Get-CIPPTable -TableName cachembxrules
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
        }
    }



    $Table = Get-CIPPTable -TableName cachembxrules
    Write-Host "$($GraphRequest.RowKey) - $($GraphRequest.tenant)"
    Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null

}
