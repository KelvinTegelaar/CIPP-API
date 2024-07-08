function Set-CIPPUserSchemaProperties {
    <#
    .SYNOPSIS
    Set Schema Properties for a user

    .DESCRIPTION
    Uses scheam extensions to set properties for a user

    .PARAMETER TenantFilter
    Tenant for user

    .PARAMETER UserId
    One or more user ids to set properties for

    .PARAMETER Properties
    Hashtable of properties to set

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [object]$Users
    )

    $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' }
    $int = 0
    $Requests = foreach ($User in $Users) {
        @{
            id        = $int++
            method    = 'PATCH'
            url       = "users/$($User.userId)"
            body      = @{
                "$($Schema.id)" = $User.Properties
            }
            'headers' = @{
                'Content-Type' = 'application/json'
            }
        }
    }

    if ($PSCmdlet.ShouldProcess("User: $($Users.userId -join ', ')", 'Set Schema Properties')) {
        $Requests = New-GraphBulkRequest -tenantid $tenantfilter -Requests @($Requests)
    }
}