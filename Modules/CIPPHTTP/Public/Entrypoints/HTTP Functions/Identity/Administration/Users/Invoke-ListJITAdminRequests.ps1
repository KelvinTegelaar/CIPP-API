function Invoke-ListJITAdminRequests {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    .SYNOPSIS
        List JIT Admin approval requests
    .DESCRIPTION
        Lists JIT Admin requests that went through the approval flow, with their decisions and whether the calling user can approve them.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Table = Get-CIPPTable -TableName 'JITAdminRequests'
    $Filter = if ($TenantFilter -eq 'AllTenants') {
        "PartitionKey eq 'JITAdminRequest'"
    } else {
        "PartitionKey eq 'JITAdminRequest' and Tenant eq '$(ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String)'"
    }
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        $AllowedDomains = (Get-Tenants -IncludeErrors).Where({ $_.customerId -in $AllowedTenants }).defaultDomainName
        $Rows = $Rows.Where({ $_.Tenant -in $AllowedDomains })
    }

    $CallingUser = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    $CallerRoles = @(Get-CIPPAccessRole -Request $Request)

    $Results = foreach ($Row in $Rows) {
        $Decisions = @($Row.Decisions | ConvertFrom-Json)
        $ApproverRoles = @($Row.ApproverRoles | ConvertFrom-Json)
        $CanDecide = $Row.State -eq 'Pending' -and $Decisions.By -notcontains $CallingUser -and $CallerRoles.Where({ $_ -in $ApproverRoles }).Count -gt 0
        [pscustomobject]@{
            RequestId     = $Row.RowKey
            State         = $Row.State
            Tenant        = $Row.Tenant
            TargetUser    = $Row.TargetUser
            Roles         = $Row.RoleNames
            Groups        = $Row.GroupNames
            Reason        = $Row.Reason
            StartDate     = [int64]$Row.StartDate
            EndDate       = [int64]$Row.EndDate
            RequestedBy   = $Row.RequestedBy
            RequestedAt   = $Row.RequestedAt
            ApproverRoles = $ApproverRoles -join ', '
            Approvals     = '{0} of {1}' -f @($Decisions.Where({ $_.Decision -eq 'Approve' })).Count, $Row.RequiredApprovals
            Decisions     = $Decisions
            Results       = $Row.Results
            CanApprove    = $CanDecide -and $CallingUser -ne $Row.RequestedBy
            CanReject     = $CanDecide
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results | Sort-Object -Property RequestedAt -Descending)
        })
}
