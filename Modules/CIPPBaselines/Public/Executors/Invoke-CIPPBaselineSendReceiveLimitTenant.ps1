function Invoke-CIPPBaselineSendReceiveLimitTenant {
    <#
    .SYNOPSIS
        SendReceiveLimitTenant executor: sets the limits on every off-limits mailbox plan.
    .DESCRIPTION
        One Set-MailboxPlan per offender the hook found, keyed on the plan GUID. Byte values
        go over the wire; Exchange renders them back as its display strings.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Guids = @($Current.offenderGuids | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })
    if ($Guids.Count -eq 0) { return }
    $MaxSend = [int64]"$($Remediate.sendLimit)" * 1MB
    $MaxReceive = [int64]"$($Remediate.receiveLimit)" * 1MB

    foreach ($Guid in $Guids) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxPlan' -cmdParams @{
            Identity = "$Guid"; MaxSendSize = $MaxSend; MaxReceiveSize = $MaxReceive
        } -useSystemMailbox $true
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set send/receive limits to $($Remediate.sendLimit)MB/$($Remediate.receiveLimit)MB on $($Guids.Count) mailbox plan(s)." -Sev 'Info'
}
