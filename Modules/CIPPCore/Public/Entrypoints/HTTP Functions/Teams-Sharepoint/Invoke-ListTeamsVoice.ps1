function Invoke-ListTeamsVoice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName 'cacheTeamsVoice'
            $PartitionKey = 'TeamsVoice'
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
                $Queue = New-CippQueueEntry -Name 'Teams Voice - All Tenants' -Link '/teams-share/teams/business-voice?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'TeamsVoiceOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListTeamsVoiceAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $GraphRequest = foreach ($policy in $Rows) {
                    ($policy.Policy | ConvertFrom-Json)
                }
            }
        } else {
            $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
            $Users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter)
            $Skip = 0
            $GraphRequest = do {
                Write-Host "Getting page $Skip"
                $Results = New-TeamsAPIGetRequest -uri "https://api.interfaces.records.teams.microsoft.com/Skype.TelephoneNumberMgmt/Tenants/$($TenantId)/telephone-numbers?skip=$($Skip)&locale=en-US&top=999" -tenantid $TenantFilter
                $data = $Results.TelephoneNumbers | ForEach-Object {
                    $CompleteRequest = $_ | Select-Object *, @{Name = 'AssignedTo'; Expression = { @($(Users | Where-Object -Property id -EQ $_.TargetId)) } }
                    if ($CompleteRequest.AcquisitionDate) {
                        $CompleteRequest.AcquisitionDate = $_.AcquisitionDate -split 'T' | Select-Object -First 1
                    } else {
                        $CompleteRequest | Add-Member -NotePropertyName 'AcquisitionDate' -NotePropertyValue 'Unknown' -Force
                    }
                    $CompleteRequest.AssignedTo ? $null : ($CompleteRequest | Add-Member -NotePropertyName 'AssignedTo' -NotePropertyValue 'Unassigned' -Force)
                    $CompleteRequest
                }
                $Skip = $Skip + 999
                $Data
            } while ($data.Count -eq 999)
            $GraphRequest = $GraphRequest | Where-Object { $_.TelephoneNumber }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    $Body = [PSCustomObject]@{
        Results  = @($GraphRequest | Where-Object { $null -ne $_.TelephoneNumber })
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
