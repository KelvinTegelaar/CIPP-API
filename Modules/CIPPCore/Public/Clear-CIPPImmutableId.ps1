function Clear-CIPPImmutableId {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $UserID,
        $Username, # Optional - used for better logging and scheduling messages
        $User, # Optional - if provided, will check sync status and schedule if needed
        $Headers,
        $APIName = 'Clear Immutable ID'
    )

    try {
        # If User object is provided, check if we need to schedule instead of clearing immediately
        if ($User) {
            # User has ImmutableID but is not synced from on-premises - safe to clear immediately
            if ($User.onPremisesSyncEnabled -ne $true -and ![string]::IsNullOrEmpty($User.onPremisesImmutableId)) {
                $DisplayName = $Username ?? $UserID
                Write-LogMessage -Message "User $DisplayName has an ImmutableID set but is not synced from on-premises. Proceeding to clear the ImmutableID." -TenantFilter $TenantFilter -Severity 'Warning' -APIName $APIName -headers $Headers
                # Continue to clear below
            }
            # User is synced from on-premises - must schedule for after deletion
            elseif ($User.onPremisesSyncEnabled -eq $true -and ![string]::IsNullOrEmpty($User.onPremisesImmutableId)) {
                $DisplayName = $Username ?? $UserID
                Write-LogMessage -Message "User $DisplayName is synced from on-premises. Scheduling an Immutable ID clear for when the user account has been soft deleted." -TenantFilter $TenantFilter -Severity 'Warning' -APIName $APIName -headers $Headers

                $ScheduledTask = @{
                    TenantFilter  = $TenantFilter
                    Name          = "Clear Immutable ID: $DisplayName"
                    Command       = @{ value = 'Clear-CIPPImmutableID' }
                    Parameters    = [pscustomobject]@{
                        UserID       = $UserID
                        TenantFilter = $TenantFilter
                        APIName      = $APIName
                    }
                    Trigger       = @{
                        Type               = 'DeltaQuery'
                        DeltaResource      = 'users'
                        ResourceFilter     = @($UserID)
                        EventType          = 'deleted'
                        UseConditions      = $false
                        ExecutePerResource = $true
                        ExecutionMode      = 'once'
                    }
                    ScheduledTime = [int64](([datetime]::UtcNow).AddMinutes(5) - (Get-Date '1/1/1970')).TotalSeconds
                    Recurrence    = '15m'
                    PostExecution = @{
                        Webhook = $false
                        Email   = $false
                        PSA     = $false
                    }
                }
                Add-CIPPScheduledTask -Task $ScheduledTask -hidden $false -DisallowDuplicateName $true
                return 'Scheduled Immutable ID clear task for when the user account is no longer synced in the on-premises directory.'
            }
            # User has no ImmutableID or is already clear
            else {
                $DisplayName = $Username ?? $UserID
                $Result = "User $DisplayName does not have an ImmutableID set or it is already cleared."
                Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Info -tenant $TenantFilter
                return $Result
            }
        }

        # Perform the actual clear operation
        try {
            $UserObj = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UserID" -tenantid $TenantFilter -ErrorAction SilentlyContinue
        } catch {
            # User might be deleted, try to restore it
            $DeletedUser = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/$UserID" -tenantid $TenantFilter
            if ($DeletedUser.id) {
                # Restore deleted user object
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/$UserID/restore" -tenantid $TenantFilter -type POST
                Write-LogMessage -headers $Headers -API $APIName -message "Restored deleted user $UserID to clear immutable ID" -sev Info -tenant $TenantFilter
            }
        }

        $Body = [pscustomobject]@{ onPremisesImmutableId = $null }
        $Body = ConvertTo-Json -InputObject $Body -Depth 5 -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserID" -tenantid $TenantFilter -type PATCH -body $Body
        $DisplayName = $Username ?? $UserID
        $Result = "Successfully cleared immutable ID for user $DisplayName"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Info -tenant $TenantFilter
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $DisplayName = $Username ?? $UserID
        $Result = "Failed to clear immutable ID for $DisplayName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
