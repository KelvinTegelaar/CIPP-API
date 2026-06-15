function Invoke-ExecJITAdminSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
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
            $JITAdminConfig = @{
                PartitionKey = 'JITAdminSettings'
                RowKey       = 'JITAdminSettings'
                MaxDuration  = $null  # null means no limit
            }
        }

        $Action = if ($Request.Body.Action) { $Request.Body.Action } else { $Request.Query.Action }

        $Results = switch ($Action) {
            'Get' {
                @{
                    MaxDuration = $JITAdminConfig.MaxDuration
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

                $JITAdminConfig.PartitionKey = 'JITAdminSettings'
                $JITAdminConfig.RowKey = 'JITAdminSettings'

                Add-CIPPAzDataTableEntity @Table -Entity $JITAdminConfig -Force | Out-Null

                $Message = if ($JITAdminConfig.MaxDuration) {
                    "Successfully set JIT Admin maximum duration to $($JITAdminConfig.MaxDuration)"
                } else {
                    'Successfully removed JIT Admin maximum duration limit'
                }

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
