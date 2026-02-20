function Push-GetMailboxRulesBatch {
    <#
    .SYNOPSIS
        Caches mailbox rules for a batch of mailboxes

    .PARAMETER InputObject
        The batch object containing TenantFilter and Mailboxes array
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $Mailboxes = $Item.Mailboxes
    $BatchNumber = $Item.BatchNumber
    $TotalBatches = $Item.TotalBatches
    $QueueId = $Item.QueueId

    try {
        Write-Information "Processing mailbox rules batch $BatchNumber/$TotalBatches for tenant $TenantFilter with $($Mailboxes.Count) mailboxes"

        # Build bulk request for mailbox rules
        $Request = $Mailboxes | ForEach-Object {
            @{
                OperationGuid = $_
                CmdletInput   = @{
                    CmdletName = 'Get-InboxRule'
                    Parameters = @{
                        Mailbox = $_
                    }
                }
            }
        }

        $Rules = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Request) | Where-Object { $_.Identity }

        Write-Information "Retrieved $($Rules.Count) rules from batch $BatchNumber/$TotalBatches"

        # Add metadata and return for aggregation
        if (($Rules | Measure-Object).Count -gt 0) {
            $RulesWithMetadata = foreach ($Rule in $Rules) {
                $Rule | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter -Force
                $Rule | Add-Member -NotePropertyName 'UserPrincipalName' -NotePropertyValue $Rule.OperationGuid -Force
                $Rule
            }
            return , $RulesWithMetadata
        } else {
            Write-Information "No rules found in batch $BatchNumber/$TotalBatches"
            return , @()
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to process mailbox rules batch $BatchNumber/$TotalBatches : $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
