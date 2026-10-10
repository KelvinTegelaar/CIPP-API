function Remove-CIPPEnrollmentTimeDeviceMembershipMarker {
    <#
    .SYNOPSIS
        Forgets the enrollment-time device group recorded against a Device Preparation policy.
    .DESCRIPTION
        Called when a policy is deleted for recreation: the recreated profile gets a new id, so a
        marker left behind under the old one would answer for a policy that no longer exists.
        A marker that cannot be removed does not fail the recreation, and a row that was never
        written is not an error - the 404 is non-terminating, so it only reaches the catch with
        -ErrorAction Stop.
    .PARAMETER PolicyId
        The configuration policy id being deleted.
    .PARAMETER TenantFilter
        The tenant the policy belongs to.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $Table = Get-CIPPTable -TableName 'EnrollmentTimeMembershipTargets'
        $Entity = @{ PartitionKey = [string]$TenantFilter; RowKey = [string]$PolicyId }
        if ($PSCmdlet.ShouldProcess($PolicyId, 'Remove enrollment time device membership marker')) {
            Remove-AzDataTableEntity @Table -Entity ([pscustomobject]$Entity) -Force -ErrorAction Stop
        }
    } catch {
        Write-Information "Could not remove the enrollment time device membership marker for policy $PolicyId : $($_.Exception.Message)"
    }
}
