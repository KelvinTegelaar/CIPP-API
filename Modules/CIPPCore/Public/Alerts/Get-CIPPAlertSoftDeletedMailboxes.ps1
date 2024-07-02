function Get-CIPPAlertSoftDeletedMailboxes {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $Select = 'ExchangeGuid,ArchiveGuid,WhenSoftDeleted,UserPrincipalName,IsInactiveMailbox'

    try {
        $SoftDeletedMailBoxes = New-ExoRequest -tenantid $TenantFilter -cmdlet 'get-mailbox' -cmdParams @{SoftDeletedMailbox = $true} -Select $Select | Select-Object ExchangeGuid, ArchiveGuid, WhenSoftDeleted, @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } }, IsInactiveMailbox
        
        # Filter out the mailboxes where IsInactiveMailbox is $true
        $AlertData = $SoftDeletedMailBoxes | Where-Object { $_.IsInactiveMailbox -ne $true }
        
        # Write the alert trace with the filtered data
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check for soft deleted mailboxes in $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}