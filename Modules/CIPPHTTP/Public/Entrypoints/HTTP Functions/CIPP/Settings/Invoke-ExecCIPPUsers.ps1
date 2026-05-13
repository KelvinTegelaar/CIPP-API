function Invoke-ExecCIPPUsers {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $Table = Get-CippTable -tablename 'allowedUsers'

    switch ($Action) {
        'AddUpdate' {
            try {
                $UPN = $Request.Body.UPN
                if ([string]::IsNullOrWhiteSpace($UPN)) {
                    throw 'UPN (email) is required'
                }
                $UPN = $UPN.Trim()

                $Roles = @($Request.Body.Roles)
                if ($Roles.Count -eq 0) {
                    throw 'At least one role must be assigned'
                }

                # Validate roles exist (built-in + custom)
                $CippRolesJson = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config\cipp-roles.json'
                $BuiltInRoles = if (Test-Path $CippRolesJson) {
                    ([System.IO.File]::ReadAllText($CippRolesJson) | ConvertFrom-Json).PSObject.Properties.Name
                } else {
                    @('readonly', 'editor', 'admin', 'superadmin')
                }

                $CustomRolesTable = Get-CippTable -tablename 'CustomRoles'
                $CustomRoles = @((Get-CIPPAzDataTableEntity @CustomRolesTable).RowKey)
                $AllValidRoles = @($BuiltInRoles) + @($CustomRoles) + @('anonymous', 'authenticated')

                foreach ($Role in $Roles) {
                    if ($Role -notin $AllValidRoles) {
                        throw "Invalid role: $Role. Valid roles: $($AllValidRoles -join ', ')"
                    }
                }

                $Entity = @{
                    PartitionKey = 'User'
                    RowKey       = $UPN
                    Roles        = [string](@($Roles) | ConvertTo-Json -Compress -AsArray)
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

                # Invalidate the in-memory user cache so changes apply immediately
                try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

                $Result = "Successfully added/updated user $UPN with roles: $($Roles -join ', ')"
                Write-LogMessage -API $APIName -headers $Headers -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to add/update user: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        'Delete' {
            try {
                $UPN = $Request.Body.UPN
                if ([string]::IsNullOrWhiteSpace($UPN)) {
                    throw 'UPN (email) is required'
                }
                $UPN = $UPN.Trim()

                # Self-lockout protection: prevent removing yourself
                $CurrentUser = $Request.Headers.'x-ms-client-principal-name'
                if ($CurrentUser -and $UPN -ieq $CurrentUser) {
                    throw 'Cannot remove your own user account. This would lock you out.'
                }

                $ExistingEntity = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$UPN'"
                if (-not $ExistingEntity) {
                    throw "User $UPN not found in the allowed users table"
                }

                Remove-AzDataTableEntity -Force @Table -Entity $ExistingEntity
                try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

                $Result = "Successfully removed user $UPN"
                Write-LogMessage -API $APIName -headers $Headers -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to delete user: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        default {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Unknown action: $Action. Valid actions: AddUpdate, Delete" }
            }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Result }
    }
}
