function Push-StoreMailboxRules {
    <#
    .SYNOPSIS
        Post-execution function to aggregate and store all mailbox rules

    .DESCRIPTION
        Collects results from all batches and stores them in the reporting database

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $Results = $Item.Results

    try {
        Write-Information "Storing mailbox rules for tenant $TenantFilter"
        Write-Information "Received $($Results.Count) batch results"

        # Aggregate all rules from batches
        $AllRules = [System.Collections.Generic.List[object]]::new()

        foreach ($BatchResult in $Results) {
            # Activity functions may return an array
            $ActualResult = $BatchResult
            if ($BatchResult -is [array] -and $BatchResult.Count -gt 0) {
                Write-Information "Result is array with $($BatchResult.Count) elements"
                # If first element is array of rules, use it
                if ($BatchResult[0] -is [array]) {
                    $ActualResult = $BatchResult[0]
                } else {
                    $ActualResult = $BatchResult
                }
            }

            if ($ActualResult) {
                if ($ActualResult -is [array]) {
                    Write-Information "Adding $($ActualResult.Count) rules from batch"
                    $AllRules.AddRange($ActualResult)
                } else {
                    Write-Information 'Adding 1 rule from batch'
                    $AllRules.Add($ActualResult)
                }
            }
        }

        Write-Information "Aggregated $($AllRules.Count) total mailbox rules"

        # Store all rules
        if ($AllRules.Count -gt 0) {
            $AllRules | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllRules.Count) mailbox rules" -sev Info
        } else {
            # Store empty result to indicate successful check with no rules
            @() | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No mailbox rules found to cache' -sev Info
        }

        return

    } catch {
        $ErrorMsg = "Failed to store mailbox rules for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
