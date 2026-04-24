function Push-ListMailboxRulesQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    # Write out the queue message and metadata to the information log.
    Write-Host "PowerShell queue trigger function processed work item: $($Item.defaultDomainName)"

    $domainName = $Item.defaultDomainName

    $Table = Get-CIPPTable -TableName cachembxrules
    try {
        $Mailboxes = New-ExoRequest -tenantid $domainName -cmdlet 'Get-Mailbox' -Select 'userPrincipalName,GUID'
        $Request = $Mailboxes | ForEach-Object {
            @{
                OperationGuid = $_.UserPrincipalName
                CmdletInput   = @{
                    CmdletName = 'Get-InboxRule'
                    Parameters = @{
                        Mailbox = $_.UserPrincipalName
                    }
                }
            }
        }

        $Rules = New-ExoBulkRequest -tenantid $domainName -cmdletArray @($Request) | Where-Object { $_.Identity }
        if (($Rules | Measure-Object).Count -gt 0) {
            $GraphRequest = foreach ($Rule in $Rules) {
                [PSCustomObject]@{
                    Rules        = [string]($Rule | ConvertTo-Json)
                    RowKey       = [string](New-Guid).guid
                    Tenant       = [string]$domainName
                    PartitionKey = 'MailboxRules'
                }

            }
        } else {
            $Rules = @(@{
                    Name = 'No rules found'
                }) | ConvertTo-Json
            $GraphRequest = [PSCustomObject]@{
                Rules        = [string]$Rules
                RowKey       = [string]$domainName
                Tenant       = [string]$domainName
                PartitionKey = 'MailboxRules'
            }
        }
    } catch {
        $Rules = @{
            Name = "Could not connect to tenant $($_.Exception.message)"
        } | ConvertTo-Json
        $GraphRequest = [PSCustomObject]@{
            Rules        = [string]$Rules
            RowKey       = [string]$domainName
            Tenant       = [string]$domainName
            PartitionKey = 'MailboxRules'
        }
    }
    Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
}
