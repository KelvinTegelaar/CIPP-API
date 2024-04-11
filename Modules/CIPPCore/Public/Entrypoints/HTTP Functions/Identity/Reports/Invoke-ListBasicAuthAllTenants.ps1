using namespace System.Net

Function Invoke-ListBasicAuthAllTenants {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        
    Get-Tenants | ForEach-Object -Parallel { 
        $domainName = $_.defaultDomainName
        Import-Module '.\Modules\AzBobbyTables'
        Import-Module '.\Modules\CIPPCore'

        $currentTime = Get-Date -Format 'yyyy-MM-ddTHH:MM:ss'
        $ts = (Get-Date).AddDays(-30)
        $endTime = $ts.ToString('yyyy-MM-ddTHH:MM:ss')
        $filters = "createdDateTime ge $($endTime)Z and createdDateTime lt $($currentTime)Z and (clientAppUsed eq 'AutoDiscover' or clientAppUsed eq 'Exchange ActiveSync' or clientAppUsed eq 'Exchange Online PowerShell' or clientAppUsed eq 'Exchange Web Services' or clientAppUsed eq 'IMAP4' or clientAppUsed eq 'MAPI Over HTTP' or clientAppUsed eq 'Offline Address Book' or clientAppUsed eq 'Outlook Anywhere (RPC over HTTP)' or clientAppUsed eq 'Other clients' or clientAppUsed eq 'POP3' or clientAppUsed eq 'Reporting Web Services' or clientAppUsed eq 'Authenticated SMTP' or clientAppUsed eq 'Outlook Service')"
        try {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&filter=$($filters)" -tenantid $domainName -ErrorAction stop | Sort-Object -Unique -Property clientAppUsed | ForEach-Object {
                @{
                    Tenant            = $domainName
                    clientAppUsed     = $_.clientAppUsed
                    userPrincipalName = $_.UserPrincipalName
                    RowKey            = "$($_.UserPrincipalName)-$($_.clientAppUsed)"
                    PartitionKey      = 'basicauth'
                }
            }
        } catch {
            $GraphRequest = @{
                Tenant            = $domainName
                clientAppUsed     = "Could not connect to Tenant: $($_.Exception.message)"
                userPrincipalName = $domainName
                RowKey            = $domainName
                PartitionKey      = 'basicauth'
            }
        } 
        $Table = Get-CIPPTable -TableName cachebasicauth
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null

    }



}
