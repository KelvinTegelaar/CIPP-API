function Set-CIPPDBCacheMailboxRules {
    <#
    .SYNOPSIS
        Caches mailbox rules for a tenant

    .PARAMETER TenantFilter
        The tenant to cache mailbox rules for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mailbox rules' -sev Debug

        # Get mailboxes
        $Mailboxes = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -Select 'userPrincipalName,GUID'
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

        $Rules = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Request) | Where-Object { $_.Identity }

        if (($Rules | Measure-Object).Count -gt 0) {
            $MailboxRules = foreach ($Rule in $Rules) {
                $Rule | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter -Force
                $Rule | Add-Member -NotePropertyName 'UserPrincipalName' -NotePropertyValue $Rule.OperationGuid -Force
                $Rule
            }

            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -Data @($MailboxRules)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -Data @($MailboxRules) -Count

            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($MailboxRules.Count) mailbox rules successfully" -sev Debug
        } else {
            # Cache empty result to indicate successful check with no rules
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -Data @()
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -Data @() -Count

            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No mailbox rules found' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mailbox rules: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
