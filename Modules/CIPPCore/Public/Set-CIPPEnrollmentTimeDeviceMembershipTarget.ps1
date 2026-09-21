function Set-CIPPEnrollmentTimeDeviceMembershipTarget {
    <#
    .SYNOPSIS
        Applies the enrollment-time device group to a Device Preparation policy.
    .DESCRIPTION
        The enrollment_autopilot_dpp_devicesecuritygroupids setting string in the policy body is
        only what the portal displays - Intune enrols devices into the group named by this action,
        so a policy created without it has no device group at all. The action targets an existing
        policy, so it always runs after the create.

        The action answers 200 with a validation verdict rather than failing the request, so a
        rejected group would otherwise pass silently. A group created moments earlier is not
        replicated yet and is rejected as securityGroupNotFound, which clears on its own, so only
        that verdict is retried. This is the only place the write-side URI
        and body are built.

        What was applied is recorded in CIPP's own storage, because the read-back action does not
        route on every tenant: without the marker a half-deployed profile is indistinguishable
        from a healthy one. A marker that cannot be written does not fail the apply.
    .PARAMETER PolicyId
        The configuration policy id.
    .PARAMETER GroupId
        The security group to enrol devices into.
    .PARAMETER TenantFilter
        The tenant to write to.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$GroupId,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Body = @{
        enrollmentTimeDeviceMembershipTargets = @(
            @{
                '@odata.type' = 'microsoft.graph.enrollmentTimeDeviceMembershipTarget'
                targetType    = 'staticSecurityGroup'
                targetId      = $GroupId
            }
        )
    } | ConvertTo-Json -Compress -Depth 10

    $Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/setEnrollmentTimeDeviceMembershipTarget"
    $Attempt = 0
    while ($true) {
        $Attempt++
        $Result = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -body $Body -type POST
        if ($Result.validationSucceeded -eq $true) { break }

        $StatusList = @($Result.enrollmentTimeDeviceMembershipTargetValidationStatuses)
        $NotReplicated = @($StatusList | Where-Object { $_.targetValidationErrorCode -eq 'securityGroupNotFound' }).Count -gt 0
        if (-not $NotReplicated -or $Attempt -gt 3) {
            $Statuses = $StatusList | ConvertTo-Json -Compress -Depth 10
            throw "Intune rejected the enrollment time device membership target for policy $PolicyId : $Statuses"
        }
        Start-Sleep -Seconds 10
    }

    try {
        $Table = Get-CIPPTable -TableName 'EnrollmentTimeMembershipTargets'
        $Entity = @{
            PartitionKey = [string]$TenantFilter
            RowKey       = [string]$PolicyId
            GroupId      = [string]$GroupId
            AppliedAt    = (Get-Date).ToUniversalTime().ToString('o')
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    } catch {
        Write-Information "Could not record the enrollment time device membership target for policy $PolicyId : $($_.Exception.Message)"
    }

    $Result
}
