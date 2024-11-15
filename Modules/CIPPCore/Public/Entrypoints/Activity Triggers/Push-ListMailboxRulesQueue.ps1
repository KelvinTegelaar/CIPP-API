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
        $Rules = New-ExoRequest -tenantid $domainName -cmdlet 'Get-Mailbox' -Select 'userPrincipalName,GUID' | ForEach-Object -Parallel {
            Import-Module CIPPCore
            $MbxRules = New-ExoRequest -Anchor $_.UserPrincipalName -tenantid $using:domainName -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $_.GUID; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' }
            foreach ($Rule in $MbxRules) {
                $Rule | Add-Member -NotePropertyName 'UserPrincipalName' -NotePropertyValue $_.userPrincipalName
                $Rule
            }
        }
        if (($Rules | Measure-Object).Count -gt 0) {
            foreach ($Rule in $Rules) {
                $GraphRequest = [PSCustomObject]@{
                    Rules        = [string]($Rule | ConvertTo-Json)
                    RowKey       = [string](New-Guid).guid
                    Tenant       = [string]$domainName
                    PartitionKey = 'mailboxrules'
                }

            }
        } else {
            $Rules = @{
                Name = 'No rules found'
            } | ConvertTo-Json
            $GraphRequest = [PSCustomObject]@{
                Rules        = [string]$Rules
                RowKey       = [string]$domainName
                Tenant       = [string]$domainName
                PartitionKey = 'mailboxrules'
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
            PartitionKey = 'mailboxrules'
        }
    }
    Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
}
