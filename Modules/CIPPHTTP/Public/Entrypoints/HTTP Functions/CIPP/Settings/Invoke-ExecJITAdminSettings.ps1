function Invoke-ExecJITAdminSettings {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $StatusCode = [HttpStatusCode]::OK

    try {
        $Table = Get-CIPPTable -TableName Config
        $Filter = "PartitionKey eq 'JITAdminSettings' and RowKey eq 'JITAdminSettings'"
        $JITAdminConfig = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $JITAdminConfig) {
            $JITAdminConfig = [pscustomobject]@{
                PartitionKey = 'JITAdminSettings'
                RowKey       = 'JITAdminSettings'
                MaxDuration  = $null  # null means no limit
            }
        }

        $Action = if ($Request.Body.Action) { $Request.Body.Action } else { $Request.Query.Action }

        $Results = switch ($Action) {
            'Get' {
                @{
                    MaxDuration          = $JITAdminConfig.MaxDuration
                    RequireApproval      = [bool]$JITAdminConfig.RequireApproval
                    ApprovalTriggerRoles = @(if ($JITAdminConfig.ApprovalTriggerRoles) { $JITAdminConfig.ApprovalTriggerRoles | ConvertFrom-Json })
                    ApproverRoles        = @(if ($JITAdminConfig.ApproverRoles) { $JITAdminConfig.ApproverRoles | ConvertFrom-Json | ForEach-Object { @{ label = $_; value = $_ } } })
                    RequiredApprovals    = [math]::Max(1, [int]$JITAdminConfig.RequiredApprovals)
                }
            }
            'Set' {
                $MaxDuration = $Request.Body.MaxDuration.value
                Write-Host "MAx dur: $($MaxDuration)"
                # Validate ISO 8601 duration format if provided
                if (![string]::IsNullOrWhiteSpace($MaxDuration)) {
                    try {
                        # Test if it's a valid ISO 8601 duration
                        $null = [System.Xml.XmlConvert]::ToTimeSpan($MaxDuration)
                        $JITAdminConfig | Add-Member -NotePropertyName MaxDuration -NotePropertyValue $MaxDuration -Force
                    } catch {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        @{
                            Results = 'Error: Invalid ISO 8601 duration format. Expected format like PT4H, P1D, P4W, etc.'
                        }
                        break
                    }
                } else {
                    # Empty or null means no limit
                    $JITAdminConfig.MaxDuration = $null
                }

                # Roles that need approval; none selected means every JIT Admin request needs approval
                $TriggerRoles = @($Request.Body.ApprovalTriggerRoles | Where-Object { $_.value } | ForEach-Object { @{ label = $_.label; value = $_.value } })
                # CIPP roles whose users can approve requests
                $ApproverRoles = @($Request.Body.ApproverRoles.value | Where-Object { $_ })
                if ([bool]$Request.Body.RequireApproval -and $ApproverRoles.Count -eq 0) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    @{ Results = 'Error: Select at least one approver role when approval is required.' }
                    break
                }
                $JITAdminConfig | Add-Member -NotePropertyName RequireApproval -NotePropertyValue ([bool]$Request.Body.RequireApproval) -Force
                $JITAdminConfig | Add-Member -NotePropertyName ApprovalTriggerRoles -NotePropertyValue ([string](ConvertTo-Json -InputObject $TriggerRoles -Compress)) -Force
                $JITAdminConfig | Add-Member -NotePropertyName ApproverRoles -NotePropertyValue ([string](ConvertTo-Json -InputObject $ApproverRoles -Compress)) -Force
                $JITAdminConfig | Add-Member -NotePropertyName RequiredApprovals -NotePropertyValue ([math]::Max(1, ($Request.Body.RequiredApprovals -as [int]))) -Force

                $JITAdminConfig.PartitionKey = 'JITAdminSettings'
                $JITAdminConfig.RowKey = 'JITAdminSettings'

                Add-CIPPAzDataTableEntity @Table -Entity $JITAdminConfig -Force | Out-Null

                $DurationMessage = if ($JITAdminConfig.MaxDuration) {
                    "Successfully set JIT Admin maximum duration to $($JITAdminConfig.MaxDuration)"
                } else {
                    'Successfully removed JIT Admin maximum duration limit'
                }
                $ApprovalMessage = if ($JITAdminConfig.RequireApproval) {
                    "approval required: $($JITAdminConfig.RequiredApprovals) from $($ApproverRoles -join ', ')"
                } else {
                    'approval not required'
                }
                $Message = "$DurationMessage; $ApprovalMessage"

                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info'

                @{
                    Results = $Message
                }
            }
            default {
                $StatusCode = [HttpStatusCode]::BadRequest
                @{
                    Results = 'Error: Invalid action. Use Get or Set.'
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = @{
            Results = "Error: $($ErrorMessage.NormalizedError)"
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to process JIT Admin settings: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
