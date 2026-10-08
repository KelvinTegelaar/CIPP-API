function Get-CIPPJITAdminApprovalRequirement {
    <#
    .SYNOPSIS
        Returns the instance-wide JIT admin approval requirement for the requested roles, or $null when no approval is needed
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string[]]$Roles)

    $Table = Get-CIPPTable -TableName Config
    $Settings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'JITAdminSettings' and RowKey eq 'JITAdminSettings'"
    if ($Settings.RequireApproval -ne $true) { return $null }

    $TriggerRoles = @(if ($Settings.ApprovalTriggerRoles) { ($Settings.ApprovalTriggerRoles | ConvertFrom-Json).value }).Where({ $_ })
    if ($TriggerRoles.Count -gt 0 -and @($Roles).Where({ $_ -in $TriggerRoles }).Count -eq 0) { return $null }

    [pscustomobject]@{
        ApproverRoles     = @(if ($Settings.ApproverRoles) { $Settings.ApproverRoles | ConvertFrom-Json })
        RequiredApprovals = [math]::Max(1, [int]$Settings.RequiredApprovals)
    }
}
