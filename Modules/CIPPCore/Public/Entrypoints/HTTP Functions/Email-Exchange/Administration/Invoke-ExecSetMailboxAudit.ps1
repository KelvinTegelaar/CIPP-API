function Invoke-ExecSetMailboxAudit {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Body.tenantFilter
    $UserID = $Request.Body.userID
    $AuditEnabled = $Request.Body.AuditEnabled
    $AuditActions = $Request.Body.AuditActions

    try {
        $Results = [System.Collections.ArrayList]::new()

        # Build the Set-Mailbox parameters
        $Params = @{
            Identity = $UserID
        }

        # Handle specific audit actions (always set the full, final list for each access type)
        if ($AuditActions -and $AuditActions.Count -gt 0) {
            # Supported actions for each access type (from Microsoft documentation table)
            $SupportedOwner = @(
                'ApplyRecord',
                'AttachmentAccess',
                'Create',
                'HardDelete',
                'MailboxLogin',
                'MailItemsAccessed',
                'Move',
                'MoveToDeletedItems',
                'RecordDelete',
                'SearchQueryInitiated',
                'Send',
                'SoftDelete',
                'Update',
                'UpdateCalendarDelegation',
                'UpdateFolderPermissions',
                'UpdateInboxRules'
            )
            $SupportedDelegate = @(
                'ApplyRecord',
                'AttachmentAccess',
                'Create',
                'FolderBind',
                'HardDelete',
                'MailItemsAccessed',
                'Move',
                'MoveToDeletedItems',
                'RecordDelete',
                'SendAs',
                'SendOnBehalf',
                'SoftDelete',
                'Update',
                'UpdateFolderPermissions',
                'UpdateInboxRules'
            )

            $SupportedAdmin = @(
                'ApplyRecord',
                'AttachmentAccess',
                'Copy',
                'Create',
                'FolderBind',
                'HardDelete',
                'MailItemsAccessed',
                'Move',
                'MoveToDeletedItems',
                'RecordDelete',
                'Send',
                'SendAs',
                'SendOnBehalf',
                'SoftDelete',
                'Update',
                'UpdateCalendarDelegation',
                'UpdateFolderPermissions',
                'UpdateInboxRules'
            )

            # Build the full, final list for each access type
            $FinalOwner = @()
            $FinalDelegate = @()
            $FinalAdmin = @()

            foreach ($Action in $AuditActions) {
                if ($Action.AccessType -eq 'Owner' -and $Action.Modification -eq 'Add' -and $SupportedOwner -contains $Action.Action) {
                    $FinalOwner += $Action.Action
                }
                if ($Action.AccessType -eq 'Delegate' -and $Action.Modification -eq 'Add' -and $SupportedDelegate -contains $Action.Action) {
                    $FinalDelegate += $Action.Action
                }
                if ($Action.AccessType -eq 'Admin' -and $Action.Modification -eq 'Add' -and $SupportedAdmin -contains $Action.Action) {
                    $FinalAdmin += $Action.Action
                }
            }

            if ($FinalOwner.Count -gt 0) {
                $Params.AuditOwner = $FinalOwner
            }
            if ($FinalDelegate.Count -gt 0) {
                $Params.AuditDelegate = $FinalDelegate
            }
            if ($FinalAdmin.Count -gt 0) {
                $Params.AuditAdmin = $FinalAdmin
            }
        }


        # Only execute Set-Mailbox if we have parameters to set
        if ($Params.Count -gt 1) {
            # Handle AuditOwner, AuditDelegate, AuditAdmin separately for Add/Remove
            $auditTypes = @('AuditOwner', 'AuditDelegate', 'AuditAdmin')
            $baseParams = $Params.Clone()
            $auditCalls = @()

            foreach ($auditType in $auditTypes) {
                if ($Params.ContainsKey($auditType)) {
                    $add = $Params[$auditType]['Add']
                    $remove = $Params[$auditType]['Remove']
                    if ($add -and $remove) {
                        # Call Set-Mailbox twice: once for Add, once for Remove
                        $pAdd = $baseParams.Clone()
                        $pAdd[$auditType] = $add
                        $auditCalls += ,$pAdd
                        $pRemove = $baseParams.Clone()
                        $pRemove[$auditType] = @{Remove = $remove}
                        $auditCalls += ,$pRemove
                        $Params.Remove($auditType)
                    } elseif ($add) {
                        $Params[$auditType] = $add
                    } elseif ($remove) {
                        $Params[$auditType] = @{Remove = $remove}
                    }
                }
            }

            # Main call (for AuditEnabled and any single Add/Remove)
            if ($Params.Count -gt 1) {
                $SetResult = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams $Params -useSystemMailbox $true
            }

            # Additional calls for Add/Remove splits
            foreach ($ac in $auditCalls) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams $ac -useSystemMailbox $true
            }

            if ($AuditEnabled -eq $true) {
                $null = $Results.Add('Mailbox auditing has been enabled')
            } elseif ($AuditEnabled -eq $false) {
                $null = $Results.Add('Mailbox auditing has been disabled')
            }

            if ($AuditActions -and $AuditActions.Count -gt 0) {
                $ActionSummary = ($AuditActions | ForEach-Object {
                    "$($_.Modification) $($_.Action) for $($_.AccessType)"
                }) -join ', '
                $null = $Results.Add("Modified audit actions: $ActionSummary")
            }
        }

        if ($Results.Count -eq 0) {
            $null = $Results.Add('No changes were requested')
        }

        Write-LogMessage -API 'ExecSetMailboxAudit' -message "Set mailbox audit config for $UserID" -Sev 'Info' -tenant $TenantFilter

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results = @($Results)
            }
        })

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ExecSetMailboxAudit' -message "Failed to set mailbox audit config for $UserID`: $($_.Exception.Message)" -Sev 'Error' -LogData $ErrorMessage -tenant $TenantFilter
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                Results = @("Failed to set mailbox audit config: $($_.Exception.Message)")
            }
        })
    }
}
