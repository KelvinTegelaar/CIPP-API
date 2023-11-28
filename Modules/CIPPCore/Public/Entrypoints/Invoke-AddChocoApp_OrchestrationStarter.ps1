using namespace System.Net

Function Invoke-AddChocoApp_OrchestrationStarter {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-LogMessage -API 'ChocoApps' -message 'Attempted to start upload but an instance was already running.' -sev Info
    $InstanceId = Start-NewOrchestration -FunctionName 'Applications_Orchestrator'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Write-LogMessage -API 'ChocoApps' -message 'Started uploading applications to tenants' -sev Info
    $Results = [pscustomobject]@{'Results' = 'Started application queue' }

    Write-Host ($Orchestrator | ConvertTo-Json)


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $results
        })

}