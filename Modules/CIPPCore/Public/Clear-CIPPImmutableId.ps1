function Clear-CIPPImmutableId {
    # Legacy: kept for offboarding and already-queued scheduled tasks. New code should prolly use Clear-CIPPOnPremisesAttributes instead -bobby
    # TODO: Move Invoke-CIPPOffboardingJob(User Offboarding) to use Clear-CIPPOnPremisesAttributes instead

    [CmdletBinding()]
    param (
        $TenantFilter,
        $UserID,
        $Username, # Optional - used for better logging and scheduling messages
        $User, # Optional - if provided, will check sync status and schedule if needed
        $Headers,
        $APIName = 'Clear Immutable ID'
    )

    # If User object is provided, check if we need to schedule instead of clearing immediately
    if ($User) {
        $DisplayName = $Username ?? $UserID
        try {
            # User has ImmutableID but is not synced from on-premises - safe to clear immediately
            if ($User.onPremisesSyncEnabled -ne $true -and ![string]::IsNullOrEmpty($User.onPremisesImmutableId)) {
                Write-LogMessage -Message "User $DisplayName has an ImmutableID set but is not synced from on-premises. Proceeding to clear the ImmutableID." -TenantFilter $TenantFilter -Severity 'Warning' -APIName $APIName -headers $Headers
                # Continue to clear below
            }
            # User is synced from on-premises - must schedule for after deletion
            elseif ($User.onPremisesSyncEnabled -eq $true -and ![string]::IsNullOrEmpty($User.onPremisesImmutableId)) {
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
                $Result = "User $DisplayName does not have an ImmutableID set or it is already cleared."
                Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Info -tenant $TenantFilter
                return $Result
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Result = "Failed to schedule immutable ID clear for $DisplayName. Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Error -tenant $TenantFilter -LogData $ErrorMessage
            throw $Result
        }
    }

    # The clear itself (including restoring a soft-deleted user) lives in the shared on-premises attribute helper
    return (Clear-CIPPOnPremisesAttributes -TenantFilter $TenantFilter -UserID $UserID -Username $Username -Headers $Headers -APIName $APIName -Attributes 'onPremisesImmutableId')
}
