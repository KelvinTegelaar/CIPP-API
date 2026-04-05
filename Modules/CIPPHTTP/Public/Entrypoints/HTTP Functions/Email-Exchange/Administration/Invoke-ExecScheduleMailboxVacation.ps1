function Invoke-ExecScheduleMailboxVacation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Body.tenantFilter
        $MailboxOwners = @($Request.Body.mailboxOwners)
        $Delegates = @($Request.Body.delegates)
        $PermissionTypes = @($Request.Body.permissionTypes)
        $AutoMap = if ($null -ne $Request.Body.autoMap) { [bool]$Request.Body.autoMap } else { $true }
        $IncludeCalendar = [bool]$Request.Body.includeCalendar
        $CalendarPermission = $Request.Body.calendarPermission.value ?? $Request.Body.calendarPermission
        $CanViewPrivateItems = [bool]$Request.Body.canViewPrivateItems
        $StartDate = $Request.Body.startDate
        $EndDate = $Request.Body.endDate

        # Extract UPNs from addedFields
        $OwnerUPNs = @($MailboxOwners | ForEach-Object { $_.addedFields.userPrincipalName ?? $_.value })
        $DelegateUPNs = @($Delegates | ForEach-Object { $_.addedFields.userPrincipalName ?? $_.value })

        if ($OwnerUPNs.Count -eq 0 -or $DelegateUPNs.Count -eq 0 -or $PermissionTypes.Count -eq 0) {
            throw 'Mailbox owners, delegates, and permission types are required.'
        }

        # Build mailbox permissions array: Cartesian product of owners x delegates x permissionTypes
        $MailboxPermissions = @(foreach ($owner in $OwnerUPNs) {
                foreach ($delegate in $DelegateUPNs) {
                    foreach ($permType in $PermissionTypes) {
                        $level = $permType.value ?? $permType
                        [PSCustomObject]@{
                            UserId          = $owner
                            AccessUser      = $delegate
                            PermissionLevel = $level
                            AutoMap         = $AutoMap
                        }
                    }
                }
            })

        # Build calendar permissions array if requested
        $CalendarPermissions = @()
        if ($IncludeCalendar -and $CalendarPermission) {
            $CalendarPermissions = @(foreach ($owner in $OwnerUPNs) {
                    # Resolve the calendar folder name for this owner's mailbox locale at schedule time.
                    $FolderStats = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{
                        Identity    = $owner
                        FolderScope = 'Calendar'
                    } -Anchor $owner | Where-Object { $_.FolderType -eq 'Calendar' }
                    $CalFolderName = if ($FolderStats) { $FolderStats.Name } else { 'Calendar' }

                    foreach ($delegate in $DelegateUPNs) {
                        [PSCustomObject]@{
                            UserID               = $owner
                            UserToGetPermissions = $delegate
                            FolderName           = $CalFolderName
                            Permissions          = $CalendarPermission
                            CanViewPrivateItems  = $CanViewPrivateItems
                        }
                    }
                })
        }

        # Build display names for task naming
        $OwnerDisplay = ($OwnerUPNs | Select-Object -First 3) -join ', '
        if ($OwnerUPNs.Count -gt 3) { $OwnerDisplay += " (+$($OwnerUPNs.Count - 3) more)" }
        $DelegateDisplay = ($DelegateUPNs | Select-Object -First 3) -join ', '
        if ($DelegateUPNs.Count -gt 3) { $DelegateDisplay += " (+$($DelegateUPNs.Count - 3) more)" }

        # Create Add task
        $AddParameters = [PSCustomObject]@{
            TenantFilter        = $TenantFilter
            Action              = 'Add'
            MailboxPermissions  = $MailboxPermissions
            CalendarPermissions = $CalendarPermissions
            APIName             = $APIName
        }

        $AddTaskBody = [PSCustomObject]@{
            TenantFilter  = $TenantFilter
            Name          = "Add Mailbox Vacation Mode: $DelegateDisplay -> $OwnerDisplay"
            Command       = @{
                value = 'Set-CIPPMailboxVacation'
                label = 'Set-CIPPMailboxVacation'
            }
            Parameters    = $AddParameters
            ScheduledTime = [int64]$StartDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }

        Add-CIPPScheduledTask -Task $AddTaskBody -hidden $false

        # Create Remove task (separate Parameters object to avoid reference mutation)
        $RemoveParameters = [PSCustomObject]@{
            TenantFilter        = $TenantFilter
            Action              = 'Remove'
            MailboxPermissions  = $MailboxPermissions
            CalendarPermissions = $CalendarPermissions
            APIName             = $APIName
        }

        $RemoveTaskBody = [PSCustomObject]@{
            TenantFilter  = $TenantFilter
            Name          = "Remove Mailbox Vacation Mode: $DelegateDisplay -> $OwnerDisplay"
            Command       = @{
                value = 'Set-CIPPMailboxVacation'
                label = 'Set-CIPPMailboxVacation'
            }
            Parameters    = $RemoveParameters
            ScheduledTime = [int64]$EndDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }

        Add-CIPPScheduledTask -Task $RemoveTaskBody -hidden $false

        $Result = "Successfully scheduled mailbox vacation mode for $DelegateDisplay -> $OwnerDisplay."
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to schedule mailbox vacation mode: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
