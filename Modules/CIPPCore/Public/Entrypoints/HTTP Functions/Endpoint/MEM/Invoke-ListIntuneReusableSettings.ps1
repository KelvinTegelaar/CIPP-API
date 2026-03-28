function Invoke-ListIntuneReusableSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter
    $SettingId = $Request.Query.ID

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }

    if ($TenantFilter -eq 'AllTenants') {
        # AllTenants functionality
        $Table = Get-CIPPTable -TableName 'cacheIntuneReusableSettings'
        $PartitionKey = 'IntuneReusableSetting'
        $Filter = "PartitionKey eq '$PartitionKey'"
        $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
        $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
        $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
        if ($RunningQueue) {
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                QueueId      = $RunningQueue.RowKey
            }
        } elseif (!$Rows -and !$RunningQueue) {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name 'Reusable Settings - All Tenants' -Link '/endpoint/MEM/reusable-settings?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                QueueId      = $Queue.RowKey
            }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'IntuneReusableSettingsOrchestrator'
                QueueFunction    = @{
                    FunctionName = 'GetTenants'
                    QueueId      = $Queue.RowKey
                    TenantParams = @{
                        IncludeErrors = $true
                    }
                    DurableName  = 'ListIntuneReusableSettingsAllTenants'
                }
                SkipLog          = $true
            }
            Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
        } else {
            $Metadata = [PSCustomObject]@{
                QueueId = $RunningQueue.RowKey ?? $null
            }
            $Settings = foreach ($policy in $Rows) {
                ($policy.Policy | ConvertFrom-Json)
            }
        }
        $Body = [PSCustomObject]@{
            Results  = @($Settings)
            Metadata = $Metadata
        }
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = $Body
            })
    }

    try {
        $baseUri = 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings'
        $selectFields = @(
            'id'
            'settingInstance'
            'displayName'
            'description'
            'settingDefinitionId'
            'version'
            'referencingConfigurationPolicyCount'
            'createdDateTime'
            'lastModifiedDateTime'
        )
        $selectQuery = '?$select=' + ($selectFields -join ',')
        $uri = if ($SettingId) { "$baseUri/$SettingId$selectQuery" } else { "$baseUri$selectQuery" }

        $Settings = New-GraphGetRequest -uri $uri -tenantid $TenantFilter
        if (-not $Settings) { $Settings = @() }

        $Settings = @($Settings) | Where-Object { $_ } | ForEach-Object {
            $setting = $_

            $rawJson = $null
            try {
                $rawJson = $setting | ConvertTo-Json -Depth 50 -Compress -ErrorAction Stop
            } catch {
                $rawJson = $null
            }

            $setting | Add-Member -NotePropertyName 'RawJSON' -NotePropertyValue $rawJson -Force -PassThru
        }
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $logMessage = "Failed to retrieve reusable policy settings: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $logMessage -Sev Error -LogData $ErrorMessage
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @{ Results = $logMessage }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [PSCustomObject]@{
                Results  = @($Settings | Where-Object -Property id -NE $null)
                Metadata = $null
            }
        })
}
