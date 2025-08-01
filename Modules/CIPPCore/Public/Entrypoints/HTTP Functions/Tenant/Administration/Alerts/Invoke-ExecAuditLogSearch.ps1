function Invoke-ExecAuditLogSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Query.Action ?? $Request.Body.Action

    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    switch ($Action) {
        'ProcessLogs' {
            $SearchId = $Request.Query.SearchId ?? $Request.Body.SearchId
            $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
            if (!$SearchId) {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = 'SearchId is required'
                    })
                return
            }

            $Search = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/security/auditLog/queries/$SearchId" -AsApp $true -TenantId $TenantFilter
            Write-Information ($Search | ConvertTo-Json -Depth 10)

            $Entity = [PSCustomObject]@{
                PartitionKey = [string]'Search'
                RowKey       = [string]$SearchId
                Tenant       = [string]$TenantFilter
                DisplayName  = [string]$Search.displayName
                StartTime    = [datetime]$Search.filterStartDateTime
                EndTime      = [datetime]$Search.filterEndDateTime
                Query        = [string]($Search | ConvertTo-Json -Compress)
                CippStatus   = [string]'Pending'
            }
            $Table = Get-CIPPTable -TableName 'AuditLogSearches'
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

            Write-LogMessage -headers $Headers -API $APIName -message "Queued search for processing: $($Search.displayName)" -Sev 'Info' -tenant $TenantFilter

            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{
                        resultText = "Search '$($Search.displayName)' queued for processing."
                        state      = 'success'
                    } | ConvertTo-Json -Depth 10 -Compress
                })
        }
        default {
            $Query = $Request.Body
            if (!$Query.TenantFilter) {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = 'TenantFilter is required'
                    })
                return
            }
            if (!$Query.StartTime -or !$Query.EndTime) {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = 'StartTime and EndTime are required'
                    })
                return
            }

            # Convert StartTime and EndTime to DateTime from unixtime
            if ($Query.StartTime -match '^\d+$') {
                $Query.StartTime = [DateTime]::UnixEpoch.AddSeconds([long]$Query.StartTime)
            } else {
                $Query.StartTime = [DateTime]$Query.StartTime
            }

            if ($Query.EndTime -match '^\d+$') {
                $Query.EndTime = [DateTime]::UnixEpoch.AddSeconds([long]$Query.EndTime)
            } else {
                $Query.EndTime = [DateTime]$Query.EndTime
            }

            $Command = Get-Command New-CippAuditLogSearch
            $AvailableParameters = $Command.Parameters.Keys
            $BadProps = foreach ($Prop in $Query.PSObject.Properties.Name) {
                if ($AvailableParameters -notcontains $Prop) {
                    $Prop
                }
            }
            if ($BadProps) {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = "Invalid parameters: $($BadProps -join ', ')"
                    })
                return
            }

            try {
                Write-Information "Executing audit log search with parameters: $($Query | ConvertTo-Json -Depth 10)"

                $Query = $Query | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
                $NewSearch = New-CippAuditLogSearch @Query

                if ($NewSearch) {
                    Write-LogMessage -headers $Headers -API $APIName -message "Created audit log search: $($NewSearch.displayName)" -Sev 'Info' -tenant $TenantFilter
                    $Results = @{
                        resultText = "Created audit log search: $($NewSearch.displayName)"
                        state      = 'success'
                        details    = $NewSearch
                    }
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -message 'Failed to create audit log search' -Sev 'Error' -tenant $TenantFilter
                    $Results = @{
                        resultText = 'Failed to initiate search'
                        state      = 'error'
                    }
                }
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = $Results
                    })
            } catch {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = $_.Exception.Message
                    })
            }
        }
    }
}
